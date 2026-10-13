import SwiftUI

struct DependencyListView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showEditor = false
    @State private var editing: Dependency? = nil
    @State private var confirmDelete: [Dependency]? = nil
    @State private var logDep: Dependency? = nil
    @State private var typeSegment = -1        // -1 全部 / 0 Node / 1 Python / 2 Linux
    @State private var statusSegment = ""      // "" 全部 / 状态数字

    var body: some View {
            VStack(spacing: 0) {
                filterBar
                List {
                    ForEach(displayedDeps) { dep in
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
                            Button { logDep = dep } label: { Label("日志", systemImage: "doc.plaintext") }
                                .tint(.purple)
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
            .sheet(item: $logDep) { dep in DependencyLogSheet(dep: dep) }
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

    private func statusColor(_ dep: Dependency) -> Color {
        if dep.isInstalled { return .green }
        if dep.isBusy { return .blue }
        if dep.status == 2 || dep.status == 5 { return .red }
        if dep.status == 7 { return .gray }
        return .orange
    }

    /// 客户端即时筛选：按类型 / 状态 / 搜索关键字过滤，切段控件无需等待网络。
    private var displayedDeps: [Dependency] {
        session.dependencies.filter { dep in
            if typeSegment >= 0, dep.type != typeSegment { return false }
            if !statusSegment.isEmpty, String(dep.status) != statusSegment { return false }
            if !session.depSearch.isEmpty {
                let q = session.depSearch.lowercased()
                guard dep.name.lowercased().contains(q) || dep.remark.lowercased().contains(q) else { return false }
            }
            return true
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("类型", selection: $typeSegment) {
                Text("全部").tag(-1)
                Text("Node.js").tag(0)
                Text("Python3").tag(1)
                Text("Linux").tag(2)
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索依赖名", text: $session.depSearch)
                Picker("状态", selection: $statusSegment) {
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

/// 依赖日志弹窗：查看单个依赖的安装/运行日志（GET /api/dependencies/{id}/log）。
struct DependencyLogSheet: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    let dep: Dependency

    @State private var logText = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("加载中…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(logText.isEmpty ? "（暂无日志，依赖可能还未安装/运行过）" : logText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                }
            }
            .navigationTitle(dep.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(loading)
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        logText = await session.dependencyLog(id: dep._id)
    }
}
