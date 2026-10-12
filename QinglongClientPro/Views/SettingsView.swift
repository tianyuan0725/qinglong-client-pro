import SwiftUI

/// 系统设置（面板级配置：标题 / 时区 / 清理 / 并发 / 代理 / 镜像）。
struct SystemSettingsView: View {
    @EnvironmentObject var session: PanelSession
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ConnectionStore
    @State private var showNotify = false

    private let schemes = ["system": "跟随系统", "light": "浅色", "dark": "深色"]

    private var info: SystemConfigInfo? { session.systemConfig?.info }

    var body: some View {
            List {
                Section("外观") {
                    Picker("主题", selection: $appState.colorSchemeRaw) {
                        ForEach(schemes.keys.sorted(by: { schemes[$0]! < schemes[$1]! }), id: \.self) { key in
                            Text(schemes[key]!).tag(key)
                        }
                    }
                }

                Section("当前面板") {
                    LabeledContent("名称", value: session.connection.name)
                    LabeledContent("地址", value: session.connection.baseURLString)
                    LabeledContent("认证", value: session.connection.authType.rawValue)
                    if let v = session.panelInfo?.version {
                        LabeledContent("面板版本", value: "v\(v)")
                    }
                    Button {
                        Task { await session.loadAll() }
                    } label: {
                        Label("刷新全部数据", systemImage: "arrow.clockwise")
                    }
                }

                Section("系统设置") {
                    configLink("面板标题", stringValue(info?.panelTitle)) {
                        await session.setPanelTitle($0)
                    }
                    configLink("时区", stringValue(info?.timezone ?? "Asia/Shanghai")) {
                        await session.setTimezone($0)
                    }
                    configLink("日志清理（天，0 关闭）", numberValue(info?.logRemoveFrequency), numeric: true) {
                        await session.setLogRemoveFrequency(Int($0))
                    }
                    configLink("命令并发数", numberValue(info?.cronConcurrency), numeric: true) {
                        await session.setCronConcurrency(Int($0))
                    }
                    configLink("依赖安装代理", stringValue(info?.dependenceProxy)) {
                        await session.setDependenceProxy($0)
                    }
                    configLink("Node 镜像", stringValue(info?.nodeMirror)) {
                        await session.setNodeMirror($0)
                    }
                    configLink("Python 镜像", stringValue(info?.pythonMirror)) {
                        await session.setPythonMirror($0)
                    }
                    configLink("Linux 镜像", stringValue(info?.linuxMirror)) {
                        await session.setLinuxMirror($0)
                    }
                }
                .onAppear { Task { await session.loadSystemConfig() } }

                Section("通知设置") {
                    Button {
                        showNotify = true
                    } label: {
                        Label("发送测试通知", systemImage: "bell")
                    }
                }

                Section("日志") {
                    NavigationLink {
                        SystemLogView()
                            .environmentObject(session)
                    } label: {
                        Label("系统日志", systemImage: "doc.text")
                    }
                }

                Section("面板管理") {
                    Button {
                        appState.selected = nil
                    } label: {
                        Label("返回面板列表 / 切换面板", systemImage: "list.bullet")
                    }
                    if !appState.defaultConnectionId.isEmpty {
                        Toggle("作为默认面板自动连接", isOn: Binding(
                            get: { appState.defaultConnectionId == session.connection.id },
                            set: { on in appState.defaultConnectionId = on ? session.connection.id : "" }
                        ))
                    } else {
                        Button {
                            appState.defaultConnectionId = session.connection.id
                        } label: {
                            Label("设为默认面板", systemImage: "star")
                        }
                    }
                }
            }
            .navigationTitle("系统设置")
            .sheet(isPresented: $showNotify) {
                NotifyTestView()
                    .environmentObject(session)
            }
    }

    private func configLink(_ title: String, _ value: String, numeric: Bool = false, save: @escaping (String) async -> Void) -> some View {
        NavigationLink {
            SystemConfigEditView(title: title, initial: value, numeric: numeric, onSave: save)
                .environmentObject(session)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(value.isEmpty ? "未设置" : value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func stringValue(_ s: String?) -> String { (s?.isEmpty ?? true) ? "" : s! }
    private func numberValue(_ n: Int?) -> String { n.map(String.init) ?? "" }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

/// Generic single-value editor for system config fields.
struct SystemConfigEditView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initial: String
    let numeric: Bool
    let onSave: (String) async -> Void

    @State private var text: String = ""
    @State private var done = false

    var body: some View {
        Form {
            Section(title) {
                TextField("留空表示关闭 / 默认", text: $text)
                    .keyboardType(numeric ? .numberPad : .default)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        await onSave(text.trimmingCharacters(in: .whitespaces))
                        done = true
                        dismiss()
                    }
                }
                .disabled(session.isBusy)
            }
        }
        .onAppear { text = initial }
    }
}

struct NotifyTestView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    @State private var title = "青龙客户端 Pro"
    @State private var content = "这是一条来自青龙客户端 Pro 的测试通知"
    @State private var sent = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") { TextField("标题", text: $title) }
                Section("内容") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("测试通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        Task {
                            let ok = await session.sendNotify(title: title, content: content)
                            if ok { sent = true; dismiss() } else { failed = true }
                        }
                    }
                    .disabled(session.isBusy)
                }
            }
            .alert("发送结果", isPresented: Binding(get: { sent || failed }, set: { if !$0 { sent = false; failed = false } })) {
                Button("好") { }
            } message: { Text(failed ? "发送失败，请检查面板通知渠道配置。" : "已发送，请查看你的通知渠道。") }
        }
    }
}

struct SystemLogView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        Group {
            if session.systemLogText.isEmpty {
                VStack(spacing: 12) {
                    Text("暂无日志内容").foregroundStyle(.secondary)
                    Button("加载日志") { Task { await session.loadSystemLog() } }
                }
            } else {
                ScrollView {
                    Text(session.systemLogText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .navigationTitle("系统日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await session.loadSystemLog() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { if session.systemLogText.isEmpty { await session.loadSystemLog() } }
    }
}
