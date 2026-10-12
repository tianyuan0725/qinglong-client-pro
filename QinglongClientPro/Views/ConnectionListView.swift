import SwiftUI

struct ConnectionListView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var appState: AppState
    /// 以「账号排序」模式打开时自动进入编辑态（拖动排序）。
    var startInSortMode: Bool = false
    @State private var showEditor = false
    @State private var editing: Connection?
    @State private var editMode: EditMode = .inactive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.connections.isEmpty {
                        Text("还没有添加任何青龙面板，点右上角 + 添加。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.connections) { conn in
                        Button {
                            appState.selected = conn
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "server.rack")
                                    .foregroundStyle(qlBrandGreen)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conn.name).font(.headline)
                                    Text(conn.baseURLString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button {
                                editing = conn
                                showEditor = true
                            } label: { Label("编辑", systemImage: "pencil") }
                                .tint(.blue)
                            Button(role: .destructive) {
                                store.delete(conn)
                                if appState.defaultConnectionId == conn.id {
                                    appState.defaultConnectionId = ""
                                }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                    .onMove(perform: store.move)
                } header: { Text("已配置的面板（拖动可排序）") }

                Section {
                    Toggle("启动时自动连接默认面板", isOn: Binding(
                        get: { !appState.defaultConnectionId.isEmpty },
                        set: { on in
                            appState.defaultConnectionId = on ? (store.connections.first?.id ?? "") : ""
                        }
                    ))
                    if !appState.defaultConnectionId.isEmpty {
                        Picker("默认面板", selection: $appState.defaultConnectionId) {
                            ForEach(store.connections) { conn in
                                Text(conn.name).tag(conn.id)
                            }
                        }
                    }
                } header: { Text("通用") } footer: {
                    Text("面板地址、账号与密码均仅保存在本机 Keychain，不会上传任何服务器。")
                        .font(.caption)
                }
            }
            .navigationTitle("青龙客户端 Pro")
            .environment(\.editMode, $editMode)
            .onAppear {
                if startInSortMode { editMode = .active }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if startInSortMode {
                        Button("完成") { dismiss() }
                    } else {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = nil
                        showEditor = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showEditor) {
                ConnectionEditorView(editing: editing)
                    .environmentObject(store)
            }
        }
    }
}

struct ConnectionEditorView: View {
    @EnvironmentObject var store: ConnectionStore
    @Environment(\.dismiss) var dismiss
    var editing: Connection?

    @State private var name = ""
    @State private var baseURLString = ""
    @State private var authType: AuthType = .user
    @State private var username = ""
    @State private var password = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("面板名称", text: $name)
                    TextField("面板地址 (含端口，如 1.2.3.4:5700)", text: $baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("认证方式") {
                    Picker("类型", selection: $authType) {
                        ForEach(AuthType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if authType == .user {
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码", text: $password)
                    } else {
                        TextField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Client Secret", text: $clientSecret)
                    }
                    Text(authType == .user
                         ? "使用面板后台账号密码登录 (POST /api/user/login)。"
                         : "登录面板后到「系统设置 → 应用设置」添加应用，获取 Client ID / Secret (POST /api/apps/token)。开放 API 需在应用中授予相应权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(editing == nil ? "新增面板" : "编辑面板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("无法保存", isPresented: Binding(get: { showError != nil }, set: { if !$0 { showError = nil } })) {
                Button("确定") { showError = nil }
            } message: { Text(showError ?? "") }
        }
        .onAppear(perform: loadIfEditing)
    }

    private func loadIfEditing() {
        guard let c = editing else { return }
        name = c.name
        baseURLString = c.baseURLString
        authType = c.authType
        username = c.username
        password = c.password
        clientID = c.clientID
        clientSecret = c.clientSecret
    }

    private func save() {
        guard !name.isEmpty else { showError = "请填写面板名称"; return }
        guard !baseURLString.trimmingCharacters(in: .whitespaces).isEmpty,
              (URL(string: baseURLString) != nil || baseURLString.contains(".") || baseURLString.lowercased().contains("localhost")) else {
            showError = "请填写有效的面板地址"; return
        }
        let conn = Connection(
            id: editing?.id ?? UUID().uuidString,
            name: name,
            baseURLString: baseURLString,
            authType: authType,
            username: username,
            password: password,
            clientID: clientID,
            clientSecret: clientSecret
        )
        store.save(conn)
        dismiss()
    }
}
