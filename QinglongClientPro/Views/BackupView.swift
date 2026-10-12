import SwiftUI
import UniformTypeIdentifiers

/// 文件备份（原 VIP 功能，现免费）：本机 JSON 备份 + 面板数据 zip 导出/导入 + iCloud 入口。
struct BackupView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showFilePicker = false
    @State private var shareURL: URL?
    @State private var lastBackupURL: URL?
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
                Text("将备份文件存储到 iCloud Drive，可在多设备间同步。需要已在系统「设置 → Apple ID → iCloud」中打开 iCloud 云盘。")
                    .font(.caption)
            }

            if !session.backupProgress.isEmpty {
                Section {
                    Text(session.backupProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let url = lastBackupURL {
                Section("最近备份") {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(qlBrandGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(url.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Button { shareURL = url } label: {
                        Label("分享备份文件", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("文件备份")
        .navigationBarTitleDisplayMode(.inline)
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
}

/// iCloud 备份管理：展示本机备份文件，支持存入 iCloud Drive 目录。
struct ICloudBackupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var localFiles: [URL] = []
    @State private var iCloudAvailable = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: iCloudAvailable ? "checkmark.icloud" : "xmark.icloud")
                            .foregroundStyle(iCloudAvailable ? qlBrandGreen : .secondary)
                        Text(iCloudAvailable ? "iCloud 云盘可用" : "iCloud 云盘不可用")
                            .font(.subheadline)
                    }
                } footer: {
                    Text("备份文件默认保存在 App 的「文件」容器中。打开系统「文件」App → 我的 iPhone → 青龙客户端Pro 即可导出到 iCloud 云盘。")
                        .font(.caption)
                }

                Section("本机备份文件（\(localFiles.count)）") {
                    if localFiles.isEmpty {
                        Text("暂无备份文件，请先在「文件备份」中导出。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(localFiles, id: \.self) { url in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.zipper")
                                    .foregroundStyle(qlBrandGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(url.path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
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
            .alert("提示", isPresented: $showAlert) {
                Button("好") { }
            } message: { Text(alertMessage) }
        }
    }

    private func loadFiles() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        localFiles = files
            .filter { $0.pathExtension == "json" || $0.pathExtension == "zip" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
