import Foundation

// MARK: - Tolerant primitives

/// Accepts a Bool OR an Int (0/1) from the API and normalizes to Bool.
struct FlexBool: Codable, Hashable {
    let value: Bool
    init(_ value: Bool) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i != 0 }
        else { value = false }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// Accepts Int OR String-encoded number and normalizes to Int.
struct FlexInt: Codable, Hashable {
    let value: Int
    init(_ value: Int) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let s = try? c.decode(String.self), let i = Int(s) { value = i }
        else if let b = try? c.decode(Bool.self) { value = b ? 1 : 0 }
        else { value = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// Accepts Int / Double / numeric String / arbitrary String and normalizes to String,
/// keeping the numeric form for request payloads.
/// Qinglong >= 2.20 uses numeric ids; older panels used Mongo string ids.
struct FlexID: Codable, Hashable {
    let value: String
    let intValue: Int?

    init(_ value: String) {
        self.value = value
        self.intValue = Int(value)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = String(i); intValue = i
        } else if let d = try? c.decode(Double.self) {
            value = String(Int(d)); intValue = Int(d)
        } else if let s = try? c.decode(String.self) {
            value = s; intValue = Int(s)
        } else if let b = try? c.decode(Bool.self) {
            value = b ? "1" : "0"; intValue = b ? 1 : 0
        } else {
            value = ""; intValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let i = intValue { try c.encode(i) } else { try c.encode(value) }
    }
}

// MARK: - Cron task

struct CronTask: Identifiable, Hashable {
    var id: String { _id?.value ?? idField?.value ?? "" }
    var _id: FlexID? = nil       // legacy Mongo string id
    var idField: FlexID? = nil   // "id" key (numeric on v2.20+)
    var name: String = ""
    var command: String = ""
    var schedule: String = ""
    var labels: [String] = []
    var isDisabled: FlexInt? = nil   // v2.20+: 1 = disabled
    var enabled: FlexBool? = nil     // legacy panels
    var status: FlexInt? = nil       // v2.20+: running=0 idle=1 disabled=2 queued=3
    var pid: FlexInt? = nil
    var isSystem: FlexInt? = nil
    var isPinned: FlexInt? = nil
    var lastRunningTime: FlexInt? = nil
    var lastExecutionTime: FlexInt? = nil
    var logPath: String? = nil
    var createdAt: String? = nil

    var numericID: Int? { _id?.intValue ?? idField?.intValue }

    var isEnabled: Bool {
        if let d = isDisabled { return d.value == 0 }
        return enabled?.value ?? true
    }

    // 与面板网页逻辑一致：只看 status 字段。
    // 不要用 pid>0 判断——青龙只在「手动停止」时才清空 pid，
    // 自然跑完的任务 pid 会残留在数据库，会误判成运行中。
    var isRunning: Bool {
        status?.value == 0
    }

    var statusLabel: String {
        if isRunning { return "运行中" }
        switch status?.value {
        case 3: return "排队中"
        case 2: return "已禁用"
        default: return isEnabled ? "空闲中" : "已禁用"
        }
    }

    var lastExecutionText: String? {
        guard let t = lastExecutionTime?.value, t > 0 else { return nil }
        return Self.formatTime(t)
    }

    static func formatTime(_ t: Int) -> String {
        let ts = t > 1_000_000_000_000 ? t / 1000 : t
        guard ts > 946_684_800 else { return "-" }
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}

extension CronTask: Codable {
    enum CodingKeys: String, CodingKey {
        case _id, name, command, schedule, labels, status, pid, isSystem
        case isDisabled, isPinned, enabled
        case idField = "id"
        case lastRunningTime = "last_running_time"
        case lastExecutionTime = "last_execution_time"
        case logPath = "log_path"
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try? c.decodeIfPresent(FlexID.self, forKey: ._id)
        idField = try? c.decodeIfPresent(FlexID.self, forKey: .idField)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil ?? ""
        command = (try? c.decodeIfPresent(String.self, forKey: .command)) ?? nil ?? ""
        schedule = (try? c.decodeIfPresent(String.self, forKey: .schedule)) ?? nil ?? ""
        labels = (try? c.decodeIfPresent([String].self, forKey: .labels)) ?? nil ?? []
        isDisabled = try? c.decodeIfPresent(FlexInt.self, forKey: .isDisabled)
        enabled = try? c.decodeIfPresent(FlexBool.self, forKey: .enabled)
        status = try? c.decodeIfPresent(FlexInt.self, forKey: .status)
        pid = try? c.decodeIfPresent(FlexInt.self, forKey: .pid)
        isSystem = try? c.decodeIfPresent(FlexInt.self, forKey: .isSystem)
        isPinned = try? c.decodeIfPresent(FlexInt.self, forKey: .isPinned)
        lastRunningTime = try? c.decodeIfPresent(FlexInt.self, forKey: .lastRunningTime)
        lastExecutionTime = try? c.decodeIfPresent(FlexInt.self, forKey: .lastExecutionTime)
        logPath = try? c.decodeIfPresent(String.self, forKey: .logPath)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(_id, forKey: ._id)
        try c.encodeIfPresent(idField, forKey: .idField)
        try c.encode(name, forKey: .name)
        try c.encode(command, forKey: .command)
        try c.encode(schedule, forKey: .schedule)
        try c.encode(labels, forKey: .labels)
        try c.encodeIfPresent(isDisabled, forKey: .isDisabled)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(pid, forKey: .pid)
        try c.encodeIfPresent(isSystem, forKey: .isSystem)
        try c.encodeIfPresent(isPinned, forKey: .isPinned)
        try c.encodeIfPresent(lastRunningTime, forKey: .lastRunningTime)
        try c.encodeIfPresent(lastExecutionTime, forKey: .lastExecutionTime)
        try c.encodeIfPresent(logPath, forKey: .logPath)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

// MARK: - Environment variable

struct EnvVar: Identifiable, Hashable {
    var id: String { _id?.value ?? idField?.value ?? UUID().uuidString }
    var _id: FlexID? = nil       // legacy Mongo string id
    var idField: FlexID? = nil   // "id" key (numeric on v2.20+)
    var name: String = ""
    var value: String = ""
    var remarks: String? = nil
    var status: FlexInt? = nil   // 0 = normal, 1 = disabled
    var position: FlexInt? = nil
    var labels: [String]? = nil

    var numericID: Int? { _id?.intValue ?? idField?.intValue }

    var isEnabled: Bool { (status?.value ?? 0) == 0 }
}

extension EnvVar: Codable {
    enum CodingKeys: String, CodingKey {
        case _id, name, value, remarks, status, position, labels
        case idField = "id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try? c.decodeIfPresent(FlexID.self, forKey: ._id)
        idField = try? c.decodeIfPresent(FlexID.self, forKey: .idField)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil ?? ""
        value = (try? c.decodeIfPresent(String.self, forKey: .value)) ?? nil ?? ""
        remarks = try? c.decodeIfPresent(String.self, forKey: .remarks)
        status = try? c.decodeIfPresent(FlexInt.self, forKey: .status)
        position = try? c.decodeIfPresent(FlexInt.self, forKey: .position)
        labels = try? c.decodeIfPresent([String].self, forKey: .labels)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(_id, forKey: ._id)
        try c.encodeIfPresent(idField, forKey: .idField)
        try c.encode(name, forKey: .name)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(remarks, forKey: .remarks)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encodeIfPresent(labels, forKey: .labels)
    }
}

// MARK: - System info

struct SystemInfo: Codable {
    let version: String?
    let currentActiveUser: String?
    let cpu: CPUSub?
    let memory: MemSub?
    let disk: DiskSub?
    let uptime: Double?

    enum CodingKeys: String, CodingKey {
        case version, cpu, memory, disk, uptime
        case currentActiveUser = "currentActiveUser"
    }
}

struct CPUSub: Codable { let model: String?; let usage: Double? }
struct MemSub: Codable { let total: Double?; let usage: Double? }
struct DiskSub: Codable { let total: Double?; let usage: Double? }

extension SystemInfo {
    var memoryGB: String? {
        guard let t = memory?.total else { return nil }
        return String(format: "%.1f GB", t / 1024.0 / 1024.0 / 1024.0)
    }
    var memoryUsageText: String? {
        guard let u = memory?.usage else { return nil }
        return String(format: "%.1f%%", u)
    }
    var cpuUsageText: String? {
        guard let u = cpu?.usage else { return nil }
        return String(format: "%.1f%%", u)
    }
    var diskUsageText: String? {
        guard let u = disk?.usage else { return nil }
        return String(format: "%.1f%%", u)
    }
    var uptimeText: String? {
        guard let u = uptime else { return nil }
        let d = Int(u / 86400)
        let h = Int((u.truncatingRemainder(dividingBy: 86400)) / 3600)
        if d > 0 { return "\(d) 天 \(h) 小时" }
        return "\(h) 小时"
    }
}

// MARK: - Auth & connection

enum AuthType: String, Codable, CaseIterable, Identifiable {
    case user = "账号密码"
    case openApi = "开放API"
    var id: String { rawValue }
}

struct Connection: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var baseURLString: String
    var authType: AuthType
    var username: String
    var password: String
    var clientID: String
    var clientSecret: String

    var apiPrefix: String { authType == .openApi ? "/open" : "/api" }

    var normalizedBaseURL: URL? {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://" + s
        }
        return URL(string: s)
    }
}

// MARK: - API errors

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverMessage(String)
    case invalidResponse
    case httpError(Int)
    case encoding
    /// 两步验证（2FA）所需：普通登录密码正确但面板开启了两步验证，服务端返回 code 420。
    case twoFactorRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的面板地址"
        case .unauthorized: return "认证失败，请检查账号或开放API凭证"
        case .serverMessage(let m): return m.isEmpty ? "服务器返回错误" : m
        case .invalidResponse: return "无法解析服务器返回数据"
        case .httpError(let c): return "HTTP 错误 \(c)"
        case .encoding: return "请求参数编码失败"
        case .twoFactorRequired: return "该账号开启了两步验证，请输入验证码"
        }
    }
}

