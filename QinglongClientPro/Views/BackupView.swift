import SwiftUI
import UniformTypeIdentifiers

/// 文件备份（原 VIP 功能，现免费）：本机 JSON 备份 + 面板数据 zip 导出/导入 + iCloud 入口。
struct BackupView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showFilePicker = false
    @State private var shareURL: URL?
    @State private var lastBackupURL: URL?
    @State private var recentBackups: [URL] = []
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var working = false
    // 面板数据 zip
    @State private var showExportTypes = false
    @State private var showZipPicker = false
    // iCloud
    @State private var showICloud = false

    var body: some View {
        List {
            // MARK: 本机 JSON 备份（脚本+配置文件）
            Section {
                Button { Task { await runBackup() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                        Text("备份脚本与配置（JSON）")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working)
                Button { showFilePicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                        Text("从 JSON 备份恢复")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working)
            } header: {
                Text("本机备份（JSON）")
            } footer: {
                Text("备份 = 面板「脚本」目录全部文件 + 「配置文件」全部内容，导出为 JSON 保存到本机文件 App。恢复时自动上传回面板。")
                    .font(.caption)
            }

            // MARK: 面板数据 zip（服务端原生导出）
            Section {
                Button { showExportTypes = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up.on.square")
                        Text("导出面板数据（zip）")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .disabled(working)
                Button { showZipPicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                        Text("从面板数据 zip 恢复")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working)
            } header: {
                Text("面板数据（zip）")
            } footer: {
                Text("使用面板原生导出接口（PUT /api/system/data/export）：包含脚本、任务、环境变量、配置文件等完整数据，可用于迁移或整机恢复。恢复会覆盖面板现有数据，请谨慎操作。")
                    .font(.caption)
            }

            // MARK: iCloud
            Section {
                Button { showICloud = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("iCloud 备份管理")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("将备份文件通过系统分享面板存储到 iCloud 云盘，可在多设备间同步。需要已在系统「设置 → Apple ID → iCloud」中打开 iCloud 云盘。")
                    .font(.caption)
            }

            if !session.backupProgress.isEmpty {
                Section {
                    Text(session.backupProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("备份文件（\(recentBackups.count)）") {
                if recentBackups.isEmpty {
                    Text("暂无备份文件，点上方按钮创建。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentBackups, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(systemName: url.pathExtension == "zip" ? "doc.zipper" : "doc.fill")
                                .foregroundStyle(qlBrandGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(url.pathExtension == "zip" ? "面板数据 zip" : "脚本与配置 JSON")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button { shareURL = url } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await deleteBackup(url) }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("文件备份")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadRecentBackups() }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json, .plainText]) { result in
            if case .success(let url) = result {
                let secured = url.startAccessingSecurityScopedResource()
                Task {
                    await runRestore(url: url)
                    if secured { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .fileImporter(isPresented: $showZipPicker, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result {
                let secured = url.startAccessingSecurityScopedResource()
                Task {
                    await runZipRestore(url: url)
                    if secured { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        .confirmationDialog("选择导出内容", isPresented: $showExportTypes, titleVisibility: .visible) {
            Button("全部数据") { Task { await runZipBackup(types: []) } }
            Button("仅脚本") { Task { await runZipBackup(types: ["script"]) } }
            Button("仅任务与环境变量") { Task { await runZipBackup(types: ["cron", "env"]) } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("zip 导出使用面板服务端接口，内容比 JSON 备份更完整。")
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $showICloud) {
            ICloudBackupView()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("好") { }
        } message: { Text(alertMessage) }
    }

    // MARK: - 本机 JSON 备份
    private func runBackup() async {
        working = true
        defer { working = false }
        do {
            let url = try await session.exportBackup()
            lastBackupURL = url
            shareURL = url
            loadRecentBackups()
        } catch {
            alertTitle = "备份失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func runRestore(url: URL) async {
        working = true
        defer { working = false }
        do {
            let n = try await session.restoreBackup(from: url)
            alertTitle = "恢复完成"
            alertMessage = "已恢复 \(n) 个文件到面板。"
            showAlert = true
        } catch {
            alertTitle = "恢复失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    // MARK: - 面板 zip 导出 / 导入

    private func runZipBackup(types: [String]) async {
        working = true
        defer { working = false }
        do {
            let url = try await session.exportPanelDataZip(types: types)
            lastBackupURL = url
            shareURL = url
            loadRecentBackups()
        } catch {
            alertTitle = "导出失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func runZipRestore(url: URL) async {
        working = true
        defer { working = false }
        do {
            try await session.importPanelDataZip(url: url)
            alertTitle = "恢复完成"
            alertMessage = "面板数据已从 zip 恢复，建议重启面板容器生效。"
            showAlert = true
        } catch {
            alertTitle = "恢复失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    // MARK: - 备份文件列表 / 删除

    private func loadRecentBackups() {
        recentBackups = session.listBackupFiles()
    }

    private func deleteBackup(_ url: URL) async {
        do {
            try session.deleteBackupFile(url)
            loadRecentBackups()
        } catch {
            alertTitle = "删除失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

/// iCloud 备份管理：本机备份文件一键存储到 iCloud 云盘（经系统分享面板），
/// 以及从 iCloud 云盘选择备份恢复。免签名 App 无 iCloud 容器权限，
/// 因此走系统分享/文件选择器，由用户在分享面板中选择「存储到文件」→ iCloud Drive。
struct ICloudBackupView: View {
    @EnvironmentObject var session: PanelSession
    @Environment(\.dismiss) private var dismiss
    @State private var localFiles: [URL] = []
    @State private var shareURL: URL?
    @State private var showZipPicker = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .foregroundStyle(qlBrandGreen)
                            Text("通过「文件」App 同步到 iCloud 云盘")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("1. 先在「文件备份」中导出 JSON 或 zip 备份\n2. 在下方列表中点「存储到 iCloud」\n3. 在分享面板中选择「存储到文件」→ iCloud Drive 或「文件」App 的 iCloud 云盘位置\n4. 换设备后在本页点「从 iCloud 恢复」即可")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("需在系统「设置 → Apple ID → iCloud」中打开 iCloud 云盘，并允许「文件」App 使用 iCloud。")
                        .font(.caption2)
                }

                Section {
                    Button {
                        showZipPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.icloud")
                            Text("从 iCloud 云盘恢复（zip）")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working)
                } header: {
                    Text("恢复")
                } footer: {
                    Text("会打开系统文件选择器，可从 iCloud 云盘中选择此前导出的面板数据 zip。恢复会覆盖面板现有数据，请谨慎操作。")
                        .font(.caption2)
                }

                Section("本机备份文件（\(localFiles.count)）") {
                    if localFiles.isEmpty {
                        Text("暂无备份文件，请先在「文件备份」中导出。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                ForEach(localFiles, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(systemName: url.pathExtension == "zip" ? "doc.zipper" : "doc.text")
                            .foregroundStyle(qlBrandGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(url.pathExtension == "zip" ? "面板数据 zip" : "脚本与配置 JSON")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            shareURL = url
                        } label: {
                            Label("存储到 iCloud", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(qlBrandGreen)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await deleteLocalFile(url) }
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
                    }
                }
            }
            .navigationTitle("iCloud 备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { loadFiles() }
            .fileImporter(isPresented: $showZipPicker, allowedContentTypes: [.zip, .data]) { result in
                if case .success(let url) = result {
                    let secured = url.startAccessingSecurityScopedResource()
                    Task {
                        defer { if secured { url.stopAccessingSecurityScopedResource() } }
                        await restoreFromZip(url: url)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
                if let url = shareURL { ShareSheet(items: [url]) }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("好") { }
            } message: { Text(alertMessage) }
        }
    }

    private func loadFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        localFiles = files
            .filter { $0.pathExtension == "json" || $0.pathExtension == "zip" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func deleteLocalFile(_ url: URL) async {
        do {
            try FileManager.default.removeItem(at: url)
            loadFiles()
        } catch {
            alertTitle = "删除失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func restoreFromZip(url: URL) async {
        working = true
        defer { working = false }
        do {
            try await session.importPanelDataZip(url: url)
            alertTitle = "恢复完成"
            alertMessage = "面板数据已从 zip 恢复，建议重启面板容器生效。"
            showAlert = true
        } catch {
            alertTitle = "恢复失败"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}
