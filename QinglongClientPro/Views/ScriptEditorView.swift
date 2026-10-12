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
                Button { Task { await run() } } label: { Image(systemName: "play.circle") }
                    .disabled(loading || running)
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
    }

    private func run() async {
        running = true
        defer { running = false }
        let pid = await session.runScript(path: node.parent, filename: node.title, content: content)
        runResult = pid
        showRunResult = true
    }
}
