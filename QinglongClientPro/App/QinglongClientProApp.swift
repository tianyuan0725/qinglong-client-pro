import SwiftUI

@main
struct QinglongClientProApp: App {
    @StateObject private var store = ConnectionStore()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(appState)
                .preferredColorScheme(appState.preferredColorScheme)
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