// MARK: - File node (脚本管理)

/// A node returned by `GET /api/scripts` (v2.20+). `key` is the relative path
/// used for navigation; `type` is "directory" | "file".
struct FileNode: Identifiable, Hashable {
    var id: String { key.isEmpty ? title : key }
    var title: String = ""
    var key: String = ""
    var type: String = "file"
    var parent: String = ""
    var createTime: Int?
    var size: Int?

    var isDirectory: Bool { type == "directory" }

    var sizeText: String? {
        guard let s = size, s > 0 else { return nil }
        let kb = Double(s) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", kb / 1024.0)
    }
}

extension FileNode: Decodable {
    enum CodingKeys: String, CodingKey {
        case title, key, type, parent, size, createTime
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? title
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "file"
        parent = (try? c.decodeIfPresent(String.self, forKey: .parent)) ?? ""
        createTime = try? c.decodeIfPresent(Int.self, forKey: .createTime)
        size = try? c.decodeIfPresent(Int.self, forKey: .size)
    }
}

// MARK: - Dependency (依赖管理)

/// 青龙依赖。type: 0=Node.js / 1=Python3 / 2=Linux。status 见 DependenceStatus。
struct Dependency: Identifiable, Hashable {
    var id: Int { _id }
    var _id: Int = 0
    var name: String = ""
    var type: Int = 0
    var status: Int = 6
    var remark: String = ""

