import SwiftUI

/// 环境变量列表：序号 + 状态徽标 + 筛选段（全部 / 已启用 / 已禁用）。
struct EnvListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var search = ""
    @State private var filter: String = "all"
    @State private var showEditor = false
    @State private var editing: EnvVar?
    @State private var revealed = Set<String>()

    private var filtered: [EnvVar] {
        var list = session.envs
        switch filter {
        case "enabled": list = list.filter { $0.isEnabled }
        case "disabled": list = list.filter { !$0.isEnabled }
        default: break
        }
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
                Section {
                    Picker("状态", selection: $filter) {
                        Text("全部").tag("all")
                        Text("已启用").tag("enabled")
                        Text("已禁用").tag("disabled")
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listRowSeparator(.hidden)

                Section {
                    ForEach(filtered.indices, id: \.self) { idx in
                        let env = filtered[idx]
                        row(env, index: idx)
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
            }
            .listStyle(.insetGrouped)
            .navigationTitle("环境变量")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索名称 / 备注 / 值")
            .refreshable { await session.loadEnvs() }
            .overlay {
                if session.envs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "key")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("暂无变量，点右上角 + 新增")
                            .foregroundStyle(.secondary)
                    }
                } else if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("没有匹配的变量")
                            .foregroundStyle(.secondary)
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
            .task { if session.envs.isEmpty { await session.loadEnvs() } }
        }
    }

    private func row(_ env: EnvVar, index: Int) -> some View {
        let isRevealed = revealed.contains(env.id)
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(env.isEnabled ? qlBrandGreen.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 26, height: 26)
                Text("\(index + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(env.isEnabled ? qlBrandGreen : .gray)
            }
            NavigationLink {
                EnvEditorView(editing: env)
                    .environmentObject(session)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(env.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if let r = env.remarks, !r.isEmpty {
                            Text("(\(r))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(masked(env.value, revealed: isRevealed))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Button {
                withAnimation { toggleReveal(env.id) }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            StatusPill(text: env.isEnabled ? "已启用" : "已禁用",
                       color: env.isEnabled ? qlBrandGreen : .gray)
        }
        .padding(.vertical, 2)
    }

    private func toggleReveal(_ id: String) {
        if revealed.contains(id) { revealed.remove(id) }
        else { revealed.insert(id) }
    }
}
