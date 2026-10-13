import SwiftUI

/// 定时任务列表：顶部系统概览 + 筛选段（全部 / 运行中 / 未使用 / 已禁用）。
struct CronListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var search = ""
    @State private var filter: String = "all"
    @State private var showEditor = false
    @State private var editing: CronTask?

    private var filtered: [CronTask] {
        var list = session.crons
        switch filter {
        case "running":
            list = list.filter { $0.isRunning }
        case "unused":
            list = list.filter { ($0.lastExecutionTime?.value ?? 0) == 0 && ($0.lastRunningTime?.value ?? 0) == 0 }
        case "disabled":
            list = list.filter { !$0.isEnabled }
        default:
            break
        }
        guard !search.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.command.localizedCaseInsensitiveContains(search) ||
            $0.schedule.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                }
                .listRowSeparator(.hidden)

                Section {
                    Picker("状态", selection: $filter) {
                        Text("全部").tag("all")
                        Text("运行中").tag("running")
                        Text("未使用").tag("unused")
                        Text("已禁用").tag("disabled")
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listRowSeparator(.hidden)

                Section {
                    ForEach(filtered) { cron in
                        row(cron)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await session.deleteCron([cron.id]) }
                                } label: { Label("删除", systemImage: "trash") }
                                Button {
                                    Task { @MainActor in
                                        // 本地通知：任务开始执行即提醒，结束后再提醒一次
                                        // （用户要的是苹果系统弹窗，类微信横幅）
                                        let ok = await session.runCron([cron.id])
                                        if ok {
                                            AppNotifyManager.shared.notifyCronStarted(name: cron.name)
                                            AppNotifyManager.shared.watchCron(session: session, cronId: cron.id, name: cron.name)
                                        }
                                    }
                                } label: { Label("运行", systemImage: "play") }
                                    .tint(.green)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await session.toggleCron(cron) }
                                } label: {
                                    Label(cron.isEnabled ? "禁用" : "启用",
                                          systemImage: cron.isEnabled ? "pause" : "play")
                                }
                                .tint(cron.isEnabled ? .orange : .blue)
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("定时任务")
            .searchable(text: $search, prompt: "搜索名称 / 命令 / 周期")
            .refreshable { await session.loadCrons() }
            .overlay {
                if session.crons.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("暂无任务，点右上角 + 新增")
                            .foregroundStyle(.secondary)
                    }
                } else if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("没有匹配的任务")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = nil
                        showEditor = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showEditor) {
                CronEditorView(editing: editing)
                    .environmentObject(session)
            }
            .task {
                await session.loadCrons()
                if session.systemInfo == nil { await session.loadSystem() }
                if session.panelInfo == nil { await session.loadPanelInfo() }
                if session.subscriptions.isEmpty { await session.loadSubscriptions() }
                // 自动监听运行中任务：面板定时自动跑的任务，完成时也发本地通知
                // （不只是手动点「运行」的；watchCron 内部去重）
                for cron in session.crons where cron.isRunning {
                    AppNotifyManager.shared.watchCron(session: session, cronId: cron.id, name: cron.name)
                }
            }
        }
    }

    // MARK: - 系统概览卡片

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("青龙 v\(session.panelInfo?.version ?? session.systemInfo?.version ?? "—")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(qlBrandGreen)
                Spacer()
                HStack(spacing: 14) {
                    statItem("任务", session.cronCount, .blue)
                    statItem("运行中", session.runningCount, .green)
                    statItem("变量", session.envCount, .purple)
                    statItem("订阅", session.subscriptions.count, .orange)
                }
            }
            if let sys = session.systemInfo, sys.cpuUsageText != nil || sys.memoryUsageText != nil || sys.diskUsageText != nil {
                Divider()
                HStack(spacing: 16) {
                    if let cpu = sys.cpuUsageText { miniItem("cpu", "CPU", cpu) }
                    if let mem = sys.memoryUsageText { miniItem("memorychip", "内存", mem) }
                    if let disk = sys.diskUsageText { miniItem("internaldrive", "磁盘", disk) }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func miniItem(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func row(_ cron: CronTask) -> some View {
        NavigationLink {
            CronDetailView(cron: cron)
                .environmentObject(session)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: cron.isRunning ? "arrow.triangle.2.circlepath" : "timer")
                    .foregroundStyle(cron.isRunning ? Color.green : qlBrandGreen)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cron.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(cron.schedule).font(.caption2).foregroundStyle(.secondary)
                    if !cron.labels.isEmpty {
                        Text(cron.labels.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                StatusPill(text: cron.statusLabel,
                           color: cron.isRunning ? .green : (cron.isEnabled ? .blue : .gray))
            }
            .padding(.vertical, 4)
        }
    }
}
