import Foundation

/// 青龙 v2.23+ 仪表盘接口模型。
///
/// 重要背景（v2.0.7 修复「仪表盘没有数据」的根因）：
/// 面板 `GET /system` 只返回版本信息（isInitialized/version/publishTime/branch/changeLog），
/// **不包含** CPU/内存/磁盘等系统资源；系统资源在 `GET /dashboard/system`。
/// 旧代码把 `/system` 的响应往 SystemInfo 里塞，usage 字段全部为 nil → 仪表盘显示「—」。

/// GET /dashboard/system —— 系统资源（v2.23+ 提供；旧版面板 404 时保持 nil）。
struct DashboardSystemInfo: Codable {
    var platform: String?
    var uptime: Double?
    var memTotal: Double?
    var memFree: Double?
    /// 内存使用率字符串，如 "45.6"（面板以字符串返回）。
    var memUsagePercent: String?
    /// Node 堆内存已用（MB）。
    var heapUsed: Double?
    /// Node 堆内存总量（MB）。
    var heapTotal: Double?
    /// 1m/5m/15m 负载。
    var loadAvg: [Double]?
    /// CPU 核心数。
    var cpus: Int?

    // MARK: 展示用计算属性

    var memoryPercentText: String {
        guard let s = memUsagePercent?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return "—" }
        return s.hasSuffix("%") ? s : s + "%"
    }

    var uptimeText: String {
        guard let u = uptime, u > 0 else { return "—" }
        let total = Int(u)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
        return "\(max(minutes, 1)) 分钟"
    }

    var heapText: String {
        guard let used = heapUsed else { return "—" }
        if let total = heapTotal { return "\(Int(used)) / \(Int(total)) MB" }
        return "\(Int(used)) MB"
    }

    var loadText: String {
        guard let first = loadAvg?.first else { return "—" }
        return String(format: "%.2f", first)
    }

    var cpuText: String {
        guard let c = cpus else { return "—" }
        return "\(c) 核心"
    }

    var memoryBytesText: String {
        guard let total = memTotal else { return "—" }
        let free = memFree ?? 0
        return "\(Self.formatBytes(total - free)) / \(Self.formatBytes(total))"
    }

    static func formatBytes(_ bytes: Double) -> String {
        if bytes <= 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = bytes
        var i = 0
        while value >= 1024, i < units.count - 1 {
            value /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(value)) \(units[i])" }
        return String(format: "%.1f %@", value, units[i] as CVarArg)
    }
}

/// GET /dashboard/overview —— 今日执行统计。
struct DashboardOverview: Codable {
    var total: Int?
    var enabled: Int?
    var disabled: Int?
    var todayRuns: Int?
    var todaySuccess: Int?
    var todayFail: Int?
    /// 成功率字符串，如 "95.2"。
    var successRate: String?
    /// 平均耗时（毫秒）。
    var avgTime: Int?

    var todayRunsText: String { "\(todayRuns ?? 0)" }
    var successRateText: String {
        guard let s = successRate, !s.isEmpty else { return "0%" }
        return s.hasSuffix("%") ? s : s + "%"
    }
    var avgTimeText: String {
        guard let ms = avgTime, ms > 0 else { return "—" }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.1f s", Double(ms) / 1000.0)
    }
    var disabledText: String { "\(disabled ?? 0)" }
}

/// GET /dashboard/runtime —— 运行中/排队中的任务。
struct DashboardRuntime: Codable {
    var runningCount: Int?
    var queuedCount: Int?
    var running: [DashboardRunningTask]?
    var idleTasks: [DashboardIdleTask]?
}

struct DashboardRunningTask: Codable, Identifiable {
    var instanceId: Int?
    /// 任务 id（面板为数字 id）。
    var id: Int?
    var name: String?
    var pid: Int?
    /// 已运行秒数。
    var elapsed: Int?
    var logPath: String?

    var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "任务#\(id ?? 0)" : n
    }

    var elapsedText: String {
        guard let e = elapsed, e > 0 else { return "" }
        if e < 60 { return "\(e) 秒" }
        if e < 3600 { return "\(e / 60) 分 \(e % 60) 秒" }
        return "\(e / 3600) 时 \((e % 3600) / 60) 分"
    }
}

struct DashboardIdleTask: Codable, Identifiable {
    var id: Int?
    var name: String?
    /// 面板已格式化为 "MM-DD HH:mm"。
    var lastRun: String?

    var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "任务#\(id ?? 0)" : n
    }
}
