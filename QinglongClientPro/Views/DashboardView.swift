import SwiftUI

/// 仪表盘 —— 仿青龙面板网页版仪表盘：系统状态（CPU/内存/磁盘）、
/// 任务/变量/订阅统计、运行中任务、最近执行任务、面板信息。
struct DashboardView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        NavigationStack {
            List {
                // MARK: 系统状态
                Section {
                    if let sys = session.dashboardSystem {
                        statusRow("memorychip", "内存使用率", sys.memoryPercentText)
                        statusRow("internaldrive", "内存", sys.memoryBytesText)
                        statusRow("clock", "系统运行", sys.uptimeText)
                        statusRow("square.stack.3d.up", "堆内存", sys.heapText)
                        statusRow("waveform.path.ecg", "负载 (1m)", sys.loadText)
                        statusRow("cpu", "CPU", sys.cpuText)
                    } else if session.systemInfo != nil {
                        Text("当前面板版本较低（低于 v2.23），暂不支持读取系统资源")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("正在读取系统状态…")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("系统状态", systemImage: "gauge.medium")
                }

                // MARK: 统计概览
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statTile("定时任务", session.cronCount, "list.bullet.rectangle", .blue)
                        statTile("运行中", session.runningCount, "arrow.triangle.2.circlepath", .green)
                        statTile("环境变量", session.envCount, "key", .purple)
                        statTile("订阅", session.subscriptions.count, "square.and.arrow.down", .orange)
                        statTile("今日执行", session.dashboardOverview?.todayRuns ?? 0, "bolt", .green)
                        statTile("今日成功", session.dashboardOverview?.todaySuccess ?? 0, "checkmark.circle", .green)
                        statTile("今日失败", session.dashboardOverview?.todayFail ?? 0, "xmark.circle", .red)
                        statTextTile("成功率", session.dashboardOverview?.successRateText ?? "—", "checkmark.seal", .teal)
                        statTextTile("平均耗时", session.dashboardOverview?.avgTimeText ?? "—", "clock", .orange)
                        statTile("已禁用任务", session.dashboardOverview?.disabled ?? 0, "stop", .gray)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } header: {
                    Label("概览", systemImage: "chart.pie")
                }

                // MARK: 运行中的任务
                Section {
                    if runningCrons.isEmpty {
                        Text("暂无运行中的任务")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runningCrons) { cron in
                            NavigationLink {
                                CronDetailView(cron: cron)
                                    .environmentObject(session)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cron.name).lineLimit(1)
                                        Text(cron.schedule)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Label("运行中的任务", systemImage: "play.circle")
                }

                // MARK: 最近执行
                Section {
                    if recentCrons.isEmpty {
                        Text("暂无执行记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentCrons) { cron in
                            NavigationLink {
                                CronDetailView(cron: cron)
                                    .environmentObject(session)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(qlBrandGreen)
                                    Text(cron.name).lineLimit(1)
                                }
                            }
                        }
                    }
                } header: {
                    Label("最近执行", systemImage: "clock")
                }

                // MARK: 面板信息
                Section {
                    LabeledContent("名称", value: session.connection.name)
                    LabeledContent("地址", value: session.connection.baseURLString)
                    if let v = session.panelInfo?.version ?? session.systemInfo?.version {
                        LabeledContent("版本", value: "v\(v)")
                    }
                    if let branch = session.panelInfo?.branch, !branch.isEmpty {
                        LabeledContent("分支", value: branch)
                    }
                    if let date = session.panelInfo?.publishDateText, !date.isEmpty {
                        LabeledContent("发布时间", value: date)
                    }
                } header: {
                    Label("面板信息", systemImage: "server.rack")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("仪表盘")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await session.loadAll() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable { await session.loadAll() }
            .task {
                if session.systemInfo == nil || session.panelInfo == nil
                    || session.dashboardSystem == nil || session.dashboardOverview == nil
                    || session.subscriptions.isEmpty {
                    await session.loadAll()
                }
            }
        }
    }

    // MARK: - 组件

    private func statusRow(_ icon: String, _ title: String, _ value: String?) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
    }

    private func statTile(_ title: String, _ value: Int, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                Text("\(value)")
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 文本数值瓦片（用于成功率、平均耗时等非整数指标）。
    private func statTextTile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var runningCrons: [CronTask] {
        session.crons.filter { $0.isRunning }
    }

    /// 最近执行：按最近执行时间倒序取前 5 个。
    private var recentCrons: [CronTask] {
        session.crons
            .filter { ($0.lastExecutionTime?.value ?? 0) > 0 || ($0.lastRunningTime?.value ?? 0) > 0 }
            .sorted { ($0.lastExecutionTime?.value ?? 0) > ($1.lastExecutionTime?.value ?? 0) }
            .prefix(5)
            .map { $0 }
    }
}
