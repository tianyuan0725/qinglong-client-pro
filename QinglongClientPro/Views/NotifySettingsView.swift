import SwiftUI

/// 通知设置（GET/PUT /api/user/notification）。保存时青龙会自动发送一条测试通知验证配置。
struct NotifySettingsView: View {
    @EnvironmentObject var session: PanelSession
    @State private var channel: NotifyChannel = .bark
    @State private var fields: [String: String] = [:]
    @State private var saved = false

    var body: some View {
        Form {
            Section("通知渠道") {
                Picker("渠道", selection: $channel) {
                    ForEach(NotifyChannel.allCases) { ch in
                        Text(ch.label).tag(ch)
                    }
                }
                .onChange(of: channel) { _ in loadFields() }
            }
            Section {
                ForEach(channel.fields, id: \.key) { f in
                    TextField(f.hint, text: binding(for: f.key))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("渠道参数")
            } footer: {
                Text("保存后青龙会自动发送一条测试通知验证配置；若提示失败，请检查上方参数。")
            }
        }
        .navigationTitle("通知设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .disabled(session.isBusy)
            }
        }
        .task {
            await session.loadNotificationConfig()
            if let cfg = session.notificationConfig, let ch = cfg.channel {
                channel = ch
                fields = cfg.raw
            } else {
                loadFields()
            }
        }
        .alert("已保存", isPresented: $saved) {
            Button("好") { }
        } message: {
            Text("通知配置已保存，测试通知已由面板发送。")
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { fields[key] ?? "" },
            set: { fields[key] = $0 }
        )
    }

    /// 切换渠道：当前配置正是该渠道则沿用，否则清空。
    private func loadFields() {
        if session.notificationConfig?.channel == channel {
            fields = session.notificationConfig?.raw ?? [:]
        } else {
            fields = [:]
        }
    }

    private func save() async {
        var cfg = NotificationConfig()
        cfg.raw = fields
        let ok = await session.saveNotificationConfig(cfg, channel: channel)
        if ok { saved = true }
    }
}