    var typeLabel: String {
        switch type {
        case 0: return "Node.js"
        case 1: return "Python3"
        case 2: return "Linux"
        default: return "类型 \(type)"
        }
    }

    /// 0 installing / 1 installed / 2 installFailed / 3 removing / 4 removed
    /// 5 removeFailed / 6 queued / 7 cancelled
    var statusLabel: String {
        switch status {
        case 0: return "安装中"
        case 1: return "已安装"
        case 2: return "安装失败"
        case 3: return "卸载中"
        case 4: return "已卸载"
        case 5: return "卸载失败"
        case 6: return "排队中"
        case 7: return "已取消"
        default: return "未知"
        }
    }

    var isInstalled: Bool { status == 1 }
    var isBusy: Bool { status == 0 || status == 3 || status == 6 }
}

extension Dependency: Decodable {
    enum CodingKeys: String, CodingKey {
        case _id = "id", name, type, status, remark
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = (try? c.decodeIfPresent(Int.self, forKey: ._id)) ?? 0
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        type = (try? c.decodeIfPresent(Int.self, forKey: .type)) ?? 0
        status = (try? c.decodeIfPresent(Int.self, forKey: .status)) ?? 6
        remark = (try? c.decodeIfPresent(String.self, forKey: .remark)) ?? ""
    }
}

