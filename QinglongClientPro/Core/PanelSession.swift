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

    func setPanelTitle(_ v: String) async { await applyConfigField { try await client.updatePanelTitle(v) } }
    func setTimezone(_ v: String) async { await applyConfigField { try await client.updateTimezone(v) } }
    func setLogRemoveFrequency(_ v: Int?) async { await applyConfigField { try await client.updateLogRemoveFrequency(v) } }
    func setCronConcurrency(_ v: Int?) async { await applyConfigField { try await client.updateCronConcurrency(v) } }
    func setDependenceProxy(_ v: String) async { await applyConfigField { try await client.updateDependenceProxy(v) } }
    func setNodeMirror(_ v: String) async { await applyConfigField { try await client.updateNodeMirror(v) } }
    func setPythonMirror(_ v: String) async { await applyConfigField { try await client.updatePythonMirror(v) } }
    func setLinuxMirror(_ v: String) async { await applyConfigField { try await client.updateLinuxMirror(v) } }

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
}
