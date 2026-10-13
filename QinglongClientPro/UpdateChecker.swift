import SwiftUI

/// 检查 GitHub Release 更新。
///
/// v2.0.7 整体重写：旧版比较逻辑不可靠（用户反馈「已经发布新版本，检测更新仍提示已是最新版本」）。
/// 新实现要点：
/// - 数据源固定为仓库 `releases/latest`（tag_name / body / html_url）
/// - 语义化版本比较：去掉 `v` 前缀后按数字段逐个比较，**远端大于本地才判定有更新**
/// - 比较失败/网络错误时保留上一次的结果，仅记录错误，不会误报「已是最新」
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private static let latestReleaseURL = "https://api.github.com/repos/tianyuan0725/qinglong-client-pro/releases/latest"

    /// 自动检查更新开关（进入「我的」页时会自动检查一次）。
    @AppStorage("qlpro_updateNotify") var updateNotifyEnabled: Bool = true

    /// 远端最新版本号（已去掉 v 前缀），如 "2.0.7"。
    @Published var latestVersion: String?
    /// 是否正在检查。
    @Published var checking = false
    /// 是否有新版本（远端 > 本地）。
    @Published var hasUpdate = false
    /// 更新说明（Release body）。
    @Published var releaseNotes: String?
    ///  Release 页面链接。
    @Published var releaseURL: URL?
    /// 最近一次检查的错误信息（成功时为 nil）。
    @Published var error: String?

    /// 当前 App 版本（CFBundleShortVersionString）。
    var currentVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return v.isEmpty ? "0" : v
    }

    private init() {}

    /// 拉取最新 Release 并与当前版本比较。可重复调用。
    func check() async {
        if checking { return }
        checking = true
        error = nil
        defer { checking = false }
        do {
            let release = try await fetchLatestRelease()
            let remote = Self.normalizeVersion(release.tagName)
            latestVersion = remote
            releaseNotes = release.body
            releaseURL = URL(string: release.htmlURL)
            hasUpdate = Self.compare(remote, currentVersion) == .orderedDescending
        } catch {
            // 网络失败/接口异常：保留上一次的判定结果，只记录错误，
            // 绝不把 hasUpdate 置回 false（避免「明明有新版却提示已是最新」）。
            error = error.localizedDescription
        }
    }

    // MARK: - 网络

    private struct ReleasePayload: Decodable {
        var tagName: String
        var body: String?
        var htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
        }
    }

    private func fetchLatestRelease() async throws -> ReleasePayload {
        guard let url = URL(string: Self.latestReleaseURL) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QinglongClientPro-iOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ReleasePayload.self, from: data)
    }

    // MARK: - 版本比较

    /// 去掉 `v`/`V` 前缀与空白，如 "v2.0.7" → "2.0.7"。
    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s = String(s.dropFirst())
        }
        return s
    }

    /// 语义化比较：按 `.` 分段逐个转 Int 比较，缺省段按 0。
    /// 忽略 `-`/`+` 之后的预发布/构建元数据。
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func segments(_ v: String) -> [Int] {
            let core = v.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let sa = segments(normalizeVersion(a))
        let sb = segments(normalizeVersion(b))
        let count = max(sa.count, sb.count)
        for i in 0..<count {
            let x = i < sa.count ? sa[i] : 0
            let y = i < sb.count ? sb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
