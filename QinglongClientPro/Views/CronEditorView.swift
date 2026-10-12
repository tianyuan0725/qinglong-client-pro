import SwiftUI

struct CronEditorView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) var dismiss
    var editing: CronTask?

    @State private var name = ""
    @State private var command = ""
    @State private var schedule = ""
    @State private var labelsText = ""
    @State private var saving = false
    @State private var showError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("名称", text: $name)
                    TextField("执行周期 (如 0 0 * * *)", text: $schedule)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("标签 (用逗号分隔)", text: $labelsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("命令") {
                    TextField("command / script path", text: $command, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(4...10)
                }
                if editing != nil {
                    Section {
                        Text("保存后将更新该任务。禁用/启用与运行请在任务列表操作。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增任务" : "编辑任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        if saving { ProgressView() } else { Text("保存") }
                    }
                    .disabled(saving)
                }
            }
            .alert("保存失败", isPresented: Binding(get: { showError != nil }, set: { if !$0 { showError = nil } })) {
                Button("确定") { showError = nil }
            } message: { Text(showError ?? "") }
        }
        .onAppear(perform: loadIfEditing)
    }

    private func loadIfEditing() {
        guard let c = editing else { return }
        name = c.name
        command = c.command
        schedule = c.schedule
        labelsText = c.labels.joined(separator: ", ")
    }

    private func save() {
        guard !name.isEmpty else { showError = "请填写任务名称"; return }
        guard !command.isEmpty else { showError = "请填写命令"; return }
        let labels = labelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let cron = CronTask(
            _id: editing?._id,
            idField: editing?.idField,
            name: name,
            command: command,
            schedule: schedule,
            labels: labels,
            isDisabled: editing?.isDisabled,
            enabled: editing?.enabled,
            status: editing?.status,
            pid: editing?.pid,
            isSystem: editing?.isSystem,
            isPinned: editing?.isPinned,
            lastRunningTime: editing?.lastRunningTime,
            lastExecutionTime: editing?.lastExecutionTime,
            logPath: editing?.logPath,
            createdAt: editing?.createdAt
        )
        saving = true
        Task {
            let ok = await session.saveCron(cron, isNew: editing == nil)
            saving = false
            if ok { dismiss() }
            else { showError = session.lastError ?? "保存失败" }
        }
    }
}
