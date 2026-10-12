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

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的面板地址"
        case .unauthorized: return "认证失败，请检查账号或开放API凭证"
        case .serverMessage(let m): return m.isEmpty ? "服务器返回错误" : m
        case .invalidResponse: return "无法解析服务器返回数据"
        case .httpError(let c): return "HTTP 错误 \(c)"
        case .encoding: return "请求参数编码失败"
        }
    }
}
