import SwiftUI

struct ScriptEditorView: View {
    @EnvironmentObject var session: PanelSession
    let node: FileNode
    @State private var content = ""
    @State private var loading = true
    @State private var saved = false
    @State private var runResult = ""
    @State private var showRunResult = false
    @State private var running = false
    // 历史版本
    @State private var showHistory = false
    // 下载
    @State private var showDownload = false

    var body: some View {
        Group {
            if loading {
                ProgressView("读取中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $content)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(4)
            }
        }
        .navigationTitle(node.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button {
                        Task { await run() }
                    } label: { Label("运行", systemImage: "play.circle") }
                        .disabled(loading || running)
                    Button {
                        showHistory = true
                    } label: { Label("历史版本", systemImage: "clock.arrow.circlepath") }
                    Button {
                        showDownload = true
                    } label: { Label("下载到本机", systemImage: "arrow.down.circle") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { Task { saved = await session.saveFile(path: node.parent, filename: node.title, content: content) } }
                    .disabled(loading)
            }
        }
        .task {
            content = await session.readFile(node: node)
            loading = false
        }
        .alert("运行结果", isPresented: $showRunResult) {
            Button("好") { }
        } message: { Text(runResult.isEmpty ? "已启动（无返回）" : "进程 PID：\(runResult)") }
        .alert("已保存", isPresented: $saved) {
            Button("好") { }
        } message: { Text("\(node.title) 已保存到面板。") }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                ScriptHistoryView(node: node) { historyContent in
                    // 将历史版本内容载入编辑器（用户确认后由恢复流程写入）
                    content = historyContent
                }
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $showDownload) {
            ScriptDownloadSheet(node: node) { _ in }
                .environmentObject(session)
        }
    }

    private func run() async {
        running = true
        defer { running = false }
        let pid = await session.runScript(path: node.parent, filename: node.title, content: content)
        runResult = pid
        showRunResult = true
    }
}

/// 脚本历史版本列表（GET /api/scripts/history）。
struct ScriptHistoryView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let node: FileNode
    /// 载入某个历史版本内容到编辑器。
    var onLoad: (String) -> Void

    @State private var items: [ScriptHistoryItem] = []
    @State private var loading = true
    @State private var unavailable: String?
    @State private var preview: HistoryPreview?
    @State private var confirmRestore: ScriptHistoryItem?
    @State private var restored = false
    @State private var restoreFailed: String?

    var body: some View {
        List {
            if loading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if let unavailable {
                Section {
                    Label(unavailable, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(QLPalette.orange)
                }
            } else if items.isEmpty {
                Section {
                    Text("该脚本暂无历史版本（保存后自动生成）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(items) { item in
                        Button {
                            Task { await loadPreview(item) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.createTimeText)
                                        .font(.subheadline.monospacedDigit())
                                    Text(item.sizeText)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Image(systemName: "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button {
                                confirmRestore = item
                            } label: { Label("恢复", systemImage: "arrow.uturn.backward") }
                                .tint(qlBrandGreen)
                        }
                    }
                } header: {
                    Text("共 \(items.count) 个版本（左滑恢复）")
                } footer: {
                    Text("恢复会用所选版本覆盖当前文件，当前内容会自动存为一个新历史版本。")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("历史版本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
        .task {
            items = await session.loadScriptHistory(path: node.parent, filename: node.title)
            loading = false
        }
        .sheet(item: $preview) { item in
            NavigationStack {
                ScrollView {
                    Text(item.text.isEmpty ? "（空文件）" : item.text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle("版本内容")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { preview = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("载入编辑器") {
                            onLoad(item.text)
                            preview = nil
                            dismiss()
                        }
                    }
                }
            }
        }
        .alert("恢复历史版本", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } })) {
            Button("取消", role: .cancel) { confirmRestore = nil }
            Button("恢复", role: .destructive) {
                if let item = confirmRestore {
                    Task {
                        let ok = await session.restoreScriptHistory(path: node.parent, filename: node.title, id: item.historyId ?? "")
                        if ok {
                            restored = true
                            items = await session.loadScriptHistory(path: node.parent, filename: node.title)
                        } else {
                            restoreFailed = session.lastError ?? "恢复失败"
                        }
                    }
                }
                confirmRestore = nil
            }
        } message: {
            Text(confirmRestore.map { "将用 \($0.createTimeText) 的版本覆盖当前文件？" } ?? "")
        }
        .alert("已恢复", isPresented: $restored) {
            Button("好") { }
        } message: { Text("已恢复到所选历史版本，文件内容已更新。") }
        .alert("恢复失败", isPresented: Binding(get: { restoreFailed != nil }, set: { if !$0 { restoreFailed = nil } })) {
            Button("好") { restoreFailed = nil }
        } message: { Text(restoreFailed ?? "") }
    }

    private func loadPreview(_ item: ScriptHistoryItem) async {
        let text = await session.loadScriptHistoryDetail(path: node.parent, filename: node.title, id: item.historyId ?? "")
        preview = HistoryPreview(id: item.historyId ?? "", text: text)
    }
}

/// 历史版本预览包装（Identifiable，供 sheet(item:) 使用）。
struct HistoryPreview: Identifiable {
    let id: String
    let text: String
}
