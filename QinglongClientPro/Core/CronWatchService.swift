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
    private let snapshotKey = "qlpro_cron_watch_snapshot"
    /// 离线补通知的新鲜度阈值：超过该时长不再补发（避免几天后启动补一堆旧通知）。
    private let offlineReplayMaxAge: TimeInterval = 6 * 3600

    private init() {}

    // MARK: - 启停

    /// 开始全局监听（面板会话建立后调用，重复调用安全）。
    func start(session: PanelSession) {
        self.session = session
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
        // 通知/保活开关变化时自动同步（开着才值得后台耗电）
        if AppNotifyManager.shared.enabled && BackgroundKeeper.isEnabled {
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
            establishBaseline(session: session, byId: byId, current: current)
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
                    let detail = finishDetail(cron: cron)
                    AppNotifyManager.shared.notifyCronFinished(name: cron.name, detail: detail)
                } else {
                    manualStartNotified.remove(id)
                }
            } else if !nowRunning && !alreadyNotified && execTime > 0 {
                // ② 快速任务：两轮轮询之间跑完，从未见到 running
                changed = true
                manualStartNotified.remove(id)
                lastNotifiedExec[id] = execTime
                let detail = finishDetail(cron: cron)
                AppNotifyManager.shared.notifyCronFinished(name: cron.name, detail: detail)
            }
        }
        if changed || lastStates.count != current.count {
            lastStates = current
            saveSnapshot()
        }
    }

    /// 建立基线：首轮成功加载后记录状态；同时补发「离线期间完成」的通知。
    private func establishBaseline(session: PanelSession, byId: [String: CronTask], current: [String: Bool]) {
        // 补发：上次快照之后又有新执行完成的任务（App 关闭/被杀期间跑完的）。
        // 注意：先取本地常量快照——下面会覆盖属性，而补发在 Task 里异步执行。
        let previousExec = lastNotifiedExec
        let savedAt = snapshotSavedAt
        if let savedAt, Date().timeIntervalSince(savedAt) < offlineReplayMaxAge {
            Task { @MainActor in
                for (id, cron) in byId where !cron.isRunning {
                    let execTime = cron.lastExecutionTime?.value ?? 0
                    let known = previousExec[id]
                    // 有新执行（或首次记录到该任务有执行）且没在跑 → 离线期间完成
                    if execTime > 0, (known == nil || execTime > known!) {
                        let detail = finishDetail(cron: cron)
                        AppNotifyManager.shared.notifyCronFinished(name: cron.name, detail: detail)
                    }
                }
            }
        }
        // 基线：记录当前执行时间戳，之后只通知「新发生的执行」
        for (id, cron) in byId {
            lastNotifiedExec[id] = cron.lastExecutionTime?.value ?? 0
        }
        lastStates = current
        baselined = true
        saveSnapshot()
    }

    /// 组装任务完成通知的详细内容（对齐青龙面板推送到微信的通知格式）：
    /// 「执行成功 + 耗时 + 完成时间」，不打印脚本日志。
    private func finishDetail(cron: CronTask) -> String {
        var lines: [String] = ["执行成功"]
        if let secs = cron.lastRunningTime?.value, secs > 0 {
            lines.append(secs >= 60
                ? String(format: "耗时: %.1f 分钟", Double(secs) / 60)
                : String(format: "耗时: %d 秒", secs))
        }
        if let ms = cron.lastExecutionTime?.value, ms > 0 {
            lines.append("时间: \(Self.timeText(ms: ms))")
        }
        return lines.joined(separator: "\n")
    }

    /// last_execution_time（毫秒时间戳）→ "HH:mm:ss"。
    private static func timeText(ms: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
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
