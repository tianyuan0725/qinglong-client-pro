import Foundation
import SwiftUI
import BackgroundTasks

/// 全局任务运行状态监听服务。
///
/// 与旧版「按任务 watchCron」的本质区别：旧实现只监听 App 内点过「运行」的
/// 任务，用户在青龙网页里手动触发的任务、面板 cron 到点自动跑的任务都收不到
/// 提醒（v2.3.0 用户反馈「浏览器运行的 APP 没有通知」）。现在改为全局轮询
/// 全部任务的运行状态，**任何来源**启动的任务都发本地通知；任务结束时通知
/// 带「执行成功 + 耗时 + 完成时间」（对齐青龙面板推送到微信的通知格式）。
///
/// 后台实时性：配合 BackgroundKeeper（静音保活）退后台不被系统挂起，轮询
/// 继续跑，完成时即刻弹通知；App 被系统杀掉后由 BGAppRefreshTask 兜底补轮询，
/// 离线期间完成的任务在下次启动时补发完成通知。
@MainActor
final class CronWatchService: ObservableObject {
    static let shared = CronWatchService()

    /// 是否正在轮询（设置页可展示「后台实时通知」状态）。
    @Published private(set) var isWatching = false

    // MARK: - 私有状态

    private weak var session: PanelSession?
    private var timer: Timer?

    /// 轮询间隔（秒）：用户可在通知栏顶部自定义（3–60 秒，默认 5）。
    /// 间隔越大越省电，完成检测延迟也越大。
    private var interval: TimeInterval {
        let v = UserDefaults.standard.integer(forKey: intervalKey)
        return v >= 3 ? TimeInterval(v) : 5
    }

    /// 轮询间隔持久化 key（与通知栏顶部设置联动）。
    private let intervalKey = "qlpro_poll_interval"

    /// 上一轮各任务运行状态（id -> isRunning，仅内存，用于运行状态转换检测）。
    private var lastStates: [String: Bool] = [:]
    /// 各任务已发过完成通知的执行时间戳（id -> last_execution_time）。
    /// 持久化：用于跨启动补发 + 防止重复通知。
    private var lastNotifiedExec: [String: Int] = [:]
    /// 快照保存时间（用于判断离线补通知是否已过期）。
    private var snapshotSavedAt: Date?
    /// 本轮 App 生命周期内是否已建立基线（首轮只记录不通知，避免历史状态刷屏）。
    private var baselined = false

    /// App 内手动点过「运行」的任务（开始通知已由 UI 立即发过，
    /// 轮询发现其启动时不再重复发；任务结束后移除）。
    private var manualStartNotified = Set<String>()

    /// 后台刷新任务标识（需同时在 Info.plist BGTaskSchedulerPermittedIdentifiers 登记）。
    private let bgTaskIdentifier = "com.qlpro.cronrefresh"
    /// 快照持久化 key。
    /// 快照持久化 key（按连接 id 隔离：不同面板/账号互不干扰，
    /// 避免新登录账号被旧账号的快照误判为「离线期间新完成」而补发刷屏）。
    private var snapshotKey = "qlpro_cron_watch_snapshot"
    private init() {}

    // MARK: - 启停

    /// 开始全局监听（面板会话建立后调用，重复调用安全）。
    func start(session: PanelSession) {
        self.session = session
        snapshotKey = "qlpro_cron_watch_snapshot_\(session.connection.id)"
        loadSnapshot()
        guard timer == nil else { return }
        isWatching = true
        baselined = false
        // 本地通知开着、且用户没关保活开关，才退后台保活（省电优先）
        if AppNotifyManager.shared.enabled && BackgroundKeeper.isEnabled {
            BackgroundKeeper.shared.start()
        }
        scheduleBackgroundRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { await poll() } // 立即来一轮，不等第一个 5 秒间隔
    }

    /// 停止监听（退出面板时调用）。
    func stop() {
        timer?.invalidate()
        timer = nil
        isWatching = false
        baselined = false
        manualStartNotified = []
        saveSnapshot()
        BackgroundKeeper.shared.stop()
    }

    /// App 内手动点「运行」后调用：开始通知已由 UI 立即发过，
    /// 轮询发现该任务启动时跳过，任务结束时照常发完成通知。
    func noteManualStart(cronId: String) {
        manualStartNotified.insert(cronId)
    }

    /// 用户在通知栏修改轮询间隔后调用：立即按新间隔重启定时器。
    /// 未在监听时仅记录，下次 start() 自然读取新值。
    func updateInterval(_ newInterval: TimeInterval) {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { await poll() } // 立即按新间隔来一轮
    }

    // MARK: - 轮询

