import CryptoKit
import Foundation
import SwiftUI

/// Live session bound to one Qinglong panel: owns the API client and all
/// loaded data (system info, crons, envs, scripts, dependencies, subscriptions,
/// configs, apps, system config) plus mutation helpers.
@MainActor
final class PanelSession: ObservableObject {
    let connection: Connection
    private(set) var client: APIClient

    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var isBusy = false
    /// 是否需要两步验证码（普通登录返回 code 420）。
    @Published var needsTwoFactor = false

    @Published var systemInfo: SystemInfo?
    @Published var crons: [CronTask] = []
    @Published var envs: [EnvVar] = []

    // 脚本管理
    @Published var fileNodes: [FileNode] = []
    @Published var scriptPath: String = ""

    // 依赖管理
    @Published var dependencies: [Dependency] = []
    @Published var depTypeFilter: Int? = nil
    @Published var depSearch: String = ""
    @Published var depStatusFilter: String = ""

    // 配置文件
    @Published var configFiles: [ConfigFile] = []

    // 订阅管理
    @Published var subscriptions: [Subscription] = []

    // 应用设置 (Open API)
    @Published var apps: [AppItem] = []

    // 系统设置
    @Published var systemConfig: SystemConfig?
    @Published var panelInfo: PanelInfo?
    @Published var systemLogText: String = ""

    @Published var lastError: String?

    init(connection: Connection) {
        self.connection = connection
        guard let url = connection.normalizedBaseURL else {
            fatalError("Invalid base URL for connection: \(connection.baseURLString)")
        }
        self.client = APIClient(baseURL: url, apiPrefix: connection.apiPrefix)
    }

    // MARK: - Lifecycle

