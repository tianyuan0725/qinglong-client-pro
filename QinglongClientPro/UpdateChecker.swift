import SwiftUI

/// 检查 GitHub Release 更新。
///
/// v2.0.8 重构：此前很多用户在国内网络下要么报 `NSURLErrorDomain -1011`（BadServerResponse，
/// 实为 api.github.com 被干扰/重置），要么一直卡在「正在更新…」。本版：
/// - 数据源固定为仓库 `releases/latest`，但**依次尝试多个备援地址**（主域名 + 公共镜像），
///   任一可达即成功，大幅提高国内网络下的可用性。
/// - 每个地址都有 10 秒硬超时，并对整个检查加 40 秒总超时，保证 `checking` 必定复位、绝不卡死。
/// - 错误文案本地化为中文，不再把系统原始错误码直接甩给用户。
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// 仓库 releases/latest 路径（拼到各候选 host 前面）。
    private static let repoPath = "repos/tianyuan0725/qinglong-client-pro/releases/latest"

    /// 候选地址：主域名优先，失败后依次尝试公共镜像。
    private static let candidateHosts = [
        "https://api.github.com",
        "https://ghproxy.com/https://api.github.com",
        "https://ghproxy.net/https://api.github.com",
        "https://mirror.ghproxy.com/https://api.github.com",
    ]

    /// 自动检查更新开关（进入「我的」页时会自动检查一次）。
    @AppStorage("qlpro_updateNotify") var updateNotifyEnabled: Bool = true

    /// 远端最新版本号（已去掉 v 前缀），如 "2.0.8"。
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
            let release = try await withTotalTimeout(seconds: 40) { try await fetchLatestRelease() }
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

    // MARK: - 网络（多备援地址 + 单地址超时）

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

    /// 依次尝试候选地址，第一个成功即返回；全部失败抛出最后一个错误。
    private func fetchLatestRelease() async throws -> ReleasePayload {
        var lastErr: Error = URLError(.badServerResponse)
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
        throw lastErr
    }

    private func fetch(from url: URL) async throws -> ReleasePayload {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("QinglongClientPro-iOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 4xx/5xx 视为服务器异常（含镜像偶尔的 502），交给上层换下一个地址重试。
            throw URLError(.badServerResponse)
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
            defer { group.cancelAllTasks() }
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
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .resourceUnavailable:
                return "无法连接更新服务器（网络受限），请检查网络或稍后重试"
            case .badServerResponse:
                return "更新服务器返回异常，请稍后重试"
            case .secureConnectionFailed, .serverCertificateUntrusted, .clientCertificateRejected:
                return "网络连接不安全，请更换网络后重试"
            default:
                return "检查更新失败：\(urlErr.localizedDescription)"
            }
        }
        return "检查更新失败：\(err.localizedDescription)"
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
