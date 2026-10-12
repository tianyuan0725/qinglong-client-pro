import SwiftUI
import UIKit

struct AppListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showEditor = false
    @State private var editing: AppItem? = nil
    @State private var confirmDelete: [AppItem]? = nil
    @State private var newSecret = ""
    @State private var showSecret = false

    var body: some View {
        NavigationStack {
            List {
                if session.apps.isEmpty {
                    Text("暂无应用，点击右上角添加")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(session.apps) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(app.name.isEmpty ? "（未命名）" : app.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button { Task { newSecret = await session.resetAppSecret(id: app._id); showSecret = !newSecret.isEmpty } }
                            label: { Label("重置密钥", systemImage: "key.rotation") }
                                .font(.caption)
                                .tint(.orange)
                        }
                        HStack(spacing: 6) {
                            Text("ID: \(app.clientID.isEmpty ? "—" : app.clientID)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text("权限：\(app.scopesText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { confirmDelete = [app] } label: { Label("删除", systemImage: "trash") }
                        Button { editing = app } label: { Label("编辑", systemImage: "pencil") }
                            .tint(.indigo)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("应用设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await session.loadApps() }
            .refreshable { await session.loadApps() }
            .sheet(isPresented: $showEditor) { AppEditorView(editing: nil) }
            .sheet(item: $editing) { app in AppEditorView(editing: app) }
            .alert("删除应用", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("取消", role: .cancel) { confirmDelete = nil }
                Button("删除", role: .destructive) {
                    if let arr = confirmDelete { Task { await session.deleteApps(ids: arr.map { $0._id }) } }
                    confirmDelete = nil
                }
            } message: { Text(confirmDelete.map { "确定删除应用 \($0.first?.name ?? "")？" } ?? "") }
            .alert("新的 Client Secret", isPresented: $showSecret) {
                Button("复制") { UIPasteboard.general.string = newSecret }
                Button("好", role: .cancel) { }
            } message: { Text("请立即复制保存，密钥仅显示一次：\n\(newSecret)") }
        }
    }
}

struct AppEditorView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let editing: AppItem?

    @State private var name = ""
    @State private var scopesText = ""

    init(editing: AppItem?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _scopesText = State(initialValue: editing?.scopes.joined(separator: ", ") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("应用名称") {
                    TextField("可选，留空为 system", text: $name)
                }
                Section("权限范围 (Scopes)") {
                    TextField("逗号分隔，如 cron:read,env:read", text: $scopesText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("常用：cron:read / cron:write / env:read / env:write / log:read")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(editing == nil ? "新建应用" : "编辑应用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let scopes = scopesText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        Task {
                            let ok: Bool
                            if let app = editing {
                                var a = app; a.name = name.trimmingCharacters(in: .whitespaces); a.scopes = scopes
                                ok = await session.updateApp(a)
                            } else {
                                ok = await session.createApp(name: name.trimmingCharacters(in: .whitespaces), scopes: scopes)
                            }
                            if ok { dismiss() }
                        }
                    }
                    .disabled(session.isBusy)
                }
            }
        }
    }
}
