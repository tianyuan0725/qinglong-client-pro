import Foundation
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

    /// 正在监听完成状态的任务 id（避免重复轮询）。
    private var watchingIds = Set<String>()

    private override init() {
        super.init()
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
    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        if !authorized {
            // 兜底：从未授权过（用户可能拒绝过系统对话框），先请求再发。
            requestAuthorization()
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 任务开始执行提醒。
    func notifyCronStarted(name: String) {
        guard enabled, notifyOnStart else { return }
        notify(title: "青龙客户端 Pro", body: "任务「\(name)」已开始执行")
    }

    /// 任务执行完成提醒。
    func notifyCronFinished(name: String) {
        guard enabled, notifyOnFinish else { return }
        notify(title: "青龙客户端 Pro", body: "任务「\(name)」已执行完成")
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
                    notifyCronFinished(name: name)
                    return
                }
            }
        }
    }
}
