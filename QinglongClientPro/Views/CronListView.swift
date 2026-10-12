import SwiftUI

struct CronListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var search = ""
    @State private var showEditor = false
    @State private var editing: CronTask?

    private var filtered: [CronTask] {
        let list = session.crons
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
                ForEach(filtered) { cron in
                    row(cron)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await session.deleteCron([cron.id]) }
                            } label: { Label("删除", systemImage: "trash") }
                            Button {
                                Task { await session.runCron([cron.id]) }
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
            .navigationTitle("定时任务")
            .searchable(text: $search, prompt: "搜索名称 / 命令 / 周期")
            .refreshable { await session.loadCrons() }
            .overlay { if filtered.isEmpty && !session.crons.isEmpty {
                emptyHint("没有匹配的任务")
            } else if session.crons.isEmpty {
                emptyHint("暂无任务，点右上角 + 新增")
            } }
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
        }
    }

    private func row(_ cron: CronTask) -> some View {
        NavigationLink {
            CronDetailView(cron: cron)
                .environmentObject(session)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cron.isRunning ? "arrow.triangle.2.circlepath" : "timer")
                    .foregroundStyle(cron.isRunning ? Color.green : Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cron.name).font(.headline).lineLimit(1)
                    Text(cron.schedule).font(.caption).foregroundStyle(.secondary)
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
            .padding(.vertical, 2)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
