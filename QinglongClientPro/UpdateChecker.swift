import Foundation
import SwiftUI

/// App 更新检查 —— 查询 GitHub Releases 最新版本（对齐参考 App「App更新通知」）。
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// 最新版本号（如 "2.0.0"）。
    @Published var latestVersion: String?
    /// 最新版本发布说明。
    @Published var releaseNotes: String?
    /// 下载页面 URL。
    @Published var releaseURL: URL?
    /// 是否存在比当前 App 更新的版本。
    @Published var hasUpdate = false
    /// 检查是否进行中。
    @Published var checking = false
    /// 最近一次检查错误。
    @Published var error: String?

    private let repoOwner = "tianyuan0725"
    private let repoName = "qinglong-client-pro"

    /// 当前 App 版本号。
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 是否开启更新通知（持久化开关）。
    @AppStorage("qlpro_updateNotify") var updateNotifyEnabled: Bool = true

    private init() {}

    /// 查询 GitHub 最新 release 并与当前版本比较。
    func check() async {
        guard !checking else { return }
        checking = true
        error = nil
        defer { checking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("QinglongClientPro/2.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                // 404 = 还没有 release，不视为错误
                if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                    hasUpdate = false
                    return
                }
                error = "检查失败（HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)）"
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                error = "返回数据格式错误"
                return
            }
            let tag = (json["tag_name"] as? String)?.replacingOccurrences(of: "v", with: "") ?? ""
            latestVersion = tag
            releaseNotes = json["body"] as? String
            if let html = json["html_url"] as? String {
                releaseURL = URL(string: html)
            }
            hasUpdate = versionCompare(tag, currentVersion) > 0
        } catch {
            error = error.localizedDescription
        }
    }

    /// 比较版本号：返回 1 表示 a 更新、-1 表示 b 更新、0 相同。
    private func versionCompare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }
}
