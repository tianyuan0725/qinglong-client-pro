import SwiftUI
import UniformTypeIdentifiers

/// 文件备份（原 VIP 功能，现免费）：导出面板脚本 + 配置到本机，或从备份恢复。
struct BackupView: View {
    @EnvironmentObject var session: PanelSession
    @State private var showFilePicker = false
    @State private var shareURL: URL?
    @State private var lastBackupURL: URL?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var working = false

    var body: some View {
        List {
            Section {
                Button { Task { await runBackup() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                        Text("备份脚本与配置")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working)
                Button { showFilePicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                        Text("从备份文件恢复")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working)
            } header: {
                Text("备份 / 恢复")
            } footer: {
                Text("备份 = 面板「脚本」目录全部文件 + 「配置文件」全部内容，导出为 JSON 保存到本机文件 App。恢复时自动上传回面板。")
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
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let url = shareURL { ShareSheet(url: url) }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("好") { }
        } message: { Text(alertMessage) }
    }

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
}

/// 系统分享面板。
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
