import SwiftUI

/// 关于软件：客户端版本 + 面板版本信息 + 面板更新日志。
struct AboutView: View {
    @EnvironmentObject var session: PanelSession

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(qlBrandGreen)
                            .frame(width: 56, height: 56)
                        Text("青龙")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("青龙客户端 Pro")
                            .font(.headline)
                        Text("免费无广告 · 功能与网页版一致")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("版本信息") {
                infoRow("客户端版本", "\(appVersion) (\(appBuild))")
                infoRow("面板版本", session.panelInfo?.version ?? "—")
                infoRow("面板分支", session.panelInfo?.branch ?? "—")
                infoRow("发布时间", session.panelInfo?.publishDateText ?? "—")
                infoRow("登录账号", session.currentUser?.username ?? "—")
            }

            Section("面板更新日志") {
                Text(session.panelInfo?.changeLog?.isEmpty == false ? session.panelInfo!.changeLog! : "暂无更新日志")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("相关链接") {
                if let u = URL(string: "https://github.com/tianyuan0725/qinglong-client-pro") {
                    Link(destination: u) {
                        Label("客户端源码（GitHub）", systemImage: "link")
                    }
                }
                if let u = URL(string: "https://github.com/whyour/qinglong") {
                    Link(destination: u) {
                        Label("青龙面板开源仓库", systemImage: "link")
                    }
                }
            }

            Section {
                Text("本应用是青龙面板（whyour/qinglong）的第三方 iOS 客户端，凭据仅保存在本机 Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于软件")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if session.panelInfo == nil { await session.loadPanelInfo() }
            if session.currentUser == nil { await session.loadCurrentUser() }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1)
        }
    }
}
