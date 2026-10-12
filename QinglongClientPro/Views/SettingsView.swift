import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: PanelSession
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ConnectionStore

    private let schemes = ["system": "跟随系统", "light": "浅色", "dark": "深色"]

    var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    Picker("主题", selection: $appState.colorSchemeRaw) {
                        ForEach(schemes.keys.sorted(by: { schemes[$0]! < schemes[$1]! }), id: \.self) { key in
                            Text(schemes[key]!).tag(key)
                        }
                    }
                }

                Section("当前面板") {
                    LabeledContent("名称", value: session.connection.name)
                    LabeledContent("地址", value: session.connection.baseURLString)
                    LabeledContent("认证", value: session.connection.authType.rawValue)
                    Button {
                        Task { await session.loadAll() }
                    } label: {
                        Label("刷新全部数据", systemImage: "arrow.clockwise")
                    }
                }

                Section("面板管理") {
                    Button {
                        appState.selected = nil
                    } label: {
                        Label("返回面板列表 / 切换面板", systemImage: "list.bullet")
                    }
                    if !appState.defaultConnectionId.isEmpty {
                        Toggle("作为默认面板自动连接", isOn: Binding(
                            get: { appState.defaultConnectionId == session.connection.id },
                            set: { on in appState.defaultConnectionId = on ? session.connection.id : "" }
                        ))
                    } else {
                        Button {
                            appState.defaultConnectionId = session.connection.id
                        } label: {
                            Label("设为默认面板", systemImage: "star")
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "青龙客户端 Pro")
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("构建", value: "TrollStore / 自签可用")
                    Text("本应用仅在你自己拥有的青龙面板上使用，所有凭证保存在本机 Keychain。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return v
    }
}
