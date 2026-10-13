import Foundation
import UIKit
import SwiftUI
import UserNotifications

/// App 本地通知（iOS 系统弹窗横幅，类似微信收到消息的提醒）。
/// 注意与「面板服务端通知渠道」（Bark / Server 酱等，PUT /api/system/notify）
/// 是两回事：本类只在设备本地发通知，不依赖面板配置。
@MainActor
final class AppNotifyManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotifyManager()

    /// 总开关：任务运行时发送本地通知。
    /// 注意：@AppStorage 的默认值不会触发 didSet，所以 init 里要主动补一次授权请求，
    /// 否则老用户升级后开关显示「开」但从未弹过系统授权对话框 → 通知被系统静默丢弃
    /// （v2.0.5 用户反馈「运行完收不到通知」的根因）。
    @AppStorage("qlpro_localNotify") var enabled: Bool = true {
        didSet { if enabled { requestAuthorization() } }
    }

    /// 任务「开始执行」通知开关（受总开关 enabled 控制）。
    @AppStorage("qlpro_notify_start") var notifyOnStart: Bool = true
    /// 任务「执行完成」通知开关（受总开关 enabled 控制）。
    @AppStorage("qlpro_notify_finish") var notifyOnFinish: Bool = true

    /// 是否已获得系统通知权限。
    @Published var authorized = false

    // MARK: - 通知中心（in-app 消息历史）

    /// 通知中心里展示的一条消息。
    struct AppMessage: Identifiable, Codable, Equatable {
        let id: String
        let title: String
        let body: String
        let date: Date
        var read: Bool
        /// 来源会话标识："task" = 本地任务通知；其余为青龙渠道 rawValue（如 "bark"）。
        var source: String
    }

    /// 通知中心消息历史（持久化到磁盘，App 重启不丢；最新在最上方）。
    @Published private(set) var messages: [AppMessage] = []

    private var messagesFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("app_messages.json")
    }

    private func loadMessages() {
        guard let url = messagesFileURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([AppMessage].self, from: data) else { return }
        messages = list
    }

    private func persistMessages() {
        guard let url = messagesFileURL,
              let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: url)
    }

    /// 记录一条消息到通知中心（与系统通知一起发；source 决定归入哪个会话）。
    func record(title: String, body: String, source: String = "task") {
        let msg = AppMessage(id: UUID().uuidString, title: title, body: body,
                             date: Date(), read: false, source: source)
        messages.insert(msg, at: 0)
        if messages.count > 300 { messages = Array(messages.prefix(300)) }
        persistMessages()
        syncBadge()
    }

    /// 同步桌面 App 图标徽标为未读数（0 时清除）。
    /// 用户要求：有通知消息时手机桌面图标显示数字。
    private func syncBadge() {
        UIApplication.shared.applicationIconBadgeNumber = unreadTotal
    }

    /// 未读消息总数。
    var unreadTotal: Int { messages.filter { !$0.read }.count }

    /// 某会话的未读数。
    func unreadCount(source: String) -> Int { messages.filter { $0.source == source && !$0.read }.count }

    /// 某会话的最新一条消息（用于会话列表预览）。
    func lastMessage(source: String) -> AppMessage? { messages.first { $0.source == source } }

    func markRead(source: String) {
        var changed = false
        for i in messages.indices where messages[i].source == source && !messages[i].read {
            messages[i].read = true; changed = true
        }
        if changed { persistMessages() }
        syncBadge()
    }

    func markAllRead() {
        var changed = false
        for i in messages.indices where !messages[i].read { messages[i].read = true; changed = true }
        if changed { persistMessages() }
        syncBadge()
    }

    func clearMessages(source: String) {
        messages.removeAll { $0.source == source }
        persistMessages()
        syncBadge()
    }

    /// 正在监听完成状态的任务 id（避免重复轮询）。
    private var watchingIds = Set<String>()

    private override init() {
        super.init()
        loadMessages()
        syncBadge()
        // 注册 delegate：让 App 在前台时通知也以横幅形式弹出
        // （系统默认前台不展示通知）。
        UNUserNotificationCenter.current().delegate = self
        refreshStatus()
        // 默认开启但从未请求过授权 → 启动即补请求（系统对话框只弹一次，
        // 用户错过/拒绝后设置页有「前往系统设置」引导）。
        if enabled {
            requestAuthorization()
        }
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let ok = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            Task { @MainActor in self?.authorized = ok }
        }
    }

    /// 请求通知权限（首次开启时弹系统对话框）。
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// 打开本 App 的系统设置页（用户拒绝过权限后只能去系统设置手动开）。
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 前台展示：横幅 + 列表 + 声音（否则 App 在前台时完全不弹）。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // MARK: - 发送

    /// 发送一条本地通知（立即展示）。未授权时先补一次授权请求。
    /// 同时记录到通知中心（in-app 消息历史），供「通知」页签展示。
    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        record(title: title, body: body)
        if !authorized {
            // 兜底：从未授权过（用户可能拒绝过系统对话框），先请求再发。
            requestAuthorization()
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: unreadTotal)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 任务开始执行提醒。
    func notifyCronStarted(name: String) {
        guard enabled, notifyOnStart else { return }
        notify(title: "青龙客户端 Pro", body: "任务「\(name)」已开始执行")
    }

    /// 任务执行完成提醒。
    /// - Parameter detail: 推送通知的详细内容（耗时 / 日志末尾等）；为空时只显示完成状态。
    func notifyCronFinished(name: String, detail: String = "") {
        guard enabled, notifyOnFinish else { return }
        var body = "任务「\(name)」执行完成"
        if !detail.isEmpty { body += "\n" + detail }
        notify(title: "青龙客户端 Pro", body: body)
    }

    // MARK: - 运行状态轮询

    /// 任务启动后轮询运行状态，结束时发「已完成」通知。
    /// 轮询同时会刷新任务列表（副作用：列表状态保持最新）。
    /// 去重：同一任务同时只允许一个监听（列表页自动监听 + 手动运行都会调用）。
    /// - Parameters:
    ///   - session: 当前面板会话
    ///   - cronId: 任务 id
    ///   - name: 任务名称（通知文案用）
    func watchCron(session: PanelSession, cronId: String, name: String) {
        guard !watchingIds.contains(cronId) else { return }
        watchingIds.insert(cronId)
        Task { @MainActor in
            // 最多轮询 10 分钟（120 × 3s…按 5s 算 120 次），超时不再打扰。
            defer { watchingIds.remove(cronId) }
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await session.loadCrons()
                if let cron = session.crons.first(where: { $0.id == cronId }), !cron.isRunning {
                    // 组装推送通知的详细内容：耗时 + 日志末尾（与面板推送内容一致），
                    // 而不是只写「执行成功/失败」。
                    let detail = await cronFinishDetail(session: session, cron: cron)
                    notifyCronFinished(name: name, detail: detail)
                    return
                }
            }
        }
    }

    /// 组装任务完成通知的详细内容（耗时 + 日志末尾若干行）。
    private func cronFinishDetail(session: PanelSession, cron: CronTask) async -> String {
        var parts: [String] = []
        if let secs = cron.lastRunningTime?.value, secs > 0 {
            parts.append(secs >= 60
                ? String(format: "耗时：%.1f 分钟", Double(secs) / 60)
                : String(format: "耗时：%d 秒", secs))
        }
        let logTail = await session.cronLogTail(id: cron.id)
        if !logTail.isEmpty {
            if !parts.isEmpty { parts.append("") }
            parts.append("—— 日志末尾 ——")
            parts.append(logTail)
        }
        return parts.joined(separator: "\n")
    }
}
