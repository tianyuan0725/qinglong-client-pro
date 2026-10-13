import SwiftUI

/// 通知栏 —— 底部第一个页签。
/// 以「会话框」形式聚合任务通知：App 本地任务运行通知历史
/// （气泡消息 + 未读徽标），覆盖任何来源运行的任务
/// （App 手动 / 青龙网页 / 面板定时自动跑）。
struct NotificationCenterView: View {
    @EnvironmentObject var notify: AppNotifyManager
    /// 后台保活开关：退后台播放静音音频防止被系统挂起（关闭更省电，通知可能延迟）。
    @AppStorage("qlpro_keepalive") private var keepAliveOn: Bool = true
    /// 任务状态轮询间隔（秒，3–60）：越大越省电，完成通知延迟也越大。
    @AppStorage("qlpro_poll_interval") private var pollInterval: Int = 5

    var body: some View {
        NavigationStack {
            List {
                // MARK: 后台保活与轮询（省电设置）
                Section {
                    Toggle("后台保活", isOn: $keepAliveOn)
                        .onChange(of: keepAliveOn) { on in
                            BackgroundKeeper.shared.setEnabled(on)
                        }
                    Stepper(value: $pollInterval, in: 3...60, step: 1) {
                        HStack {
                            Text("轮询间隔")
                            Spacer()
                            Text("\(pollInterval) 秒")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: pollInterval) { v in
                        CronWatchService.shared.updateInterval(TimeInterval(v))
                    }
                } header: {
                    Text("后台与通知")
                } footer: {
                    Text("后台保活：退到后台时播放静音音频防止被系统挂起（需保持任务通知开启），任务完成可即时推送；关闭更省电，但通知可能延迟。轮询间隔越大越省电，通知也越慢（3–60 秒）。")
                }

                // MARK: 任务通知会话（本地）
                Section {
                    NavigationLink {
                        TaskChatView()
                    } label: {
                        conversationRow(
                            icon: "bell.badge.fill",
                            iconColor: qlBrandGreen,
                            title: "任务通知",
                            source: "task",
                            placeholder: "暂无任务通知"
                        )
                    }
                } header: {
                    Text("本机通知")
                } footer: {
                    Text("任务开始 / 执行完成等系统推送的消息，都会在这里留存记录。")
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
                    .disabled(notify.unreadTotal == 0)
                }
            }
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
/// 任务通知聊天界面（类微信聊天框）：由通知栏「任务通知」push 进入，
/// 不再用 sheet 弹窗；返回按钮由外层 NavigationStack 提供。
struct TaskChatView: View {
    @EnvironmentObject var notify: AppNotifyManager

    private var items: [AppNotifyManager.AppMessage] {
        notify.messages.filter { $0.source == "task" }
    }

    var body: some View {
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清空") { notify.clearMessages(source: "task") }
                    .disabled(items.isEmpty)
            }
        }
        .onAppear { notify.markRead(source: "task") }
    }
}