    private func poll() async {
        guard let session, session.isAuthenticated else { return }
        // 推送通知总开关关闭：完全不接受通知——停保活并跳过本轮（省电）。
        // 重新开启后下轮自动恢复。
        guard AppNotifyManager.shared.enabled else {
            BackgroundKeeper.shared.stop()
            return
        }
        // 通知开着、保活开关变化时自动同步（开着才值得后台耗电）
        if BackgroundKeeper.isEnabled {
            BackgroundKeeper.shared.start()
        } else {
            BackgroundKeeper.shared.stop()
        }
        await pollOnce(session: session)
    }

    /// 单次轮询 + 状态比对（前台定时器与后台刷新任务共用）。
    ///
    /// 两类完成检测，互补不漏：
    /// ① 运行状态转换（跑着 → 闲了）：覆盖耗时 > 轮询间隔的任务；
    /// ② last_execution_time 变化且当前未在跑：覆盖两轮轮询之间就跑完的
    ///    快速任务（从未见到 running 状态，纯状态转换会漏）。
    func pollOnce(session: PanelSession) async {
        await session.loadCrons()
        // 加载失败（网络错误）时 crons 保持旧值；列表为空视为未加载成功，
        // 不建基线、不通知，下轮重试（面板确实 0 任务时也无通知可发）。
        guard !session.crons.isEmpty else { return }
        let byId = Dictionary(uniqueKeysWithValues: session.crons.map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: session.crons.map { ($0.id, $0.isRunning) })

        if !baselined {
            establishBaseline(byId: byId, current: current)
            return
        }

        var changed = false
        for (id, cron) in byId {
            let nowRunning = cron.isRunning
            let wasRunning = lastStates[id] ?? false
            let execTime = cron.lastExecutionTime?.value ?? 0
            let alreadyNotified = execTime > 0 && lastNotifiedExec[id] == execTime

            if nowRunning != wasRunning {
                // ① 运行状态转换：任何来源启动（App 手动 / 浏览器 / 面板定时）
                changed = true
                if nowRunning {
                    if !manualStartNotified.contains(id) {
                        AppNotifyManager.shared.notifyCronStarted(name: cron.name)
                    }
                } else if !alreadyNotified {
                    manualStartNotified.remove(id)
                    lastNotifiedExec[id] = execTime
                    let detail = await finishDetail(session: session, cron: cron)
                    AppNotifyManager.shared.notifyCronFinished(name: cron.name, detail: detail)
                } else {
                    manualStartNotified.remove(id)
                }
            } else if !nowRunning && !alreadyNotified && execTime > 0 {
                // ② 快速任务：两轮轮询之间跑完，从未见到 running
                changed = true
                manualStartNotified.remove(id)
                lastNotifiedExec[id] = execTime
                let detail = await finishDetail(session: session, cron: cron)
                AppNotifyManager.shared.notifyCronFinished(name: cron.name, detail: detail)
            }
        }
        if changed || lastStates.count != current.count {
            lastStates = current
            saveSnapshot()
        }
    }

    /// 建立基线：首轮成功加载后只记录状态，不发任何通知。
    /// v2.3.4：取消「离线期间完成任务补发」——用户明确「只接受最新的运行
    /// 成功通知，已完成的就不要推送了」。首轮（含新登录账号、快照丢失）
    /// 一律只建基线，历史已完成任务不再打扰。
    private func establishBaseline(byId: [String: CronTask], current: [String: Bool]) {
        // 基线：记录当前执行时间戳，之后只通知「新发生的执行」
        for (id, cron) in byId {
            lastNotifiedExec[id] = cron.lastExecutionTime?.value ?? 0
        }
        lastStates = current
        baselined = true
        saveSnapshot()
    }

