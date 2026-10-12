import SwiftUI

struct ScriptListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showCreate = false
    @State private var editorNode: FileNode? = nil
    @State private var renaming: FileNode? = nil
    @State private var renameText = ""
    @State private var confirmDelete: FileNode? = nil
    // 多选模式
    @State private var selectMode = false
    @State private var selectedIds: Set<String> = []
    @State private var confirmBatchDelete = false
    // 下载 / 分享
    @State private var downloadNode: FileNode? = nil
    @State private var shareItem: ShareItem? = nil
    @State private var downloadBusy = false
    // 添加到任务
    @State private var addToTaskNode: FileNode? = nil

    var body: some View {
            VStack(spacing: 0) {
                pathBar
                if selectMode {
                    batchBar
                }
                List(selection: $selectedIds) {
                    ForEach(sortedNodes) { node in
                        row(for: node)
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, selectMode ? .constant(.active) : .constant(.inactive))
            }
            .navigationTitle("脚本管理")
            .toolbar { toolbarContent }
            .task { await session.loadFiles() }
            .refreshable { await session.loadFiles() }
            .sheet(isPresented: $showCreate) { ScriptCreateSheet() }
            .sheet(item: $editorNode) { node in
                NavigationStack { ScriptEditorView(node: node) }
            }
            .sheet(item: $downloadNode) { node in
                ScriptDownloadSheet(node: node) { item in
                    shareItem = item
                }
            }
            .sheet(item: $addToTaskNode) { node in
                ScriptAddToTaskSheet(node: node)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
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
            .alert("批量删除确认", isPresented: $confirmBatchDelete) {
                Button("取消", role: .cancel) { }
                Button("删除 \(selectedIds.count) 项", role: .destructive) {
                    let nodes = sortedNodes.filter { selectedIds.contains($0.id) }
                    Task { await session.removeFiles(nodes: nodes) }
                    selectedIds = []
                }
            } message: { Text("批量删除不可恢复，确定继续？") }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(selectMode ? "退出多选" : "多选") {
                withAnimation {
                    selectMode.toggle()
                    if !selectMode { selectedIds = [] }
                }
            }
            .font(.subheadline)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showCreate = true } label: { Image(systemName: "plus") }
        }
    }

    // MARK: - 批量操作栏（参考 App：全选/全不选/批量删除/批量运行）

    private var batchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button("全选") {
                    selectedIds = Set(sortedNodes.map(\.id))
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                Button("全不选") {
                    selectedIds = []
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                Button {
                    Task {
                        let nodes = sortedNodes.filter { selectedIds.contains($0.id) }
                        _ = await session.runFiles(nodes: nodes)
                        selectedIds = []
                    }
                } label: {
                    Label("批量运行", systemImage: "play.circle")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .disabled(selectedIds.isEmpty || session.isBusy)
                Button(role: .destructive) {
                    confirmBatchDelete = true
                } label: {
                    Label("批量删除", systemImage: "trash")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .disabled(selectedIds.isEmpty || session.isBusy)
            }
            .foregroundStyle(selectedIds.isEmpty ? .secondary : qlBrandGreen)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)

            if !selectedIds.isEmpty {
                Text("已选 \(selectedIds.count) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
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
            let rowContent = HStack {
                Image(systemName: "doc.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                    if let s = node.sizeText {
                        Text(s).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if selectMode {
                    Image(systemName: selectedIds.contains(node.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIds.contains(node.id) ? qlBrandGreen : .secondary)
                }
            }
            return AnyView(
                Group {
                    if selectMode {
                        Button {
                            toggleSelection(node)
                        } label: { rowContent }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            ScriptEditorView(node: node)
                        } label: { rowContent }
                        .swipeActions { actions }
                        .contextMenu {
                            Button {
                                downloadNode = node
                            } label: { Label("下载脚本", systemImage: "arrow.down.circle") }
                            Button {
                                addToTaskNode = node
                            } label: { Label("添加到任务", systemImage: "plus.circle") }
                        }
                    }
                }
            )
        }
    }

    private func toggleSelection(_ node: FileNode) {
        if selectedIds.contains(node.id) {
            selectedIds.remove(node.id)
        } else {
            selectedIds.insert(node.id)
        }
    }
}

// MARK: - 下载脚本（保存到「文件」/ 分享）

struct ScriptDownloadSheet: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let node: FileNode
    /// 下载完成后回调（供外层弹出分享面板）。
    var onDownloaded: (ShareItem) -> Void

    @State private var busy = true
    @State private var error: String?
    @State private var savedPath: String?

    var body: some View {
        NavigationStack {
            Group {
                if busy {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("正在从面板下载 \(node.title)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(QLPalette.red)
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("重试") { Task { await download() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(qlBrandGreen)
                        Text("已下载到本机")
                            .font(.headline)
                        if let savedPath {
                            Text(savedPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                        }
                        QLSecondaryButton(title: "分享 / 存储到「文件」", icon: "square.and.arrow.up") {
                            if let savedPath, let url = URL(string: "file://" + savedPath) {
                                onDownloaded(ShareItem(url: url))
                            }
                            dismiss()
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("下载脚本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .task { await download() }
    }

    private func download() async {
        busy = true
        error = nil
        defer { busy = false }
        guard let data = await session.downloadScriptData(path: node.parent, filename: node.title) else {
            error = session.lastError ?? "下载失败"
            return
        }
        // 保存到 App 沙盒 Documents（可在「文件」App 中浏览）
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(node.title)
        do {
            try data.write(to: dest, options: .atomic)
            savedPath = dest.path
        } catch {
            self.error = "保存失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 从脚本添加到任务

struct ScriptAddToTaskSheet: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let node: FileNode

    @State private var command = ""
    @State private var schedule = "0 9 * * *"
    @State private var name = ""
    @State private var saved = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("任务名称") {
                    TextField("留空则使用脚本名", text: $name)
                }
                Section("执行命令") {
                    TextField("命令", text: $command)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                }
                Section("Cron 表达式") {
                    TextField("如 0 9 * * *", text: $schedule)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("添加到任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { Task { await save() } }
                        .disabled(session.isBusy || command.isEmpty || schedule.isEmpty)
                }
            }
            .alert("结果", isPresented: Binding(get: { saved || failed }, set: { if !$0 { saved = false; failed = false } })) {
                Button("好") { if saved { dismiss() } }
            } message: { Text(failed ? "添加失败，请检查命令与 cron 表达式。" : "已添加为定时任务。") }
        }
        .onAppear {
            let path = node.parent.isEmpty ? "" : node.parent + "/"
            command = "task \(path)\(node.title)"
            name = node.title
        }
    }

    private func save() async {
        let ok = await session.createCron(command: command, schedule: schedule, name: name.isEmpty ? node.title : name)
        if ok { saved = true } else { failed = true }
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