// MARK: - Config file (配置文件)

struct ConfigFile: Identifiable, Hashable {
    var id: String { value }
    var title: String = ""
    var value: String = ""   // file name, e.g. config.sh
}

extension ConfigFile: Decodable {
    enum CodingKeys: String, CodingKey { case title, value }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        value = (try? c.decodeIfPresent(String.self, forKey: .value)) ?? title
    }
}

// MARK: - Subscription (订阅管理)

/// 青龙订阅。status: 0 running / 1 idle / 2 disabled / 3 queued。
struct Subscription: Identifiable, Hashable {
    var id: Int { _id }
    var _id: Int = 0
    var name: String = ""
    var alias: String = ""
    var type: String = ""            // public-repo / private-repo / file
    var scheduleType: String = ""    // crontab / interval
    var schedule: String = ""
    var url: String = ""
    var status: Int = 1
    var isDisabled: Int = 0
    var branch: String = ""
    var whitelist: String = ""
    var blacklist: String = ""
    var dependences: String = ""
    var extensions: String = ""
    var subBefore: String = ""
    var subAfter: String = ""
    var proxy: String = ""
    var autoAddCron: Int = 0
    var autoDelCron: Int = 0
    var logPath: String = ""

    var displayName: String { alias.isEmpty ? name : alias }
    var isEnabled: Bool { isDisabled != 1 }

    var statusLabel: String {
        if isDisabled == 1 { return "已禁用" }
        switch status {
        case 0: return "运行中"
        case 3: return "排队中"
        default: return "空闲"
        }
    }

    var typeLabel: String {
        switch type {
        case "public-repo": return "公开仓库"
        case "private-repo": return "私有仓库"
        case "file": return "文件"
        default: return type.isEmpty ? "仓库" : type
        }
    }
}

extension Subscription: Decodable {
    enum CodingKeys: String, CodingKey {
        case _id = "id", name, alias, type, scheduleType = "schedule_type"
        case schedule, url, status, isDisabled = "is_disabled"
        case branch, whitelist, blacklist, dependences, extensions
        case subBefore = "sub_before", subAfter = "sub_after"
        case proxy, autoAddCron = "autoAddCron", autoDelCron = "autoDelCron"
        case logPath = "log_path"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = (try? c.decodeIfPresent(Int.self, forKey: ._id)) ?? 0
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        alias = (try? c.decodeIfPresent(String.self, forKey: .alias)) ?? ""
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
        scheduleType = (try? c.decodeIfPresent(String.self, forKey: .scheduleType)) ?? ""
        schedule = (try? c.decodeIfPresent(String.self, forKey: .schedule)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        status = (try? c.decodeIfPresent(Int.self, forKey: .status)) ?? 1
        isDisabled = (try? c.decodeIfPresent(Int.self, forKey: .isDisabled)) ?? 0
        branch = (try? c.decodeIfPresent(String.self, forKey: .branch)) ?? ""
        whitelist = (try? c.decodeIfPresent(String.self, forKey: .whitelist)) ?? ""
        blacklist = (try? c.decodeIfPresent(String.self, forKey: .blacklist)) ?? ""
        dependences = (try? c.decodeIfPresent(String.self, forKey: .dependences)) ?? ""
        extensions = (try? c.decodeIfPresent(String.self, forKey: .extensions)) ?? ""
        subBefore = (try? c.decodeIfPresent(String.self, forKey: .subBefore)) ?? ""
        subAfter = (try? c.decodeIfPresent(String.self, forKey: .subAfter)) ?? ""
        proxy = (try? c.decodeIfPresent(String.self, forKey: .proxy)) ?? ""
        autoAddCron = (try? c.decodeIfPresent(Int.self, forKey: .autoAddCron)) ?? 0
        autoDelCron = (try? c.decodeIfPresent(Int.self, forKey: .autoDelCron)) ?? 0
        logPath = (try? c.decodeIfPresent(String.self, forKey: .logPath)) ?? ""
    }
}

// MARK: - Open API App (应用设置)

struct AppItem: Identifiable, Hashable {
    var id: Int { _id }
    var _id: Int = 0
    var name: String = ""
    var scopes: [String] = []
    var clientID: String = ""
    var clientSecret: String = ""

