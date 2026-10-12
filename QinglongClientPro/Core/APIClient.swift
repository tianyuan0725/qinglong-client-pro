import Foundation

/// Thin async wrapper around the Qinglong REST API.
///
/// Supports both authentication flows:
///  - **User login**: `POST /api/user/login` -> token, then call `/api/*` with `Bearer <token>`.
///  - **Open API**:   `POST /api/apps/token` (client_id + client_secret) -> access_token,
///                     then call `/open/*` with `Bearer <access_token>`.
///
/// Compatibility notes:
///  - v2.20+ uses numeric ids and expects plain numeric arrays as mutation bodies
///    (e.g. `PUT /crons/run` body is `[1,2,3]`). Older panels used Mongo string ids
///    and `{"ids": [...]}` bodies. We detect and send both shapes accordingly.
///  - v2.20+ `GET /api/crons` returns `{data: [...], total: n}`; older panels
///    returned a plain array. Both are handled.
@MainActor
final class APIClient {
    let baseURL: URL
    let apiPrefix: String
    var token: String?

    private let session: URLSession

    init(baseURL: URL, apiPrefix: String, token: String? = nil) {
        self.baseURL = baseURL
        self.apiPrefix = apiPrefix
        self.token = token
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Low level

    private func request(path: String, method: String, body: Data? = nil, authenticated: Bool = true, prefixOverride: String? = nil) async throws -> Data {
        let prefix = prefixOverride ?? apiPrefix
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        let fullPath = (prefix + path).replacingOccurrences(of: "//", with: "/")
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + fullPath
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("QinglongClientPro/1.0", forHTTPHeaderField: "User-Agent")
        if authenticated, let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if http.statusCode >= 400 { throw APIError.httpError(http.statusCode) }
        }
        return data
    }

