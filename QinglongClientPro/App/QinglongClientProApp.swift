import SwiftUI
import BackgroundTasks

@main
struct QinglongClientProApp: App {
    @StateObject private var store = ConnectionStore()
    @StateObject private var appState = AppState()
    @StateObject private var appLock = AppLockManager()
    @StateObject private var updater = UpdateChecker.shared
    // 本地通知（任务运行弹窗提醒）：单例，尽早创建以注册通知 delegate
    @StateObject private var notifier = AppNotifyManager.shared
    // 后台刷新任务注册（BGTaskScheduler 需在 didFinishLaunching 时登记）
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(appState)
                .environmentObject(appLock)
                .environmentObject(updater)
                .environmentObject(notifier)
                .environment(\.sizeCategory, appState.contentSizeCategory)
                .tint(qlBrandGreen)
                .preferredColorScheme(appState.preferredColorScheme)
                .overlay {
                    if appLock.isLocked {
                        AppLockOverlay()
                            .environmentObject(appLock)
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // 冷启动首帧 active + 回前台统一入口（内部区分冷/热）
                appLock.handleDidBecomeActive()
            case .background:
                appLock.handleDidEnterBackground()
            default:
                break
            }
        }
    }
}

/// 后台刷新任务注册：App 被系统挂起/杀掉后，系统择机唤醒 App 补一次
/// 任务状态轮询（CronWatchService.handleBackgroundRefresh）。
/// 标识需同时登记在 Info.plist 的 BGTaskSchedulerPermittedIdentifiers。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.qlpro.cronrefresh", using: nil
        ) { task in
            Task { @MainActor in
                CronWatchService.shared.handleBackgroundRefresh(task: task as? BGAppRefreshTask)
            }
        }
        return true
    }
}

struct RootView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var appLock: AppLockManager

    var body: some View {
        Group {
            // 注意：内容常驻，不随 appLock.isLocked 切换而增删分支。
            // 锁定/解锁若整体替换视图树，PanelTabView 会被重建、
            // @StateObject PanelSession 随之重置（token 丢失），
            // 解锁后就会掉到面板登录页（v2.0.1 反馈的 bug）。
            // 锁定时仅将内容整体隐藏（opacity 0），AppLockOverlay 是
            // 不透明全屏遮罩，锁定期间用户只会看到解锁页。
            if let conn = appState.selected {
                PanelTabView(connection: conn)
            } else {
                ConnectionListView()
            }
        }
        .opacity(appLock.isLocked ? 0 : 1)
        .onAppear {
            autoOpenPanelIfNeeded()
        }
    }

    /// 启动时的面板恢复策略（v2.0.3）：
    /// ① 「启动时自动连接默认面板」开关打开 → 进默认面板；
    /// ② 否则恢复上次使用的面板（含解锁后冷启动场景）；
    /// ③ 仅配置了一个面板 → 直接进入（无需任何开关，重装后也生效，
    ///    因为面板列表存 Keychain、不随 UserDefaults 丢失）。
    /// 用户录屏反馈：解锁后落在连接列表页，配好面板却每次都要手点。
    private func autoOpenPanelIfNeeded() {
        // 清理已删除面板的悬空引用（否则开关显示开、选择器却空白）
        if !appState.defaultConnectionId.isEmpty,
           store.connection(withId: appState.defaultConnectionId) == nil {
            appState.defaultConnectionId = ""
        }
        if !appState.lastConnectionId.isEmpty,
           store.connection(withId: appState.lastConnectionId) == nil {
            appState.lastConnectionId = ""
        }
        guard appState.selected == nil else { return }
        if !appState.defaultConnectionId.isEmpty,
           let conn = store.connection(withId: appState.defaultConnectionId) {
            appState.selected = conn
            return
        }
        if !appState.lastConnectionId.isEmpty,
           let conn = store.connection(withId: appState.lastConnectionId) {
            appState.selected = conn
            return
        }
        if store.connections.count == 1 {
            appState.selected = store.connections[0]
        }
    }
}
