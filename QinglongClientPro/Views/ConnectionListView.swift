import SwiftUI

struct ConnectionListView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var appState: AppState
    /// 以「账号排序」模式打开时自动进入编辑态（拖动排序）。
    var startInSortMode: Bool = false
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
                            // 切换账号：RootView 会按 conn.id 重建 PanelTabView
                            // （新 PanelSession 重新登录/恢复 token）。
                            // dismiss()：从「账号排序」sheet 进入时立即收起，
                            // 避免旧面板内容一闪（被 push 时为 no-op）。
                            appState.selected = conn
                            dismiss()
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
                            } label: { Label("编辑", systemImage: "pencil") }
                                .tint(.blue)
                            Button(role: .destructive) {
                                store.delete(conn)
                                if appState.defaultConnectionId == conn.id {
                                    appState.defaultConnectionId = ""
                                }
                                if appState.lastConnectionId == conn.id {
                                    appState.lastConnectionId = ""
                                }
                                if appState.selected?.id == conn.id {
                                    appState.selected = nil
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
                    Text("关闭时将自动恢复上次使用的面板；仅配置一个面板时始终直接进入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        editing = Connection(id: UUID().uuidString, name: "", baseURLString: "",
                            authType: .user, username: "", password: "", clientID: "", clientSecret: "")
                    } label: { Image(systemName: "plus") }
                }
            }
.sheet(item: $editing) { conn in
    ConnectionEditorView(editing: conn)
        .environmentObject(store)
            }
        }
    }
}

struct ConnectionEditorView: View {
    @EnvironmentObject var store: ConnectionStore
    @Environment(\.dismiss) var dismiss
    /// 被编辑的面板；由 .sheet(item:) 驱动，恒非 nil。
    /// 新建时上层传入空 Connection（新 UUID），保存即新增；
    /// 编辑时传入列表中已有的 Connection，保存按同 id 覆盖更新。
    var editing: Connection

    @State private var name: String
    @State private var baseURLString: String
    @State private var authType: AuthType
    @State private var username: String
    @State private var password: String
    @State private var clientID: String
    @State private var clientSecret: String
    @State private var showError: String?

    /// 用传入连接预填各字段（init 赋值，杜绝 sheet 时序问题
    /// 导致「编辑打开却是空的、保存变成新增账号」）。
    init(editing: Connection) {
        self.editing = editing
        _name = State(initialValue: editing.name)
        _baseURLString = State(initialValue: editing.baseURLString)
        _authType = State(initialValue: editing.authType)
        _username = State(initialValue: editing.username)
        _password = State(initialValue: editing.password)
        _clientID = State(initialValue: editing.clientID)
        _clientSecret = State(initialValue: editing.clientSecret)
    }

    /// 是否编辑已有面板（决定标题；保存始终按 id upsert）。
    private var isExisting: Bool {
        store.connections.contains { $0.id == editing.id }
    }

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
                         : "登录面板到「系统设置 → 应用设置」添加应用，获取 Client ID / Secret (POST /api/apps/token)。开放 API 需在应用中授予相应权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isExisting ? "编辑面板" : "新增面板")
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
    }

    private func save() {
        guard !name.isEmpty else { showError = "请填写面板名称"; return }
        guard !baseURLString.trimmingCharacters(in: .whitespaces).isEmpty,
              (URL(string: baseURLString) != nil || baseURLString.contains(".") || baseURLString.lowercased().contains("localhost")) else {
            showError = "请填写有效的面板地址"; return
        }
        // 同一 id 覆盖保存（Keychain upsert）：编辑不产生重复账号。
        let conn = Connection(
            id: editing.id,
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