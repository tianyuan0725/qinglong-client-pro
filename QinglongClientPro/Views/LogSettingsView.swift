import SwiftUI

/// 日志设置：系统日志文件浏览 / 查看 / 删除 + 自动清理频率。
struct LogSettingsView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        Form {
            Section("系统日志文件") {
                ForEach(session.logFiles) { node in
                    NavigationLink {
                        LogFileDetailView(node: node)
                            .environmentObject(session)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(node.title)
                                .lineLimit(1)
                            Spacer()
                            if let s = node.sizeText {
                                Text(s)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            Section("面板日志") {
                NavigationLink {
                    SystemLogView()
                        .environmentObject(session)
                } label: {
                    Label("查看面板运行日志", systemImage: "doc.text.magnifyingglass")
                }
            }
            Section {
                if let freq = session.systemConfig?.info?.logRemoveFrequency {
                    Stepper("自动清理：每 \(freq) 天", value: Binding(
                        get: { freq },
                        set: { v in Task { await session.setLogRemoveFrequency(v) } }
                    ))
                } else {
                    Text("读取中…").foregroundStyle(.secondary)
                }
            } header: {
                Text("日志清理")
            } footer: {
                Text("面板自动删除超过设定天数的日志文件；0 表示不自动清理。左滑日志文件可手动删除。")
                    .font(.caption)
            }
        }
        .navigationTitle("日志设置")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.loadLogFiles() }
        .task {
            await session.loadLogFiles()
            if session.systemConfig == nil { await session.loadSystemConfig() }
        }
        .overlay {
            if session.logFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("暂无日志文件")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let nodes = offsets.compactMap { session.logFiles[safe: $0] }
        Task { for n in nodes { await session.deleteLogFile(n) } }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// 单个日志文件内容查看。
struct LogFileDetailView: View {
    @EnvironmentObject var session: PanelSession
    let node: FileNode
    @State private var content = ""

    var body: some View {
        ScrollView {
            Text(content.isEmpty ? "（空文件或读取失败）" : content)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(node.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { content = await session.logFileContent(node) }
    }
}