    /// 组装任务完成通知内容，格式对齐青龙面板推送到微信的通知：
    /// 成功 → 「✅ 执行成功 / ⏱️ 执行耗时: N 秒 / 🕐 完成时间: ...」
    /// 失败 → 「❌ 错误标题 / 💬 错误信息: ... / ⏱️ 执行耗时 / 🕐 完成时间」
    /// 状态与错误信息从 cron 日志实时解析（## 失败/❌ 标记、ERROR 行）。
    private func finishDetail(session: PanelSession, cron: CronTask) async -> String {
        let log = (try? await session.cronLog(id: cron.id)) ?? ""
        let parsed = Self.parseCronLog(log)
        var lines: [String] = []
        if parsed.stopped && !parsed.failed {
            lines.append("🛑 已停止")
        } else if parsed.failed {
            lines.append("❌ \(parsed.errorTitle.isEmpty ? "任务执行异常" : parsed.errorTitle)")
            if !parsed.errorDetail.isEmpty {
                lines.append("💬 错误信息: \(parsed.errorDetail)")
            }
        } else {
            lines.append("✅ 执行成功")
        }
        // 耗时：优先日志结论行的「耗时 N 秒」（与面板一致），其次 last_running_time
        let secs = parsed.durationSecs ?? cron.lastRunningTime?.value ?? 0
        if secs > 0 {
            lines.append(secs >= 60
                ? String(format: "⏱️ 执行耗时: %.1f 分钟", Double(secs) / 60)
                : String(format: "⏱️ 执行耗时: %d 秒", secs))
        }
        // 完成时间：优先日志结论行时刻；last_execution_time 记的是开始时刻，
        // 兜底用「开始 + 耗时」。注意不同青龙版本时间戳可能是秒或毫秒。
        if let finished = parsed.finishedAt {
            lines.append("🕐 完成时间: \(finished)")
        } else if let raw = cron.lastExecutionTime?.value, raw > 0 {
            let startSec = raw > 100_000_000_000 ? raw / 1000 : raw
            let finished = Date(timeIntervalSince1970: Double(startSec) + Double(secs))
            lines.append("🕐 完成时间: \(Self.dateText(finished))")
        }
        // 附上最近一次执行的脚本输出正文——青龙推送到企业微信的完整内容
        // 就是脚本 sendNotify(text, desp) 的文本，脚本通常先 echo/print 再
        // 发送，日志里能原样找回；只带结论行会丢失业务信息（如签到结果）。
        let body = Self.extractLogBody(log)
        if !body.isEmpty {
            lines.append("")
            lines.append(contentsOf: body)
        }
        return lines.joined(separator: "\n")
    }

    /// 青龙 cron 日志解析结果。
    private struct LogParseResult {
        var failed = false
        /// 手动停止（## 已停止 🛑）：不算失败，通知里单独标示。
        var stopped = false
        var errorTitle = ""
        var errorDetail = ""
        /// 结论行里的耗时（秒），如 `耗时 8 秒`。
        var durationSecs: Int?
        /// 结论行里的完成时刻（原样文本，如 2026-10-13 22:19:02）。
        var finishedAt: String?
    }

