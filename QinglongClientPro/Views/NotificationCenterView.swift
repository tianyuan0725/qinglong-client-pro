import SwiftUI

/// 通知栏 —— 底部第一个页签。
/// 以「会话框」形式聚合两类通知：
/// 1) 任务通知：App 本地任务运行通知历史（气泡消息 + 未读徽标）；
/// 2) 青龙通知渠道：面板当前通知渠道 / 旧版多渠道配置，每个渠道一个会话，
///    可经面板发送系统通知并记录到对应会话。
struct NotificationCenterView: View {
    @EnvironmentObject var session: PanelSession
    @EnvironmentObject var notify: AppNotifyManager
    @State private var showTaskChat = false
    @State private var activeChannel: NotifyChannel?

    var body: some View {
        NavigationStack {
            List {
                // MARK: 任务通知会话（本地）
                Section {
                    Button { showTaskChat = true } label: {
                        conversationRow(
                            icon: "bell.badge.fill",
                            iconColor: qlBrandGreen,
                            title: "任务通知",
                            source: "task",
                            placeholder: "暂无任务通知"
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("本机通知")
                } footer: {
                    Text("任务开始 / 执行完成等系统推送的消息，都会在这里留存记录。")
                }

                // MARK: 青龙通知渠道会话
                Section {
                    if let ch = session.notificationConfig?.channel {
                        Button { activeChannel = ch } label: {
                            conversationRow(
                                icon: icon(for: ch),
                                iconColor: .blue,
                                title: ch.label,
                                source: ch.rawValue,
                                placeholder: "暂无消息",
                                subtitle: "面板当前通知方式"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if let items = session.notifyItems, !items.isEmpty {
                        ForEach(items) { item in
                            if let ch = item.channel {
                                Button { activeChannel = ch } label: {
                                    conversationRow(
                                        icon: icon(for: ch),
                                        iconColor: .gray,
                                        title: ch.label,
                                        source: ch.rawValue,
                                        placeholder: "暂无消息",
                                        subtitle: "多渠道配置"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if session.notificationConfig?.channel == nil && (session.notifyItems?.isEmpty ?? true) {
                        Button {
                            Task {
                                await session.loadNotificationConfig()
                                await session.loadNotifyItems()
                            }
                        } label: {
                            Label("加载面板通知渠道", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("青龙通知渠道")
                } footer: {
                    Text("每个青龙通知方式为一个会话；点进去可经面板发送通知。服务端推送到这些渠道的消息不会回传到 App，会话内仅记录本 App 主动发送的内容。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { notify.markAllRead() } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .disabled(notify.unreadCount == 0)
                }
            }
            .task {
                if session.notificationConfig == nil { await session.loadNotificationConfig() }
                await session.loadNotifyItems()
            }
            .sheet(isPresented: $showTaskChat) {
                TaskChatView()
            }
            .sheet(item: $activeChannel) { ch in
                ChannelDetailSheet(channel: ch, source: ch.rawValue)
            }
        }
    }

    // MARK: - 会话行

    private func conversationRow(icon: String, iconColor: Color, title: String,
                                 source: String, placeholder: String,
                                 subtitle: String? = nil) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let last = notify.lastMessage(source: source) {
                        Text(Self.timeText(last.date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(notify.lastMessage(source: source)?.body ?? placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            let unread = notify.unreadCount(source: source)
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Color.red))
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(for channel: NotifyChannel) -> String {
        switch channel {
        case .bark, .ntfy, .pushMe, .pushDeer, .iGot, .pushPlus, .wePlusBot: return "bell"
        case .serverChan, .wxPusherBot, .aibotk: return "paperplane"
        case .telegramBot: return "paperplane.fill"
        case .dingtalkBot: return "message.badge"
        case .weWorkBot, .weWorkApp: return "bubble.left.and.bubble.right"
        case .feishu: return "square.and.paperclip"
        case .email: return "envelope"
        case .gotify, .webhook, .chronocat, .openiLink, .wpush, .chat, .goCqHttpBot: return "arrow.triangle.2.circlepath"
        }
    }

    /// 时间显示：今天显示 HH:mm，更早显示 MM-dd HH:mm。
    static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "MM-dd HH:mm"
        }
        return f.string(from: date)
    }
}

/// 任务通知会话：气泡消息列表，进入即标记已读。
struct TaskChatView: View {
    @EnvironmentObject var notify: AppNotifyManager
    @Environment(\.dismiss) private var dismiss

    private var items: [AppNotifyManager.AppMessage] {
        notify.messages.filter { $0.source == "task" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("暂无任务通知")
                            .foregroundStyle(.secondary)
                        Text("任务开始 / 执行完成时会自动推送并留存到这里")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { msg in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(msg.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(msg.body)
                                    .font(.subheadline)
                                Text(NotificationCenterView.timeText(msg.date))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("任务通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { notify.clearMessages(source: "task") }
                        .disabled(items.isEmpty)
                }
            }
            .onAppear { notify.markRead(source: "task") }
        }
    }
}

/// 青龙通知渠道会话：渠道信息 + 经面板发送通知 + 消息记录。
struct ChannelDetailSheet: View {
    @EnvironmentObject var session: PanelSession
    @EnvironmentObject var notify: AppNotifyManager
    @Environment(\.dismiss) private var dismiss
    let channel: NotifyChannel
    /// 该会话对应的消息 source。
    let source: String

    @State private var title = "青龙客户端 Pro"
    @State private var messageText = ""
    @State private var sending = false
    @State private var resultText: String?

    private var isActiveChannel: Bool {
        session.notificationConfig?.channel == channel
    }

    private var items: [AppNotifyManager.AppMessage] {
        notify.messages.filter { $0.source == source }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("渠道", value: channel.label)
                    LabeledContent("标识", value: channel.rawValue)
                    LabeledContent("状态", value: isActiveChannel ? "面板当前通知方式" : "已配置（多渠道）")
                } header: {
                    Text("渠道信息")
                }

                if isActiveChannel {
                    Section {
                        TextField("标题", text: $title)
                        TextField("通知内容", text: $messageText)
                        Button {
                            Task { await send() }
                        } label: {
                            if sending {
                                ProgressView()
                            } else {
                                Label("发送到「\(channel.label)」", systemImage: "paperplane.fill")
                            }
                        }
                        .disabled(messageText.isEmpty || session.isBusy)
                        if let r = resultText {
                            Text(r)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("发送通知")
                    } footer: {
                        Text("内容将经面板当前通知方式（PUT /api/system/notify）推送，并记录到本会话。")
                    }
                } else {
                    Section {
                        Text("该渠道为面板多渠道配置，App 仅展示其信息；服务端推送到此渠道的消息不会回传到 App。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !items.isEmpty {
                    Section("消息记录") {
                        ForEach(items) { msg in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(msg.body)
                                    .font(.subheadline)
                                Text(NotificationCenterView.timeText(msg.date))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(channel.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { notify.markRead(source: source) }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let ok = await session.sendSystemNotify(title: title, content: messageText)
        if ok {
            notify.record(title: title, body: messageText, source: source)
            resultText = "已发送 ✓"
            messageText = ""
        } else {
            resultText = session.lastError ?? "发送失败"
        }
    }
}
