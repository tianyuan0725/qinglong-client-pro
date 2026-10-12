import SwiftUI

struct DependencyListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showEditor = false
    @State private var editing: Dependency? = nil
    @State private var confirmDelete: [Dependency]? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                List {
                    ForEach(session.dependencies) { dep in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dep.name).font(.subheadline.weight(.medium))
                                HStack(spacing: 6) {
                                    StatusPill(text: dep.typeLabel, color: .gray)
                                    if !dep.remark.isEmpty {
                                        Text(dep.remark).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            StatusPill(text: dep.statusLabel, color: statusColor(dep))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { confirmDelete = [dep] } label: { Label("删除", systemImage: "trash") }
                            Button { Task { await session.reinstallDependencies(ids: [dep._id]) } } label: { Label("重装", systemImage: "arrow.clockwise") }
                                .tint(.blue)
                            if dep.isBusy {
                                Button { Task { await session.cancelDependencies(ids: [dep._id]) } } label: { Label("取消", systemImage: "xmark") }
                                    .tint(.orange)
                            }
                            Button { editing = dep } label: { Label("编辑", systemImage: "pencil") }
                                .tint(.indigo)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("依赖管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await session.loadDependencies() }
            .refreshable { await session.loadDependencies() }
            .sheet(isPresented: $showEditor) { DependencyEditorView(editing: nil) }
            .sheet(item: $editing) { dep in DependencyEditorView(editing: dep) }
            .alert("删除依赖", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("取消", role: .cancel) { confirmDelete = nil }
                Button("删除") {
                    if let arr = confirmDelete { Task { await session.deleteDependencies(ids: arr.map { $0._id }) } }
                    confirmDelete = nil
                }
                .tint(.red)
                Button("强制删除", role: .destructive) {
                    if let arr = confirmDelete { Task { await session.deleteDependencies(ids: arr.map { $0._id }, force: true) } }
                    confirmDelete = nil
                }
            } message: { Text(confirmDelete.map { "确定删除依赖 \($0.first?.name ?? "")？" } ?? "") }
        }
        .onChange(of: session.depTypeFilter) { Task { await session.loadDependencies() } }
        .onChange(of: session.depStatusFilter) { Task { await session.loadDependencies() } }
    }

    private func statusColor(_ dep: Dependency) -> Color {
        if dep.isInstalled { return .green }
        if dep.isBusy { return .blue }
        if dep.status == 2 || dep.status == 5 { return .red }
        if dep.status == 7 { return .gray }
        return .orange
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("类型", selection: $session.depTypeFilter) {
                Text("全部").tag(Int?.none)
                Text("Node.js").tag(Int?.some(0))
                Text("Python3").tag(Int?.some(1))
                Text("Linux").tag(Int?.some(2))
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索依赖名", text: $session.depSearch)
                    .onSubmit { Task { await session.loadDependencies() } }
                Picker("状态", selection: $session.depStatusFilter) {
                    Text("全部").tag("")
                    Text("已安装").tag("1")
                    Text("安装中").tag("0")
                    Text("失败").tag("2")
                    Text("排队中").tag("6")
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

struct DependencyEditorView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let editing: Dependency?

    @State private var name: String = ""
    @State private var type: Int = 0
    @State private var remark: String = ""

    init(editing: Dependency?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _type = State(initialValue: editing?.type ?? 0)
        _remark = State(initialValue: editing?.remark ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("依赖名称") {
                    TextField("例如 axios / requests", text: $name)
                }
                Section("类型") {
                    Picker("类型", selection: $type) {
                        Text("Node.js").tag(0)
                        Text("Python3").tag(1)
                        Text("Linux").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section("备注") {
                    TextField("可选", text: $remark)
                }
            }
            .navigationTitle(editing == nil ? "新建依赖" : "编辑依赖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        Task {
                            let ok: Bool
                            if let dep = editing {
                                var d = dep
                                d.name = n; d.type = type; d.remark = remark
                                ok = await session.updateDependency(d)
                            } else {
                                ok = await session.createDependency(name: n, type: type, remark: remark)
                            }
                            if ok { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || session.isBusy)
                }
            }
        }
    }
}
