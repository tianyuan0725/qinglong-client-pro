import SwiftUI

struct ConfigListView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        NavigationStack {
            List {
                if session.configFiles.isEmpty {
                    Text("暂无配置文件")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(session.configFiles) { file in
                    NavigationLink {
                        ConfigEditorView(file: file)
                    } label: {
                        HStack {
                            Image(systemName: "gearshape").foregroundStyle(.gray)
                            Text(file.title)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("配置文件")
            .task { await session.loadConfigFiles() }
            .refreshable { await session.loadConfigFiles() }
        }
    }
}

struct ConfigEditorView: View {
    @EnvironmentObject var session: PanelSession
    let file: ConfigFile
    @State private var content = ""
    @State private var loading = true
    @State private var saved = false

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
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { Task { saved = await session.saveConfig(name: file.value, content: content) } }
                    .disabled(loading)
            }
        }
        .task {
            content = await session.readConfig(name: file.value)
            loading = false
        }
    }
}
