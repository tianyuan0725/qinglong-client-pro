import SwiftUI

struct ScriptListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showCreate = false
    @State private var editorNode: FileNode? = nil
    @State private var renaming: FileNode? = nil
    @State private var renameText = ""
    @State private var confirmDelete: FileNode? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pathBar
                List {
                    ForEach(sortedNodes) { node in
                        row(for: node)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("脚本管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await session.loadFiles() }
            .refreshable { await session.loadFiles() }
            .sheet(isPresented: $showCreate) { ScriptCreateSheet() }
            .sheet(item: $editorNode) { node in
                ScriptEditorView(node: node)
            }
            .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("新名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("确定") {
                    if let node = renaming {
                        let newName = renameText.trimmingCharacters(in: .whitespaces)
                        if !newName.isEmpty { Task { _ = await session.renameFile(node: node, newName: newName) } }
                    }
                    renaming = nil
                }
            }
            .alert("删除确认", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("取消", role: .cancel) { confirmDelete = nil }
                Button("删除", role: .destructive) {
                    if let node = confirmDelete { Task { await session.removeFile(node: node) } }
                    confirmDelete = nil
                }
            } message: { Text(confirmDelete.map { "确定删除 \($0.title)？此操作不可恢复。" } ?? "") }
        }
    }

    private var sortedNodes: [FileNode] {
        session.fileNodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Button {
                if session.scriptPath.isEmpty { Task { await session.loadFiles() } }
                else { session.goUp() }
            } label: {
                Image(systemName: session.scriptPath.isEmpty ? "house" : "arrow.up")
            }
            .disabled(session.isBusy)
            Text(session.scriptPath.isEmpty ? "/ql/data/scripts" : "/ql/data/scripts/\(session.scriptPath)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private func row(for node: FileNode) -> some View {
        let actions = Group {
            Button(role: .destructive) { confirmDelete = node } label: { Label("删除", systemImage: "trash") }
            Button { renaming = node; renameText = node.title } label: { Label("重命名", systemImage: "pencil") }
        }
        if node.isDirectory {
            return AnyView(
                Button { session.enterDir(node) } label: {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.yellow)
                        Text(node.title)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .swipeActions { actions }
            )
        } else {
            return AnyView(
                NavigationLink {
                    ScriptEditorView(node: node)
                } label: {
                    HStack {
                        Image(systemName: "doc.fill").foregroundStyle(.blue)
                        Text(node.title)
                        Spacer()
                        if let s = node.sizeText {
                            Text(s).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions { actions }
            )
        }
    }
}

struct ScriptCreateSheet: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isDir = false
    @State private var content = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $isDir) {
                        Text("文件").tag(false)
                        Text("目录").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section("名称") {
                    TextField("例如 task.js / myfolder", text: $name)
                }
                if !isDir {
                    Section("内容（可留空）") {
                        TextEditor(text: $content)
                            .frame(minHeight: 160)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
            }
            .navigationTitle(isDir ? "新建目录" : "新建文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        Task {
                            let ok = isDir
                                ? await session.makeDir(path: session.scriptPath, dirname: n)
                                : await session.createFile(path: session.scriptPath, filename: n, content: content)
                            if ok { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || session.isBusy)
                }
            }
        }
    }
}