    var scopesText: String { scopes.isEmpty ? "（无）" : scopes.joined(separator: ", ") }
}

extension AppItem: Decodable {
    enum CodingKeys: String, CodingKey {
        case _id = "id", name, scopes
        case clientID = "client_id", clientSecret = "client_secret"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = (try? c.decodeIfPresent(Int.self, forKey: ._id)) ?? 0
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        scopes = (try? c.decodeIfPresent([String].self, forKey: .scopes)) ?? []
        clientID = (try? c.decodeIfPresent(String.self, forKey: .clientID)) ?? ""
        clientSecret = (try? c.decodeIfPresent(String.self, forKey: .clientSecret)) ?? ""
    }
}

// MARK: - System config (系统设置)

/// `GET /api/system/config` 返回 { ..., info: {...} }。info 内为各项配置。
struct SystemConfig: Codable {
    var id: Int?
    var info: SystemConfigInfo?
}

struct SystemConfigInfo: Codable {
    var timezone: String?
    var logRemoveFrequency: Int?
    var cronConcurrency: Int?
    var dependenceProxy: String?
    var nodeMirror: String?
    var pythonMirror: String?
    var linuxMirror: String?
    var panelTitle: String?
    var globalSshKey: String?
}

// MARK: - Panel info (关于 / GET /api/system)

struct PanelInfo: Codable {
    var version: String?
    var branch: String?
    var publishTime: Int?
    var changeLog: String?
    var changeLogLink: String?
    var isInitialized: Bool?

    var publishDateText: String? {
        guard let t = publishTime, t > 0 else { return nil }
        let d = Date(timeIntervalSince1970: TimeInterval(t))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 当前登录用户 (GET /api/user)

struct UserInfo: Decodable, Hashable {
    var username: String = ""
    var avatar: String = ""
    var twoFactorActivated: Bool = false

    enum CodingKeys: String, CodingKey { case username, avatar, twoFactorActivated }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar)) ?? ""
        twoFactorActivated = (try? c.decodeIfPresent(Bool.self, forKey: .twoFactorActivated)) ?? false
    }
}

// MARK: - 登录日志 (GET /api/user/login-log)

/// 青龙登录日志。status: 0=success / 1=fail。
struct LoginLogEntry: Identifiable, Decodable, Hashable {
    var id: String { "\(timestamp ?? 0)-\(ip ?? "")" }
    var timestamp: Int?
    var address: String?
    var ip: String?
    var platform: String?
    var status: Int?

    enum CodingKeys: String, CodingKey { case timestamp, address, ip, platform, status }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try? c.decodeIfPresent(Int.self, forKey: .timestamp)
        address = try? c.decodeIfPresent(String.self, forKey: .address)
        ip = try? c.decodeIfPresent(String.self, forKey: .ip)
        platform = try? c.decodeIfPresent(String.self, forKey: .platform)
        status = try? c.decodeIfPresent(Int.self, forKey: .status)
    }

    var isSuccess: Bool { (status ?? 0) == 0 }
    var timeText: String {
        guard let t = timestamp, t > 0 else { return "—" }
        let d = Date(timeIntervalSince1970: TimeInterval(t) / 1000.0)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }
}

