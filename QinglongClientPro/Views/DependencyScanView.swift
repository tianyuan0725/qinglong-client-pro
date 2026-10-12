import SwiftUI

/// 扫描依赖（原 VIP 功能，现免费）：递归扫描面板脚本，提取 require / import /
/// apk add 等依赖声明，与「依赖管理」中已添加的依赖比对，可一键补装缺失项。
struct DependencyScanView: View {
    @EnvironmentObject var session: PanelSession

    private var missing: [DepScanItem] { session.scanResult.filter { !$0.installed } }
    private var handled: [DepScanItem] { session.scanResult.filter { $0.installed } }

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        await session.loadDependencies()
                        await session.scanScriptDependencies()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(session.scanResult.isEmpty ? "开始扫描脚本依赖" : "重新扫描")
                        Spacer()
                        if session.isScanning { ProgressView() }
                    }
                }
                .disabled(session.isScanning)
            } header: {
                Text("扫描")
            } footer: {
                Text("递归扫描面板「脚本」目录下的 .js / .ts / .py / .sh 文件，提取 require / import / apk add 等依赖声明，并与「依赖管理」中已添加的依赖比对。")
                    .font(.caption)
            }

            if session.isScanning {
                Section {
                    Text(session.scanProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let err = session.scanError, !session.isScanning {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !missing.isEmpty {
                Section("缺失依赖 · 面板未添加（\(missing.count)）") {
                    ForEach(missing) { item in
                        row(item, missing: true)
                    }
                }
                Section {
                    Button {
                        Task { await session.installMissingDependencies(missing) }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("一键补装 \(missing.count) 个依赖")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(session.isBusy)
                }
            }

            if !handled.isEmpty {
                Section("已添加的依赖引用（\(handled.count)）") {
                    ForEach(handled) { item in
                        row(item, missing: false)
                    }
                }
            }
        }
        .navigationTitle("扫描依赖")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: DepScanItem, missing: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: missing ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(missing ? Color.orange : Color.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(item.typeLabel) · \(item.sources.count) 个脚本引用：\(item.sources.prefix(3).joined(separator: "、"))\(item.sources.count > 3 ? " 等" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
