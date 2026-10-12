import SwiftUI

/// 系统通知：发送测试通知 + 查看/编辑当前通知方式 + 多渠道通知配置管理（旧版面板）。
struct SystemNotifyView: View {
    @EnvironmentObject var session: PanelSession

    @State private var notifyTitle = "青龙客户端 Pro"
    @State private var notifyContent = "这是一条来自青龙客户端 Pro 的测试通知"
    @State private var sending = false
    @State private var sentOK = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var confirmDelete: NotifyItem?

    var body: some View {
        List {
            // MARK: 当前通知方式
            Section {
                if let cfg = session.notificationConfig, let ch = cfg.channel {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(qlBrandGreen)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.label)
                                .font(.body.weight(.semibold))
                            Text("当前通知方式")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink {
                            NotifySettingsView()
                                .environmentObject(session)
                        } label: {
                            Text("编辑")
                                .font(.subheadline)
                        }
                    }
                    // 关键参数摘要（打码）
                    ForEach(ch.fields, id: \.key) { f in
                        let v = cfg.value(f.key)
                        if !v.isEmpty {
                            HStack {
                                Text(fieldLabel(f.key))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(masked(v, revealed: false))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        Text(session.notificationConfig?.type.isEmpty == false
                             ? "当前通知方式：\(session.notificationConfig?.type ?? "")"
                             : "尚未配置通知方式")
                            .font(.subheadline)
                        Spacer()
                        NavigationLink {
                            NotifySettingsView()
                                .environmentObject(session)
                        } label: {
                            Text("去配置")
                                .font(.subheadline)
                        }
                    }
                }
            } header: {
                Text("当前通知方式")
            } footer: {
                Text("任务运行结束、失败等消息会通过该方式推送。保存后面板会自动发送一条测试通知。")
                    .font(.caption)
            }

            // MARK: 发送系统通知
            Section {
                TextField("通知标题", text: $notifyTitle)
                TextField("通知内容", text: $notifyContent)
                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane")
                        Text("发送系统通知")
                        Spacer()
                        if sending { ProgressView() }
                    }
                }
                .disabled(sending || notifyTitle.isEmpty || notifyContent.isEmpty)
            } header: {
                Text("发送系统通知")
            } footer: {
                Text("立即通过当前通知方式发送一条通知（PUT /api/system/notify），用于验证通知渠道是否可用。")
                    .font(.caption)
            }

            // MARK: 多渠道通知配置（旧版面板）
            if session.notifyMultiSupported {
                Section {
                    if let items = session.notifyItems, !items.isEmpty {
                        ForEach(items) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "bell")
                                    .foregroundStyle(qlBrandGreen)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name?.isEmpty == false ? item.name! : "未命名通知")
                                        .font(.subheadline)
                                    Text("\(item.channelLabel) · \(item.createdText)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    confirmDelete = item
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } else {
                        Text("暂无通知配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("通知配置（\(session.notifyItems?.count ?? 0)）")
                } footer: {
                    Text("面板支持多个通知配置，可分别用于不同场景。新版青龙已将该功能合并为上方单一通知方式。")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("系统通知")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await session.loadNotificationConfig()
            await session.loadNotifyItems()
        }
        .alert("已发送", isPresented: $sentOK) {
            Button("好") { }
        } message: {
            Text("通知已通过当前通知方式发送，请查看对应渠道是否收到。")
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("好") { }
        }
        .confirmationDialog("删除该通知配置？", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let item = confirmDelete {
                    Task { _ = await session.deleteNotifyItem(item) }
                }
            }
            Button("取消", role: .cancel) { }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let ok = await session.sendSystemNotify(title: notifyTitle, content: notifyContent)
        if ok { sentOK = true }
    }

    /// 渠道字段的中文名（取字段提示的首段）。
    private func fieldLabel(_ key: String) -> String {
        if let ch = session.notificationConfig?.channel,
           let f = ch.fields.first(where: { $0.key == key }) {
            return f.hint.components(separatedBy: "，").first ?? key
        }
        return key
    }
}
