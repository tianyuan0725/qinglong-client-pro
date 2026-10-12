import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    panelCard

                    statsGrid

                    runningSection
                }
                .padding()
            }
            .navigationTitle("概览")
            .refreshable { await session.loadAll() }
        }
    }

    // MARK: - Panel card

    private var panelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(Color.accentColor)
                Text("面板信息")
                    .font(.headline)
                Spacer()
                if let v = session.panelInfo?.version ?? session.systemInfo?.version {
                    StatusPill(text: "v\(v)", color: .blue)
                }
            }
            Divider()
            if let pi = session.panelInfo {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    if let b = pi.branch {
                        GridRow {
                            Text("分支").foregroundStyle(.secondary)
                            Text(b)
                        }
                    }
                    if let t = pi.publishDateText {
                        GridRow {
                            Text("发布").foregroundStyle(.secondary)
                            Text(t)
                        }
                    }
                    if let link = pi.changeLogLink, let url = URL(string: link) {
                        GridRow {
                            Text("更新").foregroundStyle(.secondary)
                            Link("查看日志", destination: url)
                        }
                    }
                }
                .font(.subheadline)
            } else {
                Text("暂无面板信息")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "任务", value: "\(session.cronCount)", color: .blue, icon: "timer")
            StatTile(title: "运行中", value: "\(session.runningCount)", color: .green, icon: "play.circle")
            StatTile(title: "变量", value: "\(session.envCount)", color: .purple, icon: "key")
            StatTile(title: "订阅", value: "\(session.subscriptions.count)", color: .orange, icon: "arrow.down.circle")
            StatTile(title: "依赖", value: "\(session.dependencies.count)", color: .teal, icon: "square.stack.3d.up")
            StatTile(title: "应用", value: "\(session.apps.count)", color: .pink, icon: "app.badge")
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