// MARK: - 通知配置 (GET/PUT /api/user/notification)

/// 通知渠道枚举，与青龙 NotificationMode 一致。
enum NotifyChannel: String, CaseIterable, Identifiable {    case gotify = "gotify"
    case goCqHttpBot = "goCqHttpBot"
    case serverChan = "serverChan"
    case pushDeer = "pushDeer"
    case bark = "bark"
    case chat = "chat"
    case telegramBot = "telegramBot"
    case dingtalkBot = "dingtalkBot"
    case weWorkBot = "weWorkBot"
    case weWorkApp = "weWorkApp"
    case aibotk = "aibotk"
    case iGot = "iGot"
    case pushPlus = "pushPlus"
    case wePlusBot = "wePlusBot"
    case email = "email"
    case pushMe = "pushMe"
    case feishu = "feishu"
    case webhook = "webhook"
    case chronocat = "Chronocat"
    case ntfy = "ntfy"
    case wxPusherBot = "wxPusherBot"
    case openiLink = "openiLink"
    case wpush = "wpush"

    var id: String { rawValue }

    /// 渠道参数项（key 为面板字段名，hint 为填写提示）。
    struct Field: Identifiable, Hashable {
        let key: String
        let hint: String
        var id: String { key }
    }

    var label: String {
        switch self {
        case .gotify: return "Gotify"
        case .goCqHttpBot: return "GoCqHttpGet Bot"
        case .serverChan: return "Server 酱"
        case .pushDeer: return "PushDeer"
        case .bark: return "Bark"
        case .chat: return "Synology Chat"
        case .telegramBot: return "Telegram 机器人"
        case .dingtalkBot: return "钉钉机器人"
        case .weWorkBot: return "企业微信机器人"
        case .weWorkApp: return "企业微信应用"
        case .aibotk: return "智能微秘书"
        case .iGot: return "iGot"
        case .pushPlus: return "PushPlus"
        case .wePlusBot: return "WePlus 机器人"
        case .email: return "电子邮件"
        case .pushMe: return "PushMe"
        case .feishu: return "飞书机器人"
        case .webhook: return "自定义 Webhook"
        case .chronocat: return "Chronocat"
        case .ntfy: return "ntfy"
        case .wxPusherBot: return "WxPusher 机器人"
        case .openiLink: return "OpeniLink"
        case .wpush: return "Wpush"
        }
    }

