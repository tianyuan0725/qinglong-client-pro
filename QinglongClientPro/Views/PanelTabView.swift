import SwiftUI
import UIKit

struct PanelTabView: View {
    let connection: Connection
    @StateObject private var session: PanelSession
    @EnvironmentObject var appState: AppState

    init(connection: Connection) {
        self.connection = connection
        _session = StateObject(wrappedValue: PanelSession(connection: connection))
    }

    var body: some View {
        Group {
            if session.isAuthenticated {
                TabView {
                    CronListView()
                        .tabItem { Label("定时任务", systemImage: "list.bullet.rectangle") }
                    EnvListView()
                        .tabItem { Label("环境变量", systemImage: "key") }
                    ConfigListView()
                        .tabItem { Label("配置文件", systemImage: "folder") }
                    ProfileView()
                        .tabItem { Label("我的", systemImage: "person.crop.circle") }
                }
                .tint(qlBrandGreen)
                .environmentObject(session)
                .overlay { if session.isBusy { LoadingOverlay() } }
                .errorToast($session.lastError)
            } else {
                AuthView()
                    .environmentObject(session)
            }
        }
        .task { await session.login() }
        .alert("连接失败", isPresented: Binding(
            get: { session.authError != nil },
            set: { if !$0 { session.authError = nil } }
        )) {
            Button("返回面板列表") { appState.selected = nil }
            Button("重试") { Task { await session.login() } }
        } message: { Text(session.authError ?? "") }
    }
}

struct AuthView: View {
    @EnvironmentObject var session: PanelSession
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "server.rack")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            ProgressView()
            Text("正在连接 \(session.connection.name)…")
                .font(.headline)
            Text(session.connection.baseURLString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
