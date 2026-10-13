import SwiftUI

/// 仪表盘 —— 仿青龙面板网页版仪表盘：系统状态（CPU/内存/磁盘）、
/// 任务/变量/订阅统计、运行中任务、最近执行任务、面板信息。
struct DashboardView: View {
    @EnvironmentObject var session: PanelSession
    @State private var todaySheet: TodaySheetMode? = nil

    var body: some View {
        NavigationStack {
            List {
                // MARK: 系统状态（紧凑 2 列网格）
                Section {
                    if let sys = session.dashboardSystem {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            statusCell("memorychip", "内存使用率", sys.memoryPercentText)
                            statusCell("internaldrive", "内存", sys.memoryBytesText)
                            statusCell("clock", "系统运行", sys.uptimeText)
                            statusCell("square.stack.3d.up", "堆内存", sys.heapText)
                            statusCell("waveform.path.ecg", "负载(1m)", sys.loadText)
                            statusCell("cpu", "CPU", sys.cpuText)
                        }
                        .padding(.vertical, 2)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowBackground(Color.clear)
                    } else if session.systemInfo != nil {
                        Text("当前面板版本较低（低于 v2.23），暂不支持读取系统资源")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("正在读取系统状态…")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("系统状态", systemImage: "gauge.medium")
                        .font(.footnote)
                }

                // MARK: 统计概览
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        statTile("定时任务", session.cronCount, "list.bullet.rectangle", .blue)
                        statTile("运行中", session.runningCount, "arrow.triangle.2.circlepath", .green)
                        statTile("环境变量", session.envCount, "key", .purple)
                        statTile("订阅", session.subscriptions.count, "square.and.arrow.down", .orange)
                        todayTile("今日执行", session.dashboardOverview?.todayRuns ?? 0, "bolt", .green, .all)
                        todayTile("今日成功", session.dashboardOverview?.todaySuccess ?? 0, "checkmark.circle", .green, .success)
                        todayTile("今日失败", session.dashboardOverview?.todayFail ?? 0, "xmark.circle", .red, .fail)
                        statTextTile("成功率", session.dashboardOverview?.successRateText ?? "—", "checkmark.seal", .teal)
                        statTextTile("平均耗时", session.dashboardOverview?.avgTimeText ?? "—", "clock", .orange)
                        statTile("已禁用任务", session.dashboardOverview?.disabled ?? 0, "stop", .gray)
                    }
                    .padding(.vertical, 2)
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowBackground(Color.clear)
                } header: {
                    Label("概览", systemImage: "chart.pie")
                        .font(.footnote)
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
                        .font(.footnote)
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
                        .font(.footnote)
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
                        .font(.footnote)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("仪表盘")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(item: $todaySheet) { mode in
                TodayTasksSheet(title: mode.title, tasks: todayTasks(for: mode))
                    .environmentObject(session)
            }
        }
    }

    // MARK: - 今日执行任务弹窗

    enum TodaySheetMode: Identifiable {
        case all, success, fail
        var id: String { "\(self)" }
        var title: String {
            switch self {
            case .all: return "今日执行的任务"
            case .success: return "今日成功执行的任务"
            case .fail: return "今日失败 / 被禁用的任务"
            }
        }
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func ranToday(_ cron: CronTask) -> Bool {
        guard let t = cron.lastExecutionTime?.value, t > 0 else { return false }
        let ts = t > 1_000_000_000_000 ? TimeInterval(t) / 1000 : TimeInterval(t)
        return Date(timeIntervalSince1970: ts) >= todayStart
    }

    private func todayTasks(for mode: TodaySheetMode) -> [CronTask] {
        let list = session.crons.filter { ranToday($0) }
        switch mode {
        case .all: return list
        case .success: return list.filter { $0.status?.value != 2 }
        case .fail: return list.filter { $0.status?.value == 2 }
        }
    }

    private func todayTile(_ title: String, _ value: Int, _ icon: String, _ color: Color, _ mode: TodaySheetMode) -> some View {
        Button {
            todaySheet = mode
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Spacer(minLength: 2)
                    Text("\(value)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 组件

    /// 紧凑状态单元：图标 + 标题 + 数值横向排布，用于系统状态的 2 列网格。
    /// 系统状态单元：独立小卡，图标 + 标签在上、大数值在下。
    private func statusCell(_ icon: String, _ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(qlBrandGreen)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statTile(_ title: String, _ value: Int, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                Text("\(value)")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 文本数值瓦片（用于成功率、平均耗时等非整数指标）。
    private func statTextTile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
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

/// 今日执行任务弹窗：列出今天有执行记录的任务（含最后执行时间与当前状态）。
/// 说明：面板 API 只提供「今日成功/失败」的计数，不含逐任务成败明细，
/// 此处按「当前是否禁用（status=2）」近似归类，点单个任务可看其运行日志。
struct TodayTasksSheet: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let title: String
    let tasks: [CronTask]

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("今日暂无相关执行记录")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(tasks) { cron in
                            NavigationLink {
                                CronDetailView(cron: cron)
                                    .environmentObject(session)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(cron.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                        if let t = cron.lastExecutionText {
                                            Text("最后执行 \(t)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    StatusPill(text: cron.statusLabel,
                                               color: cron.isRunning ? .green : (cron.isEnabled ? .blue : .gray))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