    /// 每个渠道需要填写的字段 (key -> 占位提示)。
    var fields: [Field] {
        switch self {
        case .gotify:
            return [Field(key: "gotifyUrl", hint: "Gotify 地址，如 https://gotify.example.com"),
                    Field(key: "gotifyToken", hint: "应用 Token"), Field(key: "gotifyPriority", hint: "优先级，默认 0")]
        case .goCqHttpBot:
            return [Field(key: "goCqHttpBotUrl", hint: "GoCqHttp 地址"),
                    Field(key: "goCqHttpBotToken", hint: "access_token"), Field(key: "goCqHttpBotQq", hint: "接收消息的 QQ 号")]
        case .serverChan:
            return [Field(key: "serverChanKey", hint: "SendKey")]
        case .pushDeer:
            return [Field(key: "pushDeerKey", hint: "PushKey"), Field(key: "pushDeerUrl", hint: "自建地址，可空")]
        case .bark:
            return [Field(key: "barkPush", hint: "设备 key 或完整 URL"), Field(key: "barkSound", hint: "铃声，可空"),
                    Field(key: "barkGroup", hint: "分组，默认 qinglong"), Field(key: "barkUrl", hint: "跳转 URL，可空")]
        case .chat:
            return [Field(key: "synologyChatUrl", hint: "Synology Chat 机器人 Webhook 地址")]
        case .telegramBot:
            return [Field(key: "telegramBotToken", hint: "Bot Token"), Field(key: "telegramBotUserId", hint: "用户/群 ID"),
                    Field(key: "telegramBotApiHost", hint: "API 地址，默认 https://api.telegram.org")]
        case .dingtalkBot:
            return [Field(key: "dingtalkBotToken", hint: "机器人 access_token"), Field(key: "dingtalkBotSecret", hint: "加签密钥，可空")]
        case .weWorkBot:
            return [Field(key: "weWorkBotKey", hint: "机器人 Webhook key")]
        case .weWorkApp:
            return [Field(key: "weWorkAppKey", hint: "应用 key")]
        case .aibotk:
            return [Field(key: "aibotkKey", hint: "智能微秘书 key"), Field(key: "aibotkName", hint: "接收人，可空")]
        case .iGot:
            return [Field(key: "iGotPushKey", hint: "iGot pushKey")]
        case .pushPlus:
            return [Field(key: "pushPlusToken", hint: "Token"), Field(key: "pushPlusUser", hint: "群组编码，可空")]
        case .wePlusBot:
            return [Field(key: "wePlusBotToken", hint: "Token"), Field(key: "wePlusBotReceiver", hint: "接收人 UID")]
        case .email:
            return [Field(key: "emailService", hint: "SMTP 服务，如 smtp.qq.com"),
                    Field(key: "emailUser", hint: "登录账号"), Field(key: "emailPass", hint: "密码/授权码"), Field(key: "emailTo", hint: "收件人，可空")]
        case .pushMe:
            return [Field(key: "pushMeKey", hint: "PushKey"), Field(key: "pushMeUrl", hint: "自建地址，可空")]
        case .feishu:
            return [Field(key: "larkKey", hint: "飞书机器人 Webhook 中的 key"), Field(key: "larkSecret", hint: "加签密钥，可空")]
        case .webhook:
            return [Field(key: "webhookUrl", hint: "完整 Webhook 地址"), Field(key: "webhookMethod", hint: "GET/POST/PUT"),
                    Field(key: "webhookContentType", hint: "application/json 等"), Field(key: "webhookHeaders", hint: "请求头 JSON，可空"),
                    Field(key: "webhookBody", hint: "请求体模板，可空")]
        case .chronocat:
            return [Field(key: "chronocatURL", hint: "Chronocat 地址"), Field(key: "chronocatQQ", hint: "接收 QQ 号"), Field(key: "chronocatToken", hint: "Token")]
        case .ntfy:
            return [Field(key: "ntfyUrl", hint: "ntfy 地址，如 https://ntfy.sh"), Field(key: "ntfyTopic", hint: "Topic"),
                    Field(key: "ntfyToken", hint: "Token，可空"), Field(key: "ntfyPriority", hint: "优先级，可空")]
        case .wxPusherBot:
            return [Field(key: "wxPusherBotAppToken", hint: "应用 Token"), Field(key: "wxPusherBotTopicIds", hint: "主题 ID，可空"),
                    Field(key: "wxPusherBotUids", hint: "用户 UID，可空")]
        case .openiLink:
            return [Field(key: "openiLinkAppToken", hint: "应用 Token"), Field(key: "openiLinkHubUrl", hint: "Hub 地址，可空")]
        case .wpush:
            return [Field(key: "wpushApiKey", hint: "API Key"), Field(key: "wpushChannel", hint: "渠道，可空"), Field(key: "wpushTopicCode", hint: "主题代码，可空")]
        }
    }
}

/// 通知配置：所有字段容错解码（不同面板版本字段有增减）。
struct NotificationConfig: Decodable {
    var type: String = ""
    var raw: [String: String] = [:]