    /// Reads `{code, message, data}` and throws on `code != 200`.
    private func unwrap(_ data: Data) throws -> Any? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let code = json["code"] as? Int ?? 200
        if code != 200 {
            let msg = json["message"] as? String ?? "请求失败 (code \(code))"
            throw APIError.serverMessage(msg)
        }
        return json["data"]
    }

    private func ensureOK(_ data: Data) throws {
        _ = try unwrap(data)
    }

    private func jsonBody(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    /// Normalizes a list response into a JSON array:
    /// handles a plain array (legacy) and `{data: [...], total: n}` (v2.20+ pagination).
    private func dataArray(from dataObj: Any) -> Any {
        if let dict = dataObj as? [String: Any] {
            if let arr = dict["data"] { return arr }
            if let arr = dict["rows"] { return arr }
            return []
        }
        return dataObj
    }

    /// v2.20+ expects a plain numeric array for run/stop/enable/disable/pin/delete;
    /// legacy panels expect `{"ids": [strings]}`.
    private func idPayload(_ ids: [String]) throws -> Data {
        let nums = ids.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if !ids.isEmpty && nums.count == ids.count {
            return try JSONSerialization.data(withJSONObject: nums)
        }
        return try jsonBody(["ids": ids])
    }

    // MARK: - Auth

    func authenticate(authType: AuthType, username: String, password: String, clientID: String, clientSecret: String) async throws -> String {
        // Auth endpoints always live under /api, even when using the Open API (which
        // then calls data endpoints under /open with the obtained access token).
        if authType == .openApi {
            let body = try jsonBody(["client_id": clientID, "client_secret": clientSecret])
            let data = try await request(path: "/apps/token", method: "POST", body: body, authenticated: false, prefixOverride: "/api")
            return try extractToken(from: data, key: "access_token")
        } else {
            let body = try jsonBody(["username": username, "password": password])
            let data = try await request(path: "/user/login", method: "POST", body: body, authenticated: false, prefixOverride: "/api")
            return try extractToken(from: data, key: "token")
        }
    }

    private func extractToken(from data: Data, key: String) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.invalidResponse }
        let code = json["code"] as? Int ?? 200
        if code == 420 {
            // 面板开启两步验证：密码正确但需二次验证码
            throw APIError.twoFactorRequired
        }
        if code != 200 {
            throw APIError.serverMessage(json["message"] as? String ?? "认证失败")
        }
        guard let dataObj = json["data"] else { throw APIError.invalidResponse }
        if let dict = dataObj as? [String: Any], let t = dict[key] as? String { return t }
        if let str = dataObj as? String { return str }
        throw APIError.invalidResponse
    }

    // MARK: - Cron

    func getCrons() async throws -> [CronTask] {
        let data = try await request(path: "/crons", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let reencoded = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return try JSONDecoder().decode([CronTask].self, from: reencoded)
    }

    func cronLog(id: String) async throws -> String {
        let data = try await request(path: "/crons/\(id)/log", method: "GET")
        guard let dataObj = try unwrap(data) else { return "" }
        if let s = dataObj as? String { return s }
        return String(data: try JSONSerialization.data(withJSONObject: dataObj), encoding: .utf8) ?? ""
    }

    func runCron(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/crons/run", method: "PUT", body: body)
        try ensureOK(data)
    }

    func stopCron(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/crons/stop", method: "PUT", body: body)
        try ensureOK(data)
    }

    func enableCron(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/crons/enable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func disableCron(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/crons/disable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func pinCron(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/crons/pin", method: "PUT", body: body)
        try ensureOK(data)
    }

    func saveCron(_ cron: CronTask, isNew: Bool) async throws {
        var payload: [String: Any] = [
            "name": cron.name,
            "command": cron.command,
            "schedule": cron.schedule,
            "labels": cron.labels
        ]
        if !isNew {
            if let n = cron.numericID {
                payload["id"] = n
            } else {
                payload["id"] = cron.id
            }
        }
        let body = try jsonBody(payload)
        let data = try await request(path: "/crons", method: isNew ? "POST" : "PUT", body: body)
        try ensureOK(data)
    }

    func deleteCron(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/crons", method: "DELETE", body: body)
        try ensureOK(data)
    }

    // MARK: - Environment

    func getEnvs() async throws -> [EnvVar] {
        let data = try await request(path: "/envs", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let reencoded = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return try JSONDecoder().decode([EnvVar].self, from: reencoded)
    }

    func saveEnv(_ env: EnvVar, isNew: Bool) async throws {
        var payload: [String: Any] = [
            "name": env.name,
            "value": env.value,
            "remarks": env.remarks ?? ""
        ]
        if !isNew {
            if let n = env.numericID {
                payload["id"] = n
            } else {
                payload["id"] = env.id
            }
        }
        let body = try jsonBody(payload)
        let data = try await request(path: "/envs", method: isNew ? "POST" : "PUT", body: body)
        try ensureOK(data)
    }

    func enableEnv(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/envs/enable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func disableEnv(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/envs/disable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func deleteEnv(ids: [String]) async throws {
        let body = try idPayload(ids)
        let data = try await request(path: "/envs", method: "DELETE", body: body)
        try ensureOK(data)
    }

    // MARK: - System

    func getSystem() async throws -> SystemInfo? {
        let data = try await request(path: "/system", method: "GET")
        guard let dataObj = try unwrap(data) else { return nil }
        let reencoded = try JSONSerialization.data(withJSONObject: dataObj)
        return try JSONDecoder().decode(SystemInfo.self, from: reencoded)
    }

    // MARK: - Low-level variants

    /// Like `request` but supports query items (needed by scripts/configs/logs).
    private func requestQ(path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil, authenticated: Bool = true, prefixOverride: String? = nil) async throws -> Data {
        let prefix = prefixOverride ?? apiPrefix
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        let fullPath = (prefix + path).replacingOccurrences(of: "//", with: "/")
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + fullPath
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("QinglongClientPro/1.1", forHTTPHeaderField: "User-Agent")
        if authenticated, let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if http.statusCode >= 400 { throw APIError.httpError(http.statusCode) }
        }
        return data
    }

    private func numericArray(_ ids: [Int]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ids)
    }

    /// Boxes an optional Int as JSON value (Int or null) for nullable numeric fields.
    private func nullableInt(_ n: Int?) -> Any {
        n.map { $0 as Any } ?? NSNull()
    }

    /// Returns raw response text (used by streamed log endpoints that are not JSON).
    private func getText(path: String, query: [URLQueryItem] = []) async throws -> String {
        let data = try await requestQ(path: path, method: "GET", query: query)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Scripts / Files

    func getFileList(path: String?) async throws -> [FileNode] {
        var q: [URLQueryItem] = []
        if let p = path, !p.isEmpty { q.append(URLQueryItem(name: "path", value: p)) }
        let data = try await requestQ(path: "/scripts", method: "GET", query: q)
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return try JSONDecoder().decode([FileNode].self, from: re)
    }

    func getFileContent(path: String, file: String) async throws -> String {
        let q = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "file", value: file)]
        let data = try await requestQ(path: "/scripts/detail", method: "GET", query: q)
        guard let dataObj = try unwrap(data) else { return "" }
        if let s = dataObj as? String { return s }
        if let d = dataObj as? [String: Any], let s = d["data"] as? String { return s }
        return ""
    }

    func saveFileContent(path: String, filename: String, content: String) async throws {
        let body = try jsonBody(["filename": filename, "path": path, "content": content])
        let data = try await request(path: "/scripts", method: "PUT", body: body)
        try ensureOK(data)
    }

    func createFile(path: String, filename: String, content: String) async throws {
        let body = try jsonBody(["filename": filename, "path": path, "content": content])
        let data = try await request(path: "/scripts", method: "POST", body: body)
        try ensureOK(data)
    }

    func createDirectory(path: String, dirname: String) async throws {
        let body = try jsonBody(["path": path, "directory": dirname])
        let data = try await request(path: "/scripts", method: "POST", body: body)
        try ensureOK(data)
    }

    func deleteFile(path: String, filename: String) async throws {
        let body = try jsonBody(["filename": filename, "path": path])
        let data = try await request(path: "/scripts", method: "DELETE", body: body)
        try ensureOK(data)
    }

    func renameFile(path: String, filename: String, newFilename: String) async throws {
        let body = try jsonBody(["filename": filename, "path": path, "newFilename": newFilename])
        let data = try await request(path: "/scripts/rename", method: "PUT", body: body)
        try ensureOK(data)
    }

    @discardableResult
    func runScript(path: String, filename: String, content: String) async throws -> String {
        let body = try jsonBody(["filename": filename, "path": path, "content": content])
        let data = try await request(path: "/scripts/run", method: "PUT", body: body)
        guard let dataObj = try unwrap(data) else { return "" }
        if let pid = dataObj as? Int { return String(pid) }
        if let d = dataObj as? [String: Any], let pid = d["data"] { return "\(pid)" }
        return ""
    }

    func stopScript(path: String, filename: String, pid: Int?) async throws {
        var dict: [String: Any] = ["filename": filename, "path": path]
        if let pid { dict["pid"] = pid }
        let data = try await request(path: "/scripts/stop", method: "PUT", body: try jsonBody(dict))
        try ensureOK(data)
    }

    // MARK: - Dependencies

    func getDependencies(type: Int? = nil, search: String? = nil, status: String? = nil) async throws -> [Dependency] {
        var q: [URLQueryItem] = []
        if let t = type { q.append(URLQueryItem(name: "type", value: String(t))) }
        if let s = search, !s.isEmpty { q.append(URLQueryItem(name: "searchValue", value: s)) }
        if let st = status, !st.isEmpty { q.append(URLQueryItem(name: "status", value: st)) }
        let data = try await requestQ(path: "/dependencies", method: "GET", query: q)
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return try JSONDecoder().decode([Dependency].self, from: re)
    }

    func createDependencies(_ items: [[String: Any]]) async throws {
        let data = try await request(path: "/dependencies", method: "POST", body: try JSONSerialization.data(withJSONObject: items))
        try ensureOK(data)
    }

    func updateDependency(id: Int, name: String, type: Int, remark: String) async throws {
        let body = try jsonBody(["id": id, "name": name, "type": type, "remark": remark])
        let data = try await request(path: "/dependencies", method: "PUT", body: body)
        try ensureOK(data)
    }

    func deleteDependencies(ids: [Int], force: Bool = false) async throws {
        let path = force ? "/dependencies/force" : "/dependencies"
        let data = try await request(path: path, method: "DELETE", body: try numericArray(ids))
        try ensureOK(data)
    }

    func reinstallDependencies(ids: [Int]) async throws {
        let data = try await request(path: "/dependencies/reinstall", method: "PUT", body: try numericArray(ids))
        try ensureOK(data)
    }

    func cancelDependencies(ids: [Int]) async throws {
        let data = try await request(path: "/dependencies/cancel", method: "PUT", body: try numericArray(ids))
        try ensureOK(data)
    }

    // MARK: - Config files

    func getConfigFiles() async throws -> [ConfigFile] {
        let data = try await request(path: "/configs/files", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return try JSONDecoder().decode([ConfigFile].self, from: re)
    }

    func getConfigContent(path: String) async throws -> String {
        let q = [URLQueryItem(name: "path", value: path)]
        let data = try await requestQ(path: "/configs/detail", method: "GET", query: q)
        guard let dataObj = try unwrap(data) else { return "" }
        if let s = dataObj as? String { return s }
        if let d = dataObj as? [String: Any], let s = d["data"] as? String { return s }
        return ""
    }

    func saveConfig(name: String, content: String) async throws {
        let body = try jsonBody(["name": name, "content": content])
        let data = try await request(path: "/configs/save", method: "POST", body: body)
        try ensureOK(data)
    }

    // MARK: - Subscriptions

    func getSubscriptions() async throws -> [Subscription] {
        let data = try await request(path: "/subscriptions", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return try JSONDecoder().decode([Subscription].self, from: re)
    }

    func createSubscription(_ payload: [String: Any]) async throws {
        let data = try await request(path: "/subscriptions", method: "POST", body: try jsonBody(payload))
        try ensureOK(data)
    }

    func updateSubscription(_ payload: [String: Any]) async throws {
        let data = try await request(path: "/subscriptions", method: "PUT", body: try jsonBody(payload))
        try ensureOK(data)
    }

    func deleteSubscriptions(ids: [Int]) async throws {
        let data = try await request(path: "/subscriptions", method: "DELETE", body: try numericArray(ids))
        try ensureOK(data)
    }

    func runSubscriptions(ids: [Int]) async throws {
        let data = try await request(path: "/subscriptions/run", method: "PUT", body: try numericArray(ids))
        try ensureOK(data)
    }

    func stopSubscriptions(ids: [Int]) async throws {
        let data = try await request(path: "/subscriptions/stop", method: "PUT", body: try numericArray(ids))
        try ensureOK(data)
    }

    func enableSubscriptions(ids: [Int]) async throws {
        let data = try await request(path: "/subscriptions/enable", method: "PUT", body: try numericArray(ids))
        try ensureOK(data)
    }

    func disableSubscriptions(ids: [Int]) async throws {
        let data = try await request(path: "/subscriptions/disable", method: "PUT", body: try numericArray(ids))
        try ensureOK(data)
    }

    func subscriptionLog(id: Int) async throws -> String {
        let q = [URLQueryItem(name: "tail", value: "true"), URLQueryItem(name: "limit", value: "200000")]
        let data = try await requestQ(path: "/subscriptions/\(id)/log", method: "GET", query: q)
        guard let dataObj = try unwrap(data) else { return "" }
        if let s = dataObj as? String { return s }
        if let d = dataObj as? [String: Any], let s = d["data"] as? String { return s }
        return ""
    }

    // MARK: - Open API Apps

    func getApps() async throws -> [AppItem] {
        let data = try await request(path: "/apps", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return try JSONDecoder().decode([AppItem].self, from: re)
    }

    func createApp(name: String, scopes: [String]) async throws {
        let body = try jsonBody(["name": name, "scopes": scopes])
        let data = try await request(path: "/apps", method: "POST", body: body)
        try ensureOK(data)
    }

    func updateApp(id: Int, name: String, scopes: [String]) async throws {
        let body = try jsonBody(["id": id, "name": name, "scopes": scopes])
        let data = try await request(path: "/apps", method: "PUT", body: body)
        try ensureOK(data)
    }

    func deleteApps(ids: [Int]) async throws {
        let data = try await request(path: "/apps", method: "DELETE", body: try numericArray(ids))
        try ensureOK(data)
    }

    @discardableResult
    func resetAppSecret(id: Int) async throws -> String {
        let data = try await request(path: "/apps/\(id)/reset-secret", method: "PUT")
        guard let dataObj = try unwrap(data) else { return "" }
        if let s = dataObj as? String { return s }
        if let d = dataObj as? [String: Any] {
            if let s = d["data"] as? String { return s }
            if let s = d["client_secret"] as? String { return s }
        }
        return ""
    }

    // MARK: - System config & info

    func getSystemConfig() async throws -> SystemConfig? {
        let data = try await request(path: "/system/config", method: "GET")
        guard let dataObj = try unwrap(data) else { return nil }
        let re = try JSONSerialization.data(withJSONObject: dataObj)
        return try JSONDecoder().decode(SystemConfig.self, from: re)
    }

    func updatePanelTitle(_ value: String) async throws {
        try ensureOK(await request(path: "/system/config/panel-title", method: "PUT",
                                  body: try jsonBody(["panelTitle": value])))
    }

    func updateTimezone(_ value: String) async throws {
        try ensureOK(await request(path: "/system/config/timezone", method: "PUT",
                                  body: try jsonBody(["timezone": value])))
    }

    func updateLogRemoveFrequency(_ value: Int?) async throws {
        try ensureOK(await request(path: "/system/config/log-remove-frequency", method: "PUT",
                                  body: try jsonBody(["logRemoveFrequency": nullableInt(value)])))
    }

    func updateCronConcurrency(_ value: Int?) async throws {
        try ensureOK(await request(path: "/system/config/cron-concurrency", method: "PUT",
                                  body: try jsonBody(["cronConcurrency": nullableInt(value)])))
    }

    func updateDependenceProxy(_ value: String) async throws {
        try ensureOK(await request(path: "/system/config/dependence-proxy", method: "PUT",
                                  body: try jsonBody(["dependenceProxy": value])))
    }

    func updateNodeMirror(_ value: String) async throws {
        try ensureOK(await request(path: "/system/config/node-mirror", method: "PUT",
                                  body: try jsonBody(["nodeMirror": value])))
    }

    func updatePythonMirror(_ value: String) async throws {
        try ensureOK(await request(path: "/system/config/python-mirror", method: "PUT",
                                  body: try jsonBody(["pythonMirror": value])))
    }

    func updateLinuxMirror(_ value: String) async throws {
        try ensureOK(await request(path: "/system/config/linux-mirror", method: "PUT",
                                  body: try jsonBody(["linuxMirror": value])))
    }

    func updateGlobalSshKey(_ value: String) async throws {
        try ensureOK(await request(path: "/system/config/global-ssh-key", method: "PUT",
                                  body: try jsonBody(["globalSshKey": value])))
    }

    func sendNotify(title: String, content: String) async throws {
        try ensureOK(await request(path: "/system/notify", method: "PUT",
                                  body: try jsonBody(["title": title, "content": content])))
    }

    func getPanelInfo() async throws -> PanelInfo? {
        let data = try await request(path: "/system", method: "GET")
        guard let dataObj = try unwrap(data) else { return nil }
        let re = try JSONSerialization.data(withJSONObject: dataObj)
        return try JSONDecoder().decode(PanelInfo.self, from: re)
    }

    func getSystemLog(limit: Int = 100000) async throws -> String {
        try await getText(path: "/system/log", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    // MARK: - 当前用户 (GET/PUT /api/user)

    func getCurrentUser() async throws -> UserInfo {
        let data = try await request(path: "/user", method: "GET")
        guard let dataObj = try unwrap(data) else { return UserInfo() }
        let re = try JSONSerialization.data(withJSONObject: dataObj)
        return (try? JSONDecoder().decode(UserInfo.self, from: re)) ?? UserInfo()
    }

    /// 修改用户名 / 密码（PUT /api/user，两个字段均必填）。
    func updateUsernameAndPassword(username: String, password: String) async throws {
        let body = try jsonBody(["username": username, "password": password])
        try ensureOK(try await request(path: "/user", method: "PUT", body: body))
    }

    // MARK: - 登录日志 (GET /api/user/login-log)

    func getLoginLogs() async throws -> [LoginLogEntry] {
        let data = try await request(path: "/user/login-log", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return (try? JSONDecoder().decode([LoginLogEntry].self, from: re)) ?? []
    }

    // MARK: - 通知设置 (GET/PUT /api/user/notification)

    func getNotificationConfig() async throws -> NotificationConfig {
        let data = try await request(path: "/user/notification", method: "GET")
        guard let dataObj = try unwrap(data) else { return NotificationConfig() }
        let re = try JSONSerialization.data(withJSONObject: dataObj)
        return (try? JSONDecoder().decode(NotificationConfig.self, from: re)) ?? NotificationConfig()
    }

    func updateNotificationConfig(_ payload: [String: String]) async throws {
        let body = try jsonBody(payload)
        try ensureOK(try await request(path: "/user/notification", method: "PUT", body: body))
    }

    // MARK: - 系统日志文件 (GET /api/logs)

    func getLogFiles() async throws -> [FileNode] {
        let data = try await request(path: "/logs", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return (try? JSONDecoder().decode([FileNode].self, from: re)) ?? []
    }

    func getLogFileContent(path: String, file: String, tail: Bool = true) async throws -> String {
        var q = [URLQueryItem(name: "file", value: file)]
        if !path.isEmpty { q.append(URLQueryItem(name: "path", value: path)) }
        if tail { q.append(URLQueryItem(name: "tail", value: "true")) }
        let data = try await requestQ(path: "/logs/detail", method: "GET", query: q)
        // 响应为 JSON：{ code, data, logStatus, offset, nextOffset, total, truncated }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["data"] as? String { return text }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func deleteLogFile(path: String, file: String) async throws {
        let body = try jsonBody(["filename": file, "path": path])
        try ensureOK(try await request(path: "/logs", method: "DELETE", body: body))
    }

    /// 两步验证 2FA (PUT /api/user/two-factor/login)

    /// 普通登录返回 code 420（密码正确但开启两步验证）后，携带 TOTP 验证码完成登录。
    /// 注意：该端点限流 20 次/15 分钟。
    func twoFactorLogin(code: String, username: String, password: String) async throws -> String {
        let body = try jsonBody(["code": code, "username": username, "password": password])
        let data = try await request(path: "/user/two-factor/login", method: "PUT", body: body, authenticated: false, prefixOverride: "/api")
        return try extractToken(from: data, key: "token")
    }

    // MARK: - 脚本下载 / 历史版本 (v2.20+)

    /// 下载脚本文件二进制内容（POST /api/scripts/download，body {filename, path}）。
    func downloadScript(path: String, filename: String) async throws -> Data {
        let body = try jsonBody(["filename": filename, "path": path])
        return try await request(path: "/scripts/download", method: "POST", body: body)
    }

    /// 脚本历史版本列表（GET /api/scripts/history?path=&filename=）。
    func getScriptHistory(path: String, filename: String) async throws -> [ScriptHistoryItem] {
        var q = [URLQueryItem(name: "filename", value: filename)]
        if !path.isEmpty { q.append(URLQueryItem(name: "path", value: path)) }
        let data = try await requestQ(path: "/scripts/history", method: "GET", query: q)
        guard let dataObj = try unwrap(data) else { return [] }
        let re = try JSONSerialization.data(withJSONObject: dataArray(from: dataObj))
        return (try? JSONDecoder().decode([ScriptHistoryItem].self, from: re)) ?? []
    }

    /// 单个历史版本内容（GET /api/scripts/history/detail?path=&filename=&id=<uuid>）。
    func getScriptHistoryDetail(path: String, filename: String, id: String) async throws -> String {
        var q = [URLQueryItem(name: "filename", value: filename), URLQueryItem(name: "id", value: id)]
        if !path.isEmpty { q.append(URLQueryItem(name: "path", value: path)) }
        let data = try await requestQ(path: "/scripts/history/detail", method: "GET", query: q)
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["data"] as? String { return text }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 恢复到指定历史版本（PUT /api/scripts/history/restore，id 为 UUID，expectedHash 为 64 位 hex）。
    func restoreScriptHistory(path: String, filename: String, id: String, expectedHash: String) async throws {
        let body = try jsonBody([
            "path": path,
            "filename": filename,
            "id": id,
            "expectedHash": expectedHash,
        ])
        try ensureOK(try await request(path: "/scripts/history/restore", method: "PUT", body: body))
    }

    // MARK: - 面板数据导出 / 导入 (v2.20+)

    /// 导出面板数据 zip 二进制（PUT /api/system/data/export）。types 为空表示全部。
    func exportPanelData(types: [String] = []) async throws -> Data {
        var body: Data?
        if !types.isEmpty {
            body = try jsonBody(["type": types])
        }
        return try await request(path: "/system/data/export", method: "PUT", body: body)
    }

    /// 导入面板数据 zip（PUT /api/system/data/import，multipart 字段名 data）。
    func importPanelData(fileURL: URL) async throws {
        guard let fileData = try? Data(contentsOf: fileURL) else { throw APIError.invalidResponse }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: exportImportURL)
        req.httpMethod = "PUT"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("QinglongClientPro/2.0", forHTTPHeaderField: "User-Agent")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var payload = Data()
        payload.append("--\(boundary)\r\n".data(using: .utf8)!)
        payload.append("Content-Disposition: form-data; name=\"data\"; filename=\"backup.zip\"\r\n".data(using: .utf8)!)
        payload.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        payload.append(fileData)
        payload.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = payload

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.httpError(http.statusCode)
        }
        try ensureOK(data)
    }

    private var exportImportURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path)
            + (apiPrefix + "/system/data/import").replacingOccurrences(of: "//", with: "/")
        return components.url ?? baseURL
    }

    // MARK: - 版本检查 / 面板升级 (v2.20+)

    /// 检查面板是否有新版本（PUT /api/system/update-check）。
    func checkServerUpdate() async throws -> ServerUpdateInfo {
        let data = try await request(path: "/system/update-check", method: "PUT")
        guard let dataObj = try unwrap(data) else { return ServerUpdateInfo() }
        let re = try JSONSerialization.data(withJSONObject: dataObj)
        return (try? JSONDecoder().decode(ServerUpdateInfo.self, from: re)) ?? ServerUpdateInfo()
    }

    /// 触发面板自身升级（PUT /api/system/update）。
    func updatePanelSystem() async throws {
        try ensureOK(try await request(path: "/system/update", method: "PUT"))
    }

    // MARK: - 系统命令执行 (v2.20+，流式)

    /// 执行系统命令（PUT /api/system/command-run）。
    /// 响应体为流式输出（octet-stream），响应头 QL-Task-Pid 为进程号、QL-Task-Log 为日志路径。
    /// 注意：URLSession 会等流结束才返回完整数据，仅适合短命令；长命令可先拿 pid 再 stop。
    func runCommand(_ command: String) async throws -> (pid: String, logPath: String, output: String) {
        let body = try jsonBody(["command": command])
        let (data, resp) = try await session.data(for: buildCommandRequest(path: "/system/command-run", method: "PUT", body: body))
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        let pid = http.value(forHTTPHeaderField: "QL-Task-Pid") ?? ""
        let logPath = http.value(forHTTPHeaderField: "QL-Task-Log") ?? ""
        return (pid, logPath, String(data: data, encoding: .utf8) ?? "")
    }

    /// 停止正在执行的命令（PUT /api/system/command-stop，pid 为数字）。
    func stopCommand(_ command: String, pid: String) async throws {
        let pidNum = Int(pid) ?? 0
        let body = try jsonBody(["command": command, "pid": pidNum])
        try ensureOK(try await request(path: "/system/command-stop", method: "PUT", body: body))
    }

    private func buildCommandRequest(path: String, method: String, body: Data?) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let fullPath = (apiPrefix + path).replacingOccurrences(of: "//", with: "/")
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + fullPath
        var req = URLRequest(url: components.url ?? baseURL)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("QinglongClientPro/2.0", forHTTPHeaderField: "User-Agent")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }
}
