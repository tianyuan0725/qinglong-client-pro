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
        .onChange(of: scenePhase) { _, phase in
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

    var body: some View {
        Group {
            if let conn = appState.selected {
                PanelTabView(connection: conn)
            } else {
                ConnectionListView()
            }
        }
        .onAppear {
            // Auto-open the default panel if still present.
            if appState.selected == nil, !appState.defaultConnectionId.isEmpty,
               let conn = store.connection(withId: appState.defaultConnectionId) {
                appState.selected = conn
            }
        }
    }
}
