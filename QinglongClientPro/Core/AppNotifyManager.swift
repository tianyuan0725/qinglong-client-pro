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
    @AppStorage("qlpro_localNotify") var enabled: Bool = true {
        didSet { if enabled { requestAuthorization() } }
    }

    /// 是否已获得系统通知权限。
    @Published var authorized = false

    private init() {
        // 注册 delegate：让 App 在前台时通知也以横幅形式弹出
        // （系统默认前台不展示通知）。
        UNUserNotificationCenter.current().delegate = self
        refreshStatus()
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

    /// 发送一条本地通知（立即展示）。
    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 任务开始执行提醒。
    func notifyCronStarted(name: String) {
        guard enabled else { return }
        notify(title: "青龙客户端 Pro", body: "任务「\(name)」已开始执行")
    }

    /// 任务执行完成提醒。
    func notifyCronFinished(name: String) {
        guard enabled else { return }
        notify(title: "青龙客户端 Pro", body: "任务「\(name)」已执行完成")
    }

    // MARK: - 运行状态轮询

    /// 任务启动后轮询运行状态，结束时发「已完成」通知。
    /// 轮询同时会刷新任务列表（副作用：列表状态保持最新）。
    /// - Parameters:
    ///   - session: 当前面板会话
    ///   - cronId: 任务 id
    ///   - name: 任务名称（通知文案用）
    func watchCron(session: PanelSession, cronId: String, name: String) {
        Task { @MainActor in
            // 最多轮询 10 分钟（120 × 5s），超时不再打扰。
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await session.loadCrons()
                if let cron = session.crons.first(where: { $0.id == cronId }), !cron.isRunning {
                    notifyCronFinished(name: name)
                    return
                }
            }
        }
    }
}
