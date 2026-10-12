import SwiftUI

struct EnvListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var search = ""
    @State private var showEditor = false
    @State private var editing: EnvVar?
    @State private var revealed = Set<String>()

    private var filtered: [EnvVar] {
        let list = session.envs
        guard !search.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            ($0.remarks ?? "").localizedCaseInsensitiveContains(search) ||
            $0.value.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { env in
                    row(env)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await session.deleteEnv([env.id]) }
                            } label: { Label("删除", systemImage: "trash") }
                            Button {
                                Task { await session.toggleEnv(env) }
                            } label: {
                                Label(env.isEnabled ? "禁用" : "启用",
                                      systemImage: env.isEnabled ? "eye.slash" : "eye")
                            }
                            .tint(env.isEnabled ? .orange : .blue)
                        }
                }
            }
            .navigationTitle("环境变量")
            .searchable(text: $search, prompt: "搜索名称 / 备注 / 值")
            .refreshable { await session.loadEnvs() }
            .overlay {
                if session.envs.isEmpty {
                    VStack {
                        Spacer()
                        Text("暂无变量，点右上角 + 新增")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = nil
                        showEditor = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showEditor) {
                EnvEditorView(editing: editing)
                    .environmentObject(session)
            }
        }
    }

    private func row(_ env: EnvVar) -> some View {
        let isRevealed = revealed.contains(env.id)
        return HStack(spacing: 12) {
            NavigationLink {
                EnvEditorView(editing: env)
                    .environmentObject(session)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "key")
                        .foregroundStyle(env.isEnabled ? Color.accentColor : .gray)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(env.name).font(.headline).lineLimit(1)
                            if !env.isEnabled {
                                StatusPill(text: "已禁用", color: .gray)
                            }
                        }
                        Text(masked(env.value, revealed: isRevealed))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let r = env.remarks, !r.isEmpty {
                            Text(r)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Button {
                withAnimation { toggleReveal(env.id) }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func toggleReveal(_ id: String) {
        if revealed.contains(id) { revealed.remove(id) }
        else { revealed.insert(id) }
    }
}
