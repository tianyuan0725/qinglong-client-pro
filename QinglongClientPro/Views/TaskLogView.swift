import SwiftUI

/// 任务日志：选择任务并查看其运行日志（GET /api/crons/:id/log）。
struct TaskLogView: View {
    @EnvironmentObject var session: PanelSession
    @State private var selectedId: String?
    @State private var logText = ""
    @State private var loading = false

    private var selected: CronTask? { session.crons.first { $0.id == selectedId } }

    var body: some View {
        List {
            Section("选择任务") {
                ForEach(session.crons) { cron in
                    Button {
                        selectedId = cron.id
                        Task { await loadLog() }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cron.name).font(.body.weight(.medium)).lineLimit(1)
                                Text(cron.schedule).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if selectedId == cron.id {
                                Image(systemName: "checkmark").foregroundStyle(qlBrandGreen)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            if selected != nil {
                Section {
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("加载中…").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(logText.isEmpty ? "（暂无日志，任务可能还未运行过）" : logText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } header: {
                    HStack {
                        Text("运行日志")
                        Spacer()
                        Button { Task { await loadLog() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(loading)
                    }
                }
            }
        }
        .navigationTitle("任务日志")
        .navigationBarTitleDisplayMode(.inline)
        .task { if session.crons.isEmpty { await session.loadCrons() } }
    }

    private func loadLog() async {
        guard let id = selectedId else { return }
        loading = true
        defer { loading = false }
        logText = await session.cronLog(id: id)
    }
}