    func login() async {
        needsTwoFactor = false
        do {
            let token = try await client.authenticate(
                authType: connection.authType,
                username: connection.username,
                password: connection.password,
                clientID: connection.clientID,
                clientSecret: connection.clientSecret
            )
            client.token = token
            isAuthenticated = true
            await loadAll()
        } catch APIError.twoFactorRequired {
            needsTwoFactor = true
            authError = nil
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 两步验证码登录（面板开启 2FA 时）。
    func loginWithTwoFactor(code: String) async {
        do {
            let token = try await client.twoFactorLogin(
                code: code,
                username: connection.username,
                password: connection.password
            )
            client.token = token
            isAuthenticated = true
            needsTwoFactor = false
            await loadAll()
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSystem() }
            group.addTask { await self.loadCrons() }
            group.addTask { await self.loadEnvs() }
            group.addTask { await self.loadPanelInfo() }
        }
    }

    // MARK: - Stats

    var cronCount: Int { crons.count }
    var envCount: Int { envs.count }
    var runningCount: Int { crons.filter { $0.isRunning }.count }
    var disabledCronCount: Int { crons.filter { !$0.isEnabled }.count }
    var disabledEnvCount: Int { envs.filter { !$0.isEnabled }.count }

    // MARK: - Loaders

    func loadSystem() async {
        do { systemInfo = try await client.getSystem() }
        catch { lastError = error.localizedDescription }
    }

    func loadCrons() async {
        do { crons = try await client.getCrons() }
        catch { lastError = error.localizedDescription }
    }

    func loadEnvs() async {
        do { envs = try await client.getEnvs() }
        catch { lastError = error.localizedDescription }
    }

    func loadPanelInfo() async {
        do { panelInfo = try await client.getPanelInfo() }
        catch { /* 非关键 */ }
    }

    func cronLog(id: String) async -> String {
        (try? await client.cronLog(id: id)) ?? "（无法获取日志）"
    }

    // MARK: - 脚本管理

    func loadFiles() async {
        do { fileNodes = try await client.getFileList(path: scriptPath.isEmpty ? nil : scriptPath) }
        catch { lastError = error.localizedDescription }
    }

    func enterDir(_ node: FileNode) {
        scriptPath = node.key
        Task { await loadFiles() }
    }

    func goUp() {
        // 回到上一级目录
        if scriptPath.contains("/") {
            scriptPath = String(scriptPath.prefix(upTo: scriptPath.lastIndex(of: "/")!))
        } else {
            scriptPath = ""
        }
        Task { await loadFiles() }
    }

    func goRoot() {
        scriptPath = ""
        Task { await loadFiles() }
    }

    func readFile(node: FileNode) async -> String {
        (try? await client.getFileContent(path: node.parent, file: node.title)) ?? "（无法读取文件）"
    }

    func saveFile(path: String, filename: String, content: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.saveFileContent(path: path, filename: filename, content: content); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func createFile(path: String, filename: String, content: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.createFile(path: path, filename: filename, content: content); await loadFiles(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func makeDir(path: String, dirname: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.createDirectory(path: path, dirname: dirname); await loadFiles(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func removeFile(node: FileNode) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteFile(path: node.parent, filename: node.title); await loadFiles() }
        catch { lastError = error.localizedDescription }
    }

    func renameFile(node: FileNode, newName: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.renameFile(path: node.parent, filename: node.title, newFilename: newName); await loadFiles(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func runScript(path: String, filename: String, content: String) async -> String {
        isBusy = true; defer { isBusy = false }
        do { return try await client.runScript(path: path, filename: filename, content: content) }
        catch { lastError = error.localizedDescription; return "" }
    }

    // MARK: - 脚本批量操作（多选模式，循环单文件接口）

    /// 批量删除文件（顺序执行，逐个删除）。
    func removeFiles(nodes: [FileNode]) async {
        isBusy = true; defer { isBusy = false }
        for node in nodes {
            do { try await client.deleteFile(path: node.parent, filename: node.title) }
            catch { lastError = "删除 \(node.title) 失败：\(error.localizedDescription)" }
        }
        await loadFiles()
    }

    /// 批量运行文件（逐个启动，返回成功数量）。
    @discardableResult
    func runFiles(nodes: [FileNode]) async -> Int {
        isBusy = true; defer { isBusy = false }
        var ok = 0
        for node in nodes {
            do {
                let content = try await client.getFileContent(path: node.parent, file: node.title)
                _ = try await client.runScript(path: node.parent, filename: node.title, content: content)
                ok += 1
            } catch { lastError = "运行 \(node.title) 失败：\(error.localizedDescription)" }
        }
        return ok
    }

    // MARK: - 脚本下载 / 历史版本

    /// 下载脚本二进制（用于保存到本地 / 分享）。
    func downloadScriptData(path: String, filename: String) async -> Data? {
        do { return try await client.downloadScript(path: path, filename: filename) }
        catch { lastError = error.localizedDescription; return nil }
    }

    /// 加载脚本历史版本列表。
    func loadScriptHistory(path: String, filename: String) async -> [ScriptHistoryItem] {
        do { return try await client.getScriptHistory(path: path, filename: filename) }
        catch { lastError = error.localizedDescription; return [] }
    }

    /// 读取单个历史版本内容。
    func loadScriptHistoryDetail(path: String, filename: String, id: String) async -> String {
        do { return try await client.getScriptHistoryDetail(path: path, filename: filename, id: id) }
        catch { lastError = error.localizedDescription; return "" }
    }

    /// 恢复历史版本：先下载当前文件计算 SHA-256（expectedHash），再调 restore。
    func restoreScriptHistory(path: String, filename: String, id: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do {
            // expectedHash = 当前文件内容的 SHA-256（64 hex）
            let current = try await client.downloadScript(path: path, filename: filename)
            let expectedHash = SHA256.hash(data: current).compactMap { String(format: "%02x", $0) }.joined()
            try await client.restoreScriptHistory(path: path, filename: filename, id: id, expectedHash: expectedHash)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - 依赖管理

    func loadDependencies() async {
        do {
            dependencies = try await client.getDependencies(
                type: depTypeFilter,
                search: depSearch.isEmpty ? nil : depSearch,
                status: depStatusFilter.isEmpty ? nil : depStatusFilter
            )
        } catch { lastError = error.localizedDescription }
    }

    func createDependency(name: String, type: Int, remark: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.createDependencies([["name": name, "type": type, "remark": remark]]); await loadDependencies(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func updateDependency(_ dep: Dependency) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.updateDependency(id: dep._id, name: dep.name, type: dep.type, remark: dep.remark); await loadDependencies(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func deleteDependencies(ids: [Int], force: Bool = false) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteDependencies(ids: ids, force: force); await loadDependencies() }
        catch { lastError = error.localizedDescription }
    }

    func reinstallDependencies(ids: [Int]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.reinstallDependencies(ids: ids); await loadDependencies() }
        catch { lastError = error.localizedDescription }
    }

    func cancelDependencies(ids: [Int]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.cancelDependencies(ids: ids); await loadDependencies() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: - 配置文件

    func loadConfigFiles() async {
        do { configFiles = try await client.getConfigFiles() }
        catch { lastError = error.localizedDescription }
    }

    func readConfig(name: String) async -> String {
        (try? await client.getConfigContent(path: name)) ?? "（无法读取配置）"
    }

    func saveConfig(name: String, content: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.saveConfig(name: name, content: content); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    // MARK: - 订阅管理

    func loadSubscriptions() async {
        do { subscriptions = try await client.getSubscriptions() }
        catch { lastError = error.localizedDescription }
    }

    func runSubscriptions(ids: [Int]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.runSubscriptions(ids: ids); try? await Task.sleep(nanoseconds: 800_000_000); await loadSubscriptions() }
        catch { lastError = error.localizedDescription }
    }

    func stopSubscriptions(ids: [Int]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.stopSubscriptions(ids: ids); await loadSubscriptions() }
        catch { lastError = error.localizedDescription }
    }

    func toggleSubscriptions(_ subs: [Subscription]) async {
        isBusy = true; defer { isBusy = false }
        let ids = subs.map { $0._id }
        do {
            if subs.allSatisfy({ $0.isEnabled }) { try await client.disableSubscriptions(ids: ids) }
            else { try await client.enableSubscriptions(ids: ids) }
            await loadSubscriptions()
        } catch { lastError = error.localizedDescription }
    }

    func deleteSubscriptions(ids: [Int]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteSubscriptions(ids: ids); await loadSubscriptions() }
        catch { lastError = error.localizedDescription }
    }

    func createSubscription(_ payload: [String: Any]) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.createSubscription(payload); await loadSubscriptions(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func updateSubscription(_ payload: [String: Any]) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.updateSubscription(payload); await loadSubscriptions(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func subscriptionLog(id: Int) async -> String {
        (try? await client.subscriptionLog(id: id)) ?? "（无法获取日志）"
    }

    // MARK: - 应用设置 (Open API)

    func loadApps() async {
        do { apps = try await client.getApps() }
        catch { lastError = error.localizedDescription }
    }

    func createApp(name: String, scopes: [String]) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.createApp(name: name, scopes: scopes); await loadApps(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func updateApp(_ app: AppItem) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.updateApp(id: app._id, name: app.name, scopes: app.scopes); await loadApps(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func deleteApps(ids: [Int]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteApps(ids: ids); await loadApps() }
        catch { lastError = error.localizedDescription }
    }

    func resetAppSecret(id: Int) async -> String {
        isBusy = true; defer { isBusy = false }
        do { return try await client.resetAppSecret(id: id) }
        catch { lastError = error.localizedDescription; return "" }
    }

    // MARK: - 系统设置

    func loadSystemConfig() async {
        do { systemConfig = try await client.getSystemConfig() }
        catch { lastError = error.localizedDescription }
    }

    func setPanelTitle(_ v: String) async { await applyConfigField { try await self.client.updatePanelTitle(v) } }
    func setTimezone(_ v: String) async { await applyConfigField { try await self.client.updateTimezone(v) } }
    func setLogRemoveFrequency(_ v: Int?) async { await applyConfigField { try await self.client.updateLogRemoveFrequency(v) } }
    func setCronConcurrency(_ v: Int?) async { await applyConfigField { try await self.client.updateCronConcurrency(v) } }
    func setDependenceProxy(_ v: String) async { await applyConfigField { try await self.client.updateDependenceProxy(v) } }
    func setNodeMirror(_ v: String) async { await applyConfigField { try await self.client.updateNodeMirror(v) } }
    func setPythonMirror(_ v: String) async { await applyConfigField { try await self.client.updatePythonMirror(v) } }
    func setLinuxMirror(_ v: String) async { await applyConfigField { try await self.client.updateLinuxMirror(v) } }

    func applyConfigField(_ apply: @escaping () async throws -> Void) async {
        isBusy = true; defer { isBusy = false }
        do { try await apply(); await loadSystemConfig() }
        catch { lastError = error.localizedDescription }
    }

    func sendNotify(title: String, content: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.sendNotify(title: title, content: content); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func loadSystemLog() async {
        isBusy = true; defer { isBusy = false }
        do { systemLogText = try await client.getSystemLog() }
        catch { lastError = error.localizedDescription; systemLogText = "（无法读取系统日志）" }
    }

    // MARK: - Cron mutations

    func runCron(_ ids: [String]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.runCron(ids: ids); try? await Task.sleep(nanoseconds: 600_000_000); await loadCrons() }
        catch { lastError = error.localizedDescription }
    }

    func stopCron(_ ids: [String]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.stopCron(ids: ids); await loadCrons() }
        catch { lastError = error.localizedDescription }
    }

    func toggleCron(_ cron: CronTask) async {
        isBusy = true; defer { isBusy = false }
        do {
            if cron.isEnabled { try await client.disableCron(ids: [cron.id]) }
            else { try await client.enableCron(ids: [cron.id]) }
            await loadCrons()
        } catch { lastError = error.localizedDescription }
    }

    func pinCron(_ cron: CronTask) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.pinCron(ids: [cron.id]); await loadCrons() }
        catch { lastError = error.localizedDescription }
    }

    func saveCron(_ cron: CronTask, isNew: Bool) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.saveCron(cron, isNew: isNew); await loadCrons(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    /// 快速创建定时任务（从脚本「添加到任务」用）。
    func createCron(command: String, schedule: String, name: String) async -> Bool {
        let cron = CronTask(name: name, command: command, schedule: schedule)
        return await saveCron(cron, isNew: true)
    }

    // MARK: - 面板数据导出 / 导入 (v2.20+)

    /// 导出面板数据 zip（PUT /api/system/data/export），返回本机临时文件 URL。
    func exportPanelDataZip(types: [String] = []) async throws -> URL {
        let data = try await client.exportPanelData(types: types)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let dest = docs.appendingPathComponent("qinglong_backup_\(df.string(from: Date())).zip")
        try data.write(to: dest, options: .atomic)
        return dest
    }

    /// 从 zip 恢复面板数据（PUT /api/system/data/import）。
    func importPanelDataZip(url: URL) async throws {
        try await client.importPanelData(fileURL: url)
    }

    // MARK: - 版本检查 / 面板升级 (v2.20+)

    /// 检查面板是否有新版本。
    func checkServerUpdate() async -> ServerUpdateInfo {
        do { return try await client.checkServerUpdate() }
        catch { lastError = error.localizedDescription; return ServerUpdateInfo() }
    }

    /// 触发面板自身升级。
    func updatePanelSystem() async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.updatePanelSystem(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    /// 面板新版本信息（供「我的」页展示提示条）。
    @Published var serverUpdate: ServerUpdateInfo?

    func deleteCron(_ ids: [String]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteCron(ids: ids); await loadCrons() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: - Env mutations

    func toggleEnv(_ env: EnvVar) async {
        isBusy = true; defer { isBusy = false }
        do {
            if env.isEnabled { try await client.disableEnv(ids: [env.id]) }
            else { try await client.enableEnv(ids: [env.id]) }
            await loadEnvs()
        } catch { lastError = error.localizedDescription }
    }

    func saveEnv(_ env: EnvVar, isNew: Bool) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.saveEnv(env, isNew: isNew); await loadEnvs(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func deleteEnv(_ ids: [String]) async {
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteEnv(ids: ids); await loadEnvs() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: - 当前用户 / 登录日志 / 通知配置 / 系统日志文件

    @Published var currentUser: UserInfo?
    @Published var loginLogs: [LoginLogEntry] = []
    @Published var notificationConfig: NotificationConfig?
    @Published var logFiles: [FileNode] = []

    func loadCurrentUser() async {
        do { currentUser = try await client.getCurrentUser() }
        catch { /* 非关键，忽略 */ }
    }

    func loadLoginLogs() async {
        do { loginLogs = try await client.getLoginLogs() }
        catch { lastError = error.localizedDescription }
    }

    func loadNotificationConfig() async {
        do { notificationConfig = try await client.getNotificationConfig() }
        catch { lastError = error.localizedDescription }
    }

    func saveNotificationConfig(_ config: NotificationConfig, channel: NotifyChannel) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do {
            try await client.updateNotificationConfig(config.payload(channel: channel))
            await loadNotificationConfig()
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    func changeCredentials(username: String, password: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.updateUsernameAndPassword(username: username, password: password); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func loadLogFiles() async {
        do { logFiles = try await client.getLogFiles() }
        catch { lastError = error.localizedDescription }
    }

    func logFileContent(_ node: FileNode) async -> String {
        (try? await client.getLogFileContent(path: node.parent, file: node.title)) ?? "（无法读取日志文件）"
    }

    func deleteLogFile(_ node: FileNode) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do { try await client.deleteLogFile(path: node.parent, file: node.title); await loadLogFiles(); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    // MARK: - 依赖扫描（原 VIP 功能，现已免费）

    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var scanResult: [DepScanItem] = []
    @Published var scanError: String?
    /// 一键补装缺失依赖。
    func installMissingDependencies(_ items: [DepScanItem]) async -> Bool {
        guard !items.isEmpty else { return false }
        isBusy = true; defer { isBusy = false }
        do {
            let payload = items.map { ["name": $0.name, "type": $0.type, "remark": "扫描依赖自动补装"] as [String: Any] }
            try await client.createDependencies(payload)
            await loadDependencies()
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    /// 递归扫描面板脚本目录，提取 require/import 依赖并与已装依赖比对。
    func scanScriptDependencies() async {
        guard !isScanning else { return }
        isScanning = true; scanError = nil; scanResult = []
        defer { isScanning = false; scanProgress = "" }
        do {
            // 1) 递归收集全部脚本文件（显式栈，避免深递归）
            var stack: [String] = [""]
            var visited = Set<String>()
            var files: [(path: String, name: String)] = []
            while !stack.isEmpty {
                let dir = stack.removeLast()
                let nodes = try await self.client.getFileList(path: dir.isEmpty ? nil : dir)
                for n in nodes {
                    let key = n.key.isEmpty ? n.title : n.key
                    if visited.contains(key) { continue }
                    visited.insert(key)
                    if n.isDirectory {
                        scanProgress = "扫描目录 \(key)"
                        stack.append(key)
                    } else if Self.scriptExtensions.contains((n.title as NSString).pathExtension.lowercased()) {
                        files.append((n.parent, n.title))
                    }
                }
            }
            // 2) 下载脚本内容并解析依赖引用
            var found: [String: DepScanItem] = [:]
            for (idx, f) in files.enumerated() {
                scanProgress = "解析 \(f.name)（\(idx + 1)/\(files.count)）"
                let content = (try? await self.client.getFileContent(path: f.path, file: f.name)) ?? ""
                for (name, type) in Self.extractDeps(from: content, filename: f.name) {
                    let k = "\(name.lowercased())|\(type)"
                    if var item = found[k] {
                        if !item.sources.contains(f.name) { item.sources.append(f.name) }
                        found[k] = item
                    } else {
                        found[k] = DepScanItem(name: name, type: type, sources: [f.name], installed: false)
                    }
                }
            }
            // 3) 与面板已有依赖比对（同名即视为已处理）
            let listed = Set(dependencies.map { $0.name.lowercased() })
            scanResult = found.values.map { item in
                var i = item
                i.installed = listed.contains(item.name.lowercased())
                return i
            }
            .sorted { lhs, rhs in
                if lhs.installed != rhs.installed { return !lhs.installed }
                if lhs.type != rhs.type { return lhs.type < rhs.type }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            if scanResult.isEmpty { scanError = "未在脚本中发现第三方依赖引用" }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private static let scriptExtensions: Set<String> = ["js", "mjs", "cjs", "ts", "py", "sh"]

    /// Node.js 内置模块（无需安装依赖）。
    private static let nodeBuiltins: Set<String> = [
        "assert","async_hooks","buffer","child_process","cluster","console","constants","crypto",
        "dgram","diagnostics_channel","dns","domain","events","fs","http","http2","https","inspector",
        "module","net","os","path","perf_hooks","process","punycode","querystring","readline","repl",
        "stream","string_decoder","sys","timers","tls","trace_events","tty","url","util","v8","vm",
        "wasi","worker_threads","zlib",
    ]

    /// Python 标准库常见模块（不列为依赖）。
    private static let pythonStdlib: Set<String> = [
        "abc","argparse","array","ast","asyncio","atexit","base64","bdb","binascii","bisect","builtins",
        "bz2","calendar","cgi","cgitb","chunk","cmath","cmd","code","codecs","codeop","collections",
        "colorsys","compileall","concurrent","configparser","contextlib","contextvars","copy","copyreg",
        "cProfile","crypt","csv","ctypes","curses","dataclasses","datetime","dbm","decimal","difflib",
        "dis","distutils","doctest","email","encodings","enum","errno","faulthandler","fcntl","filecmp",
        "fileinput","fnmatch","fractions","ftplib","functools","gc","getopt","getpass","gettext","glob",
        "graphlib","grp","gzip","hashlib","heapq","hmac","html","http","imaplib","importlib","inspect",
        "io","ipaddress","itertools","json","keyword","linecache","locale","logging","lzma","mailbox",
        "mailcap","marshal","math","mimetypes","mmap","modulefinder","msilib","msvcrt","multiprocessing",
        "netrc","nis","nntplib","numbers","operator","optparse","os","ossaudiodev","pathlib","pdb","pickle",
        "pickletools","pipes","pkgutil","platform","plistlib","poplib","posix","posixpath","pprint",
        "profile","pstats","pty","pwd","py_compile","pyclbr","pydoc","queue","quopri","random","re",
        "readline","reprlib","resource","rlcompleter","runpy","sched","secrets","select","selectors",
        "shelve","shlex","shutil","signal","site","smtpd","smtplib","sndhdr","socket","socketserver",
        "spwd","sqlite3","ssl","stat","statistics","string","stringprep","struct","subprocess","sunau",
        "symtable","sys","sysconfig","syslog","tabnanny","tarfile","telnetlib","tempfile","termios",
        "textwrap","threading","time","timeit","tkinter","token","tokenize","tomllib","trace","traceback",
        "tracemalloc","tty","turtle","turtledemo","types","typing","unicodedata","unittest","urllib",
        "uu","uuid","venv","warnings","wave","weakref","webbrowser","winreg","winsound","wsgiref","xdrlib",
        "xml","xmlrpc","zipapp","zipfile","zipimport","zlib","zoneinfo",
    ]

    /// 从脚本内容中提取第三方依赖引用。返回 (依赖名, 类型)。
    static func extractDeps(from content: String, filename: String) -> [(name: String, type: Int)] {
        var result: [(String, Int)] = []
        var seen = Set<String>()
        func add(_ name: String, _ type: Int) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let k = "\(trimmed.lowercased())|\(type)"
            guard !seen.contains(k) else { return }
            seen.insert(k)
            result.append((trimmed, type))
        }
        let ext = (filename as NSString).pathExtension.lowercased()

        if ext == "py" {
            // import a / import a.b / from a.b import c（跳过 from . import 相对导入）
            if let re = try? NSRegularExpression(pattern: #"(?m)^\s*(?:import|from)\s+([A-Za-z_][A-Za-z0-9_.]*)"#) {
                let ns = content as NSString
                for m in re.matches(in: content, range: NSRange(content.startIndex..., in: content)) {
                    guard let r = Range(m.range(at: 1), in: content) else { continue }
                    let mod = String(content[r])
                    let top = mod.split(separator: ".").first.map(String.init) ?? mod
                    guard !pythonStdlib.contains(top.lowercased()) else { continue }
                    add(top, 1)
                }
            }
        } else if ext == "sh" {
            // apk add / apt-get install / pip3 install / npm i -g 等
            if let re = try? NSRegularExpression(pattern: #"(?m)(?:apk\s+(?:--\S+\s+)*add|apt(?:-get)?\s+(?:-\S+\s+)*install|yum\s+(?:-\S+\s+)*install|dnf\s+(?:-\S+\s+)*install|pip3?\s+install|npm\s+(?:i|install|add)\s+(?:-g\s+)?|pnpm\s+add\s+(?:-g\s+)?|python3?\s+-m\s+pip\s+install)\s+([^\n;&|]+)"#) {
                let ns = content as NSString
                for m in re.matches(in: content, range: NSRange(content.startIndex..., in: content)) {
                    guard let r = Range(m.range(at: 1), in: content) else { continue }
                    let seg = String(content[r])
                    for raw in seg.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                        var token = String(raw)
                        if token.hasPrefix("-") { continue }
                        // 去掉版本约束：pkg==1.0 / pkg>=1 / pkg@1.2
                        if let eq = token.firstIndex(of: "=") { token = String(token[..<eq]) }
                        if let at = token.firstIndex(of: "@"), !token.hasPrefix("@") { token = String(token[..<at]) }
                        token = token.trimmingCharacters(in: .whitespaces)
                        guard !token.isEmpty else { continue }
                        if token.lowercased() == "install" { continue }
                        add(token, 2)
                    }
                }
            }
        } else {
            // JS/TS: require('x') / from 'x' / import 'x'
            let patterns = [
                #"require\(\s*['"]([^'"\n]+)['"]\s*\)"#,
                #"from\s+['"]([^'"\n]+)['"]"#,
                #"import\s+['"]([^'"\n]+)['"]"#,
                #"import\(\s*['"]([^'"\n]+)['"]\s*\)"#,
            ]
            for p in patterns {
                guard let re = try? NSRegularExpression(pattern: p) else { continue }
                for m in re.matches(in: content, range: NSRange(content.startIndex..., in: content)) {
                    guard let r = Range(m.range(at: 1), in: content) else { continue }
                    let spec = String(content[r])
                    if spec.hasPrefix(".") || spec.hasPrefix("/") || spec.hasPrefix("node:") { continue }
                    let parts = spec.split(separator: "/").map(String.init)
                    guard var name = parts.first, !name.isEmpty else { continue }
                    if name.hasPrefix("@"), parts.count >= 2 { name = parts[0] + "/" + parts[1] }
                    guard !nodeBuiltins.contains(name.lowercased()) else { continue }
                    add(name, 0)
                }
            }
        }
        return result
    }

    // MARK: - 文件备份 / 恢复（原 VIP 功能，现免费）

    @Published var backupProgress: String = ""

    private struct BackupFile: Codable { var path: String = ""; var name: String = ""; var content: String = "" }
    private struct BackupPayload: Codable {
        var app: String = "QinglongClientPro"
        var version: Int = 1
        var panel: String = ""
        var exportedAt: String = ""
        var scripts: [BackupFile] = []
        var configs: [BackupFile] = []
    }

    /// 导出面板脚本 + 配置为 JSON 文件，返回本机文件 URL。
    func exportBackup() async throws -> URL {
        await loadConfigFiles()
        backupProgress = "收集脚本列表…"
        // 递归收集全部脚本文件（显式栈）
        var stack: [String] = [""]
        var visited = Set<String>()
        var files: [(path: String, name: String)] = []
        while !stack.isEmpty {
            let dir = stack.removeLast()
            let nodes = try await self.client.getFileList(path: dir.isEmpty ? nil : dir)
            for n in nodes {
                let key = n.key.isEmpty ? n.title : n.key
                if visited.contains(key) { continue }
                visited.insert(key)
                if n.isDirectory { stack.append(key) }
                else { files.append((n.parent, n.title)) }
            }
        }
        var scripts: [BackupFile] = []
        for (idx, f) in files.enumerated() {
            backupProgress = "读取脚本 \(f.name)（\(idx + 1)/\(files.count)）"
            let content = (try? await self.client.getFileContent(path: f.path, file: f.name)) ?? ""
            scripts.append(BackupFile(path: f.path, name: f.name, content: content))
        }
        var configs: [BackupFile] = []
        for (idx, cfg) in configFiles.enumerated() {
            backupProgress = "读取配置 \(cfg.title)（\(idx + 1)/\(configFiles.count)）"
            let content = (try? await self.client.getConfigContent(path: cfg.value)) ?? ""
            configs.append(BackupFile(path: "", name: cfg.value, content: content))
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let payload = BackupPayload(panel: connection.name, exportedAt: df.string(from: Date()),
                                    scripts: scripts, configs: configs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        df.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("qinglong-backup-\(df.string(from: Date())).json")
        try data.write(to: url)
        backupProgress = ""
        return url
    }

    /// 从备份 JSON 恢复脚本 + 配置到面板，返回恢复的文件数量。
    func restoreBackup(from url: URL) async throws -> Int {
        isBusy = true
        defer { isBusy = false; backupProgress = "" }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)
        // 先补齐目录
        let dirs = Set(payload.scripts.map { $0.path }.filter { !$0.isEmpty })
        for d in dirs {
            backupProgress = "创建目录 \(d)"
            if let last = d.lastIndex(of: "/") {
                _ = try? await self.client.createDirectory(path: String(d[d.startIndex..<last]),
                                                           dirname: String(d[d.index(after: last)...]))
            } else {
                _ = try? await self.client.createDirectory(path: "", dirname: d)
            }
        }
        var count = 0
        for (idx, f) in payload.scripts.enumerated() {
            backupProgress = "恢复脚本 \(f.name)（\(idx + 1)/\(payload.scripts.count)）"
            do { try await self.client.saveFileContent(path: f.path, filename: f.name, content: f.content) }
            catch { try await self.client.createFile(path: f.path, filename: f.name, content: f.content) }
            count += 1
        }
        for (idx, f) in payload.configs.enumerated() {
            backupProgress = "恢复配置 \(f.name)（\(idx + 1)/\(payload.configs.count)）"
            try await self.client.saveConfig(name: f.name, content: f.content)
            count += 1
        }
        await loadFiles()
        await loadConfigFiles()
        return count
    }
}
