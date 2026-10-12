import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let sys = session.systemInfo {
                        systemCard(sys)
                    } else {
                        Text("暂无系统信息")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    statsGrid

                    runningSection
                }
                .padding()
            }
            .navigationTitle("概览")
            .refreshable { await session.loadAll() }
        }
    }

    // MARK: - System card

    private func systemCard(_ sys: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(Color.accentColor)
                Text("系统信息")
                    .font(.headline)
                Spacer()
                if let v = sys.version {
                    StatusPill(text: "v\(v)", color: .blue)
                }
            }
            Divider()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                if let cpu = sys.cpuUsageText {
                    GridRow {
                        Text("CPU").foregroundStyle(.secondary)
                        Text(cpu)
                    }
                }
                if let mem = sys.memoryUsageText {
                    GridRow {
                        Text("内存").foregroundStyle(.secondary)
                        Text(mem + (sys.memoryGB.map { " / \($0)" } ?? ""))
                    }
                }
                if let disk = sys.diskUsageText {
                    GridRow {
                        Text("磁盘").foregroundStyle(.secondary)
                        Text(disk)
                    }
                }
                if let up = sys.uptimeText {
                    GridRow {
                        Text("运行").foregroundStyle(.secondary)
                        Text(up)
                    }
                }
                if let user = sys.currentActiveUser {
                    GridRow {
                        Text("用户").foregroundStyle(.secondary)
                        Text(user)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "任务总数", value: "\(session.cronCount)", color: .blue, icon: "timer")
            StatTile(title: "运行中", value: "\(session.runningCount)", color: .green, icon: "play.circle")
            StatTile(title: "已禁用任务", value: "\(session.disabledCronCount)", color: .orange, icon: "pause.circle")
            StatTile(title: "环境变量", value: "\(session.envCount)", color: .purple, icon: "key")
        }
    }

    // MARK: - Running tasks

    private var runningSection: some View {
        let running = session.crons.filter { $0.isRunning }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("运行中任务")
                    .font(.headline)
                Spacer()
                Text("\(running.count)")
                    .foregroundStyle(.secondary)
            }
            if running.isEmpty {
                Text("当前没有正在运行的任务")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(running) { cron in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cron.name).font(.subheadline.weight(.medium))
                            Text(cron.schedule).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await session.stopCron([cron.id]) }
                        } label: {
                            Image(systemName: "stop.circle")
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Spacer()
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
