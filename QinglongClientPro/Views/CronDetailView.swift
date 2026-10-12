import SwiftUI
import UIKit

struct CronDetailView: View {
    @EnvironmentObject var session: PanelSession
    let cron: CronTask

    @State private var logText = "（点击右上角刷新日志）"
    @State private var logLoading = false
    @State private var autoRefresh = false
    @State private var showEditor = false

    private var live: CronTask? {
        session.crons.first { $0.id == cron.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard
                actionButtons
                logCard
            }
            .padding()
        }
        .navigationTitle(live?.name ?? cron.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditor = true
                } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showEditor) {
            CronEditorView(editing: live ?? cron)
                .environmentObject(session)
        }
        .task { await loadLog() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            if autoRefresh, live?.isRunning == true {
                Task { await loadLog() }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(text: live?.statusLabel ?? cron.statusLabel,
                           color: (live?.isRunning ?? cron.isRunning) ? .green : ((live?.isEnabled ?? cron.isEnabled) ? .blue : .gray))
                Spacer()
                if let running = live?.isRunning, running {
                    StatusPill(text: "自动刷新中", color: .green)
                }
            }
            row("名称", live?.name ?? cron.name)
            row("周期", live?.schedule ?? cron.schedule)
            if let last = live?.lastExecutionText ?? cron.lastExecutionText {
                row("上次执行", last)
            }
            if !cron.labels.isEmpty {
                row("标签", cron.labels.joined(separator: " · "))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("命令").foregroundStyle(.secondary).font(.caption)
                Text(live?.command ?? cron.command)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .font(.subheadline)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            action("运行", systemImage: "play.fill", .green) {
                Task { await session.runCron([cron.id]) }
            }
            action("停止", systemImage: "stop.fill", .red) {
                Task { await session.stopCron([cron.id]) }
            }
            action(live?.isEnabled ?? cron.isEnabled ? "禁用" : "启用",
                   systemImage: (live?.isEnabled ?? cron.isEnabled) ? "pause.fill" : "play.fill",
                   .orange) {
                Task { await session.toggleCron(cron) }
            }
            action("置顶", systemImage: "pin.fill", .blue) {
                Task { await session.pinCron(cron) }
            }
        }
    }

    private func action(_ title: String, systemImage: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
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
                Text("执行日志")
                    .font(.headline)
                Spacer()
                Toggle("自动刷新", isOn: $autoRefresh)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                Button {
                    Task { await loadLog() }
                } label: { Image(systemName: "arrow.clockwise") }
                Button {
                    UIPasteboard.general.string = logText
                } label: { Image(systemName: "doc.on.doc") }
            }
            if logLoading {
                ProgressView().frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                ScrollView {
                    Text(logText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 360)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func loadLog() async {
        logLoading = true
        defer { logLoading = false }
        logText = await session.cronLog(id: cron.id)
    }
}
