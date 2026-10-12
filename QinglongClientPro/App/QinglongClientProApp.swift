import SwiftUI

@main
struct QinglongClientProApp: App {
    @StateObject private var store = ConnectionStore()
    @StateObject private var appState = AppState()
    @StateObject private var appLock = AppLockManager()
    @StateObject private var updater = UpdateChecker.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(appState)
                .environmentObject(appLock)
                .environmentObject(updater)
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
            // Auto-open the default panel if still present.
            if appState.selected == nil, !appState.defaultConnectionId.isEmpty,
               let conn = store.connection(withId: appState.defaultConnectionId) {
                appState.selected = conn
            }
        }
    }
}