    /// 解析青龙 cron 日志：
    /// - 失败判定：末尾结论行 `## 失败 ❌(退出码 N)` 或含 ❌；
    /// - 错误标题/详情：最后一条 ` - ERROR - ` 行，按「标题: 详情」拆分
    ///   （例：`任务执行异常: [Errno 2] No such file...` → 标题=任务执行异常，详情=[Errno 2]...）；
    /// - 耗时/完成时间：结论行 `## 失败 ❌(退出码 1)... 2026-10-13 22:05:23  耗时 8 秒`；
    ///   无 ERROR 行时兜底找 Traceback 末行（FileNotFoundError/Exception 等）。
    private static func parseCronLog(_ log: String) -> LogParseResult {
        let lines = log
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        var result = LogParseResult()
        // 结论行（从后往前）：## 失败 ❌(退出码 1)... 2026-10-13 22:05:23  耗时 8 秒
        var conclusion: String?
        for line in lines.reversed() {
            // 兼容各版本青龙结论行：新版「## 完成 ✅」/「## 已停止 🛑」，
            // 旧版「## 执行成功」/「## 成功」/「## 失败 ❌(退出码 N)」。
            if line.contains("## 完成") || line.contains("## 失败")
                || line.contains("## 已停止") || line.contains("## 执行成功")
                || line.contains("## 成功") {
                conclusion = line
                break
            }
        }
        // 状态：结论行优先；没有结论行再按 ❌ 兜底
        if let conclusion {
            result.failed = conclusion.contains("## 失败") || conclusion.contains("❌")
            result.stopped = conclusion.contains("## 已停止") || conclusion.contains("🛑")
            if let m = conclusion.firstMatch(of: Self.timeRegex) {
                result.finishedAt = String(m.0)
            }
            if let m = conclusion.firstMatch(of: Self.durationRegex) {
                let n = Int(m.1) ?? 0
                result.durationSecs = (m.2 == "分钟") ? n * 60 : n
            }
        } else {
            for line in lines.reversed() {
                if line.contains("❌") { result.failed = true; break }
                if line.contains("✅") { break }
            }
        }
        // 错误信息：最后一条 ERROR 行
        for line in lines.reversed() {
            guard let range = line.range(of: " - ERROR - ") else { continue }
            let msg = String(line[range.upperBound...])
            if let colon = msg.range(of: ": ") {
                result.errorTitle = String(msg[..<colon.lowerBound])
                result.errorDetail = String(msg[colon.upperBound...])
            } else {
                result.errorTitle = msg
            }
            break
        }
        // 兜底：失败了但没有 ERROR 行，取最后的异常行
        if result.failed && result.errorDetail.isEmpty {
            for line in lines.reversed() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.contains("Error:") || t.contains("Exception") || t.contains("错误") {
                    result.errorTitle = "任务执行异常"
                    result.errorDetail = t
                    break
                }
            }
        }
        return result
    }

    /// 结论行里的完成时刻：2026-10-13 22:05:23。
    private static let timeRegex = /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/
    /// 结论行里的耗时：耗时 8 秒 / 耗时 1 分钟（group1=数值，group2=单位）。
    private static let durationRegex = /耗时\s*(\d+)\s*(秒|分钟)/

    /// 青龙 preload 包装的日志行前缀：`2026-10-14 08:23:01 - INFO - `。
    /// group1=毫秒（可无），group2=日志级别。整匹配 m.0 即要剥离的前缀。
    private static let logLevelRegex = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}([.,]\d{1,3})?\s+-\s+(INFO|WARNING|ERROR|DEBUG|CRITICAL)\s+-\s+/

    /// 日志行首的时间戳前缀：`2026-10-14 08:23:01 ` / `2026-10-14 08:23:01,123 `。
    private static let logTimePrefixRegex = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}([.,]\d{1,3})?\s+/

    /// 提取最近一次执行的脚本输出正文，对齐企业微信机器人收到的内容。
    /// 青龙日志按次追加（tee -a），先截取最后一次执行：
    /// `## 开始执行...` 之后、结论行（## 完成/失败/已停止）之前的片段；
    /// 再逐行剥离时间戳 / ` - LEVEL - ` 前缀，滤掉 ERROR 等日志噪音行。
    /// 只保留最后 15 行——sendNotify 的文本在脚本末尾输出。
    private static func extractLogBody(_ log: String) -> [String] {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return [] }
        // 结论行位置（从后往前第一条）
        var end = lines.count
        for i in lines.indices.reversed() {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.contains("## 完成") || t.contains("## 失败") || t.contains("## 已停止")
                || t.contains("## 执行成功") || t.contains("## 成功") {
                end = i
                break
            }
        }
        // 最后一次执行的起点：最后一个「## 开始执行」分隔线
        var start = -1
        for i in (0..<end).reversed() {
            if lines[i].contains("## 开始执行") { start = i + 1; break }
        }
        // 没找到起点（旧版青龙无分隔线）时最多回看 40 行，避免带入历史执行
        if start < 0 { start = max(0, end - 40) }
        var body: [String] = []
        for i in start..<end {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("## ") { continue }               // 内核标记行
            if t.hasPrefix("执行前置命令") || t.hasPrefix("执行后置命令") { continue }
            var text = t
            // 剥离「时间 - LEVEL - 」前缀（青龙 preload 包装的 logging 行）
            if let m = text.firstMatch(of: Self.logLevelRegex) {
                let level = String(m.2)
                if level == "ERROR" || level == "WARNING" || level == "CRITICAL" { continue }
                let prefix = String(m.0)
                if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
            } else if let m = text.firstMatch(of: Self.logTimePrefixRegex) {
                let prefix = String(m.0)
                if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
            }
            text = text.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                // 单行截断，防止通知体过长
                body.append(text.count > 200 ? String(text.prefix(200)) + "…" : text)
            }
        }
        return Array(body.suffix(15))
    }

    /// Date → "yyyy-MM-dd HH:mm:ss"。
    private static func dateText(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: date)
    }

    // MARK: - 快照持久化

    private struct Snapshot: Codable {
        /// 各任务已通知过的执行时间戳（id -> last_execution_time）。
        var execTimes: [String: Int]
        var savedAt: Date
    }

    private func loadSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        lastNotifiedExec = snap.execTimes
        snapshotSavedAt = snap.savedAt
    }

    private func saveSnapshot() {
        let snap = Snapshot(execTimes: lastNotifiedExec, savedAt: Date())
        snapshotSavedAt = snap.savedAt
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    // MARK: - 后台刷新（BGTaskScheduler）

    /// 提交下一次后台刷新请求（最早 15 分钟后；系统决定实际时机）。
    /// 注册入口见 AppDelegate；Info.plist 需含 BGTaskSchedulerPermittedIdentifiers。
    func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// 系统后台刷新回调（App 被挂起/杀掉后的兜底通道）：补一次轮询。
    func handleBackgroundRefresh(task: BGAppRefreshTask?) {
        scheduleBackgroundRefresh() // 先续期，保证后续还有机会
        guard let session, session.isAuthenticated else {
            task?.setTaskCompleted(success: true)
            return
        }
        Task { @MainActor in
            await pollOnce(session: session)
            task?.setTaskCompleted(success: true)
        }
    }
}
