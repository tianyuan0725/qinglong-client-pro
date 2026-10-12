import SwiftUI

struct EnvEditorView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) var dismiss
    var editing: EnvVar?

    @State private var name = ""
    @State private var value = ""
    @State private var remarks = ""
    @State private var saving = false
    @State private var showError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("变量") {
                    TextField("名称 (如 JD_COOKIE)", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("备注", text: $remarks)
                }
                Section("值") {
                    TextField("变量值", text: $value, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(4...12)
                }
            }
            .navigationTitle(editing == nil ? "新增变量" : "编辑变量")
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
        guard let e = editing else { return }
        name = e.name
        value = e.value
        remarks = e.remarks ?? ""
    }

    private func save() {
        guard !name.isEmpty else { showError = "请填写变量名称"; return }
        let env = EnvVar(
            _id: editing?._id,
            idField: editing?.idField,
            name: name,
            value: value,
            remarks: remarks.isEmpty ? nil : remarks,
            status: editing?.status,
            position: editing?.position
        )
        saving = true
        Task {
            let ok = await session.saveEnv(env, isNew: editing == nil)
            saving = false
            if ok { dismiss() }
            else { showError = session.lastError ?? "保存失败" }
        }
    }
}
