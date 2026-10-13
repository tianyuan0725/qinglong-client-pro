import SwiftUI

/// 检查更新。
///
/// 根因（v2.0.7/v2.0.8 已踩的坑）：qinglong-client-pro 是**私有仓库**，未登录的 GitHub REST API
/// 对私有仓库直接返回 404；国内网络直连 api.github.com 又常被重置（NSURLErrorDomain -1011）；
/// 公开代理（ghproxy 系列）证书不受信任 / 限流 403 / 返回网页而非 JSON。
/// 自 v2.0.9 起改用「带只读 Token 的 GitHub API」读取 releases/latest：
/// - Token 通过 GitHub Actions 构建密钥（UPDATE_CHECK_TOKEN）在**编译期注入**，不会提交进仓库源码；
/// - Token 仅用于读取该仓库的 Release 元数据（只读），即使泄露也无可写权限；
/// - 增加重试（应对国内网络偶发重置），错误提示不再误报「网络连接不安全」。
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// 仓库 releases/latest 路径。
    private static let repoPath = "repos/tianyuan0725/qinglong-client-pro/releases/latest"
    /// 候选 host：主域名优先。若主域名在部分网络被重置，可在此追加同样支持 Bearer Token 的镜像。
    private static let candidateHosts = [
        "https://api.github.com",
    ]

    /// 编译期由 CI 注入（build.yml 的「Inject update-check token」步骤把 REPLACE_WITH_GITHUB_TOKEN 替换为密钥）。
    /// 本地直接 Archive 调试、或 CI 未配置密钥时，该值为占位符，更新检查会因 401 失败——属正常，
    /// 安装请用 CI 产物（IPA）。
    private static let githubToken = "REPLACE_WITH_GITHUB_TOKEN"

    /// 自动检查更新开关（进入「我的」页时会自动检查一次）。
    @AppStorage("qlpro_updateNotify") var updateNotifyEnabled: Bool = true

    /// 远端最新版本号（已去掉 v 前缀），如 "2.0.9"。
    @Published var latestVersion: String?
    /// 是否正在检查。
    @Published var checking = false
    /// 是否有新版本（远端 > 本地）。
    @Published var hasUpdate = false
    /// 更新说明（Release body）。
    @Published var releaseNotes: String?
    /// Release 页面链接。
    @Published var releaseURL: URL?
    /// 最近一次检查的错误信息（成功时为 nil）。已本地化为中文。
    @Published var error: String?

    /// 当前 App 版本（CFBundleShortVersionString）。
    var currentVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return v.isEmpty ? "0" : v
    }

    /// 专用会话：短超时 + 不等待系统连通性（避免在无网时长时间挂起）。
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    /// 拉取最新 Release 并与当前版本比较。可重复调用。
    func check() async {
        if checking { return }
        checking = true
        error = nil
        // defer 保证无论成功/失败/超时，checking 都会复位，绝不卡「正在更新…」。
        defer { checking = false }
        do {
            let release = try await withTotalTimeout(seconds: 45) { try await fetchLatestRelease() }
            let remote = Self.normalizeVersion(release.tagName)
            latestVersion = remote
            releaseNotes = release.body
            releaseURL = URL(string: release.htmlURL)
            hasUpdate = Self.compare(remote, currentVersion) == .orderedDescending
        } catch {
            // 网络失败/接口异常：保留上一次的判定结果，只记录友好的中文错误，
            // 绝不把 hasUpdate 置回 false（避免「明明有新版却提示已是最新」）。
            self.error = Self.friendlyError(error)
        }
    }

    // MARK: - 网络（带 Token + 重试）

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

    /// 带重试地拉取最新 Release（应对国内网络偶发重置）。最多 3 轮，每轮依次尝试候选 host。
    private func fetchLatestRelease() async throws -> ReleasePayload {
        var lastErr: Error = URLError(.badServerResponse)
        for attempt in 0..<3 {
            for host in Self.candidateHosts {
                guard let url = URL(string: host + "/" + Self.repoPath) else { continue }
                do {
                    let payload = try await fetch(from: url)
                    if !payload.tagName.isEmpty {
                        return payload
                    }
                } catch {
                    lastErr = error
                }
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 重试前短暂退避
            }
        }
        throw lastErr
    }

    private func fetch(from url: URL) async throws -> ReleasePayload {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("QinglongClientPro-iOS", forHTTPHeaderField: "User-Agent")
        if !Self.githubToken.isEmpty, Self.githubToken != "REPLACE_WITH_GITHUB_TOKEN" {
            req.setValue("Bearer " + Self.githubToken, forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 10
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw URLError(.userAuthenticationRequired)
            }
            if !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
        }
        return try JSONDecoder().decode(ReleasePayload.self, from: data)
    }

    /// 对整个检查加总超时：网络调用与「到点抛超时」赛跑，先完成者胜出。
    private func withTotalTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw URLError(.timedOut) }
            return result
        }
    }

    // MARK: - 错误本地化

    static func friendlyError(_ err: Error) -> String {
        if let urlErr = err as? URLError {
            switch urlErr.code {
            case .timedOut:
                return "检查更新超时，请稍后重试"
            case .notConnectedToInternet:
                return "当前无网络连接，请联网后重试"
            case .userAuthenticationRequired:
                return "更新校验失败（Token 未配置），请联系开发者"
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .resourceUnavailable:
                return "无法连接更新服务器，请稍后重试"
            default:
                // 证书等其它错误统一归为「服务器异常」，不再甩「请更换网络」误导用户。
                return "检查更新失败，请稍后重试"
            }
        }
        return "检查更新失败，请稍后重试"
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
