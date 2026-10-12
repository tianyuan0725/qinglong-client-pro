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

// MARK: - Cron task

struct CronTask: Identifiable, Hashable {
    var id: String { _id ?? "" }
    let _id: String?
    var name: String
    var command: String
    var schedule: String
    var labels: [String]
    var enabled: FlexBool?
    var status: FlexInt?
    var pid: FlexInt?
    var isSystem: FlexInt?
    var lastRunningTime: String?
    var lastExecutionTime: String?
    var runningStatus: FlexInt?
    var logPath: String?
    var createdAt: String?

    var isEnabled: Bool { enabled?.value ?? true }
    var isRunning: Bool { (runningStatus?.value ?? 0) > 0 || (pid?.value ?? 0) > 0 }
    var statusLabel: String {
        if isRunning { return "运行中" }
        if let s = status?.value, s > 0 { return "已结束" }
        return isEnabled ? "已启用" : "已禁用"
    }
}

extension CronTask: Codable {
    enum CodingKeys: String, CodingKey {
        case _id, name, command, schedule, labels, status, pid, isSystem
        case enabled
        case lastRunningTime = "last_running_time"
        case lastExecutionTime = "last_execution_time"
        case runningStatus = "running_status"
        case logPath = "log_path"
        case createdAt = "created_at"
    }
}

// MARK: - Environment variable

struct EnvVar: Identifiable, Hashable {
    var id: String { _id ?? idField ?? UUID().uuidString }
    let _id: String?
    let idField: String?
    var name: String
    var value: String
    var remarks: String?
    var status: FlexInt?   // 0 = enabled, 1 = disabled
    var position: FlexInt?

    var isEnabled: Bool { status?.value ?? 0 == 0 }
}

extension EnvVar: Codable {
    enum CodingKeys: String, CodingKey {
        case _id, name, value, remarks, status, position
        case idField = "id"
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
