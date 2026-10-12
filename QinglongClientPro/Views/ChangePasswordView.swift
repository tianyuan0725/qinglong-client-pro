import SwiftUI

/// 修改密码 / 用户名（PUT /api/user，两个字段均必填）。
struct ChangePasswordView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var done = false

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty && password == confirm
    }

    var body: some View {
            Form {
                Section {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("新密码", text: $password)
                    SecureField("确认新密码", text: $confirm)
                } header: {
                    Text("账号信息")
                } footer: {
                    Text("用户名与密码会同时更新（PUT /api/user）。若修改了密码，请同步更新本机保存的面板凭据。")
                        .font(.caption)
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(!canSave || session.isBusy)
                }
            }
            .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("确定") { error = nil }
            } message: { Text(error ?? "") }
            .alert("已修改", isPresented: $done) {
                Button("好") { dismiss() }
            } message: { Text("账号信息已更新。") }
            .onAppear {
                if username.isEmpty {
                    username = session.currentUser?.username ?? session.connection.username
                }
            }
    }

    private func save() async {
        guard password == confirm else { error = "两次输入的密码不一致"; return }
        let ok = await session.changeCredentials(username: username, password: password)
        if ok { done = true }
    }
}
