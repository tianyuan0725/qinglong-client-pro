import SwiftUI
import UIKit

struct SubscriptionListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showEditor = false
    @State private var editing: Subscription? = nil
    @State private var confirmDelete: [Subscription]? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.subscriptions) { sub in
                    NavigationLink {
                        SubscriptionDetailView(sub: sub)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(sub.displayName).font(.subheadline.weight(.medium))
                                StatusPill(text: sub.typeLabel, color: .gray)
                            }
                            if !sub.url.isEmpty {
                                Text(sub.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                StatusPill(text: sub.statusLabel,
                                           color: sub.isDisabled == 1 ? .gray : (sub.status == 0 ? .green : (sub.status == 3 ? .blue : .secondary)))
                                if !sub.schedule.isEmpty {
                                    Text(sub.scheduleType == "interval" ? "间隔 \(sub.schedule)" : sub.schedule)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { confirmDelete = [sub] } label: { Label("删除", systemImage: "trash") }
                        Button {
                            Task { await session.toggleSubscriptions([sub]) }
                        } label: { Label(sub.isEnabled ? "禁用" : "启用", systemImage: sub.isEnabled ? "pause.fill" : "play.fill") }
                        .tint(.orange)
                        Button { editing = sub } label: { Label("编辑", systemImage: "pencil") }
                            .tint(.indigo)
                    }
                    .swipeActions(edge: .leading) {
                        Button { Task { await session.runSubscriptions(ids: [sub._id]) } } label: { Label("运行", systemImage: "play.fill") }
                            .tint(.green)
                        Button { Task { await session.stopSubscriptions(ids: [sub._id]) } } label: { Label("停止", systemImage: "stop.fill") }
                            .tint(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("订阅管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await session.loadSubscriptions() }
            .refreshable { await session.loadSubscriptions() }
            .sheet(isPresented: $showEditor) { SubscriptionEditorView(editing: nil) }
            .sheet(item: $editing) { sub in SubscriptionEditorView(editing: sub) }
            .alert("删除订阅", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("取消", role: .cancel) { confirmDelete = nil }
                Button("强制删除", role: .destructive) {
                    if let arr = confirmDelete { Task { await session.deleteSubscriptions(ids: arr.map { $0._id }) } }
                    confirmDelete = nil
                }
            } message: { Text(confirmDelete.map { "确定删除订阅 \($0.first?.displayName ?? "")？" } ?? "") }
        }
    }
}

struct SubscriptionDetailView: View {
    @EnvironmentObject var session: PanelSession
    let sub: Subscription

    @State private var logText = "（点击右上角刷新日志）"
    @State private var logLoading = false
    @State private var autoRefresh = false
    @State private var live: Subscription?

    private var current: Subscription { live ?? sub }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard
                actionButtons
                logCard
            }
            .padding()
        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await loadLog() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await refresh(); await loadLog() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            if autoRefresh { Task { await refresh(); await loadLog() } }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusPill(text: current.statusLabel,
                           color: current.isDisabled == 1 ? .gray : (current.status == 0 ? .green : (current.status == 3 ? .blue : .secondary)))
                Spacer()
                if current.status == 0 {
                    StatusPill(text: "自动刷新", color: .green)
                }
            }
            row("类型", current.typeLabel)
            row("别名", current.alias)
            if !current.url.isEmpty { row("地址", current.url) }
            if !current.schedule.isEmpty { row("周期", current.scheduleType == "interval" ? "间隔 \(current.schedule)" : current.schedule) }
            if !current.branch.isEmpty { row("分支", current.branch) }
            if !current.proxy.isEmpty { row("代理", current.proxy) }
            HStack(alignment: .top) {
                Text("自动").foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                Text("加任务 \(current.autoAddCron == 1 ? "是" : "否") · 删任务 \(current.autoDelCron == 1 ? "是" : "否")")
            }
        }
        .font(.subheadline)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            action("运行", "play.fill", .green) { Task { await session.runSubscriptions(ids: [current._id]); await refresh() } }
            action("停止", "stop.fill", .red) { Task { await session.stopSubscriptions(ids: [current._id]); await refresh() } }
            action(current.isEnabled ? "禁用" : "启用",
                   current.isEnabled ? "pause.fill" : "play.fill", .orange) { Task { await session.toggleSubscriptions([current]); await refresh() } }
        }
    }

    private func action(_ title: String, _ icon: String, _ color: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(color)
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("拉取日志")
                    .font(.headline)
                Spacer()
                Toggle("自动刷新", isOn: $autoRefresh).labelsHidden().toggleStyle(.switch).scaleEffect(0.8)
                Button { UIPasteboard.general.string = logText } label: { Image(systemName: "doc.on.doc") }
            }
            if logLoading {
                ProgressView().frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                ScrollView {
                    Text(logText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }.frame(maxHeight: 320)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func refresh() async {
        await session.loadSubscriptions()
        live = session.subscriptions.first { $0.id == sub.id }
    }

    private func loadLog() async {
        logLoading = true
        defer { logLoading = false }
        logText = await session.subscriptionLog(id: sub._id)
    }
}