    private static let stringKeys: Set<String> = [
        "gotifyUrl","gotifyToken","goCqHttpBotUrl","goCqHttpBotToken","goCqHttpBotQq",
        "serverChanKey","pushDeerKey","pushDeerUrl","synologyChatUrl","barkPush","barkSound",
        "barkGroup","barkUrl","telegramBotToken","telegramBotUserId","telegramBotApiHost",
        "dingtalkBotToken","dingtalkBotSecret","weWorkBotKey","weWorkAppKey","aibotkKey",
        "aibotkName","iGotPushKey","pushPlusToken","pushPlusUser","pushplusTo","wePlusBotToken",
        "wePlusBotReceiver","emailService","emailUser","emailPass","emailTo","pushMeKey",
        "pushMeUrl","larkKey","larkSecret","webhookUrl","webhookMethod","webhookContentType",
        "webhookHeaders","webhookBody","chronocatURL","chronocatQQ","chronocatToken","ntfyUrl",
        "ntfyTopic","ntfyToken","ntfyPriority","ntfyUsername","ntfyPassword","wxPusherBotAppToken",
        "wxPusherBotTopicIds","wxPusherBotUids","wxPusherSptList","openiLinkAppToken",
        "openiLinkHubUrl","openiLinkContextToken","wpushApiKey","wpushChannel","wpushTopicCode",
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        var out: [String: String] = [:]
        if let t = try? c.decodeIfPresent(String.self, forKey: DynamicKey("type")) { type = t }
        for key in Self.stringKeys {
            if let v = try? c.decodeIfPresent(String.self, forKey: DynamicKey(key)) { out[key] = v }
        }
        // 数字型字段也按字符串收，便于统一回显
        if let p = try? c.decodeIfPresent(Int.self, forKey: DynamicKey("gotifyPriority")) { out["gotifyPriority"] = String(p) }
        raw = out
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    func value(_ key: String) -> String { raw[key] ?? "" }
    var channel: NotifyChannel? { NotifyChannel(rawValue: type) }

    /// 组装 PUT /api/user/notification 请求体（附带 type）。
    func payload(channel: NotifyChannel) -> [String: String] {
        var dict = raw
        dict["type"] = channel.rawValue
        return dict
    }
}

// MARK: - 依赖扫描结果 (扫描依赖)

/// 从脚本中识别出的依赖引用。
struct DepScanItem: Identifiable, Hashable {
    var id: String { "\(name)|\(type)" }
    var name: String
    var type: Int            // 0 Node.js / 1 Python3 / 2 Linux
    /// 引用该依赖的脚本相对路径。
    var sources: [String]
    /// 面板中已安装的同名依赖数量（>0 视为已安装）。
    var installed: Bool

    var typeLabel: String {
        switch type {
        case 0: return "Node.js"
        case 1: return "Python3"
        default: return "Linux"
        }
    }
}

// MARK: - 脚本历史版本 (v2.20+ 新增)

/// 脚本历史版本条目（GET /api/scripts/history）。id 为 UUID 字符串。
struct ScriptHistoryItem: Identifiable, Decodable, Hashable {
    var id: String { historyId ?? UUID().uuidString }
    let historyId: String?
    let filename: String?
    let size: Double?
    let createTime: Double?
    let remark: String?

    enum CodingKeys: String, CodingKey {
        case historyId = "id"
        case filename
        case size
        case createTime
        case remark
    }

    var createTimeText: String {
        guard let t = createTime else { return "—" }
        let d = Date(timeIntervalSince1970: t / 1000)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    var sizeText: String {
        guard let s = size else { return "—" }
        if s < 1024 { return "\(Int(s)) B" }
        if s < 1024 * 1024 { return String(format: "%.1f KB", s / 1024) }
        return String(format: "%.1f MB", s / 1024 / 1024)
    }
}

// MARK: - 版本检查 (PUT /api/system/update-check)

/// 服务端新版本信息（PUT /api/system/update-check）。
struct ServerUpdateInfo: Decodable, Hashable {
    let hasNewVersion: Bool
    let lastVersion: String?
    let latestVersion: String?
    let currentVersion: String?
    let logUrl: String?

    enum CodingKeys: String, CodingKey {
        case hasNewVersion
        case lastVersion
        case latestVersion
        case currentVersion
        case logUrl
    }

    init(hasNewVersion: Bool = false, lastVersion: String? = nil) {
        self.hasNewVersion = hasNewVersion
        self.lastVersion = lastVersion
        self.latestVersion = nil
        self.currentVersion = nil
        self.logUrl = nil
    }
}
