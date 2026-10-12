import Foundation

/// Thin async wrapper around the Qinglong REST API.
///
/// Supports both authentication flows:
///  - **User login**: `POST /api/user/login` -> token, then call `/api/*` with `Bearer <token>`.
///  - **Open API**:   `POST /api/apps/token` (client_id + client_secret) -> access_token,
///                     then call `/open/*` with `Bearer <access_token>`.
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
        let reencoded = try JSONSerialization.data(withJSONObject: dataObj)
        return try JSONDecoder().decode([CronTask].self, from: reencoded)
    }

    func cronLog(id: String) async throws -> String {
        let data = try await request(path: "/crons/\(id)/log", method: "GET")
        guard let dataObj = try unwrap(data) else { return "" }
        if let s = dataObj as? String { return s }
        return String(data: try JSONSerialization.data(withJSONObject: dataObj), encoding: .utf8) ?? ""
    }

    func runCron(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/crons/run", method: "PUT", body: body)
        try ensureOK(data)
    }

    func stopCron(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/crons/stop", method: "PUT", body: body)
        try ensureOK(data)
    }

    func enableCron(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/crons/enable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func disableCron(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/crons/disable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func pinCron(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/crons/pin", method: "PUT", body: body)
        try ensureOK(data)
    }

    func saveCron(_ cron: CronTask, isNew: Bool) async throws {
        let payload: [String: Any] = [
            "id": cron._id ?? "",
            "name": cron.name,
            "command": cron.command,
            "schedule": cron.schedule,
            "labels": cron.labels
        ]
        let body = try jsonBody(payload)
        let data = try await request(path: "/crons", method: isNew ? "POST" : "PUT", body: body)
        try ensureOK(data)
    }

    func deleteCron(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/crons", method: "DELETE", body: body)
        try ensureOK(data)
    }

    // MARK: - Environment

    func getEnvs() async throws -> [EnvVar] {
        let data = try await request(path: "/envs", method: "GET")
        guard let dataObj = try unwrap(data) else { return [] }
        let reencoded = try JSONSerialization.data(withJSONObject: dataObj)
        return try JSONDecoder().decode([EnvVar].self, from: reencoded)
    }

    func saveEnv(_ env: EnvVar, isNew: Bool) async throws {
        var payload: [String: Any] = [
            "name": env.name,
            "value": env.value,
            "remarks": env.remarks ?? ""
        ]
        if !isNew { payload["id"] = env._id ?? env.idField ?? "" }
        let body = try jsonBody(payload)
        let data = try await request(path: "/envs", method: isNew ? "POST" : "PUT", body: body)
        try ensureOK(data)
    }

    func enableEnv(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/envs/enable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func disableEnv(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
        let data = try await request(path: "/envs/disable", method: "PUT", body: body)
        try ensureOK(data)
    }

    func deleteEnv(ids: [String]) async throws {
        let body = try jsonBody(["ids": ids])
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
}
