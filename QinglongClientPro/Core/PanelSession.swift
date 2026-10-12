import Foundation
import SwiftUI

/// Live session bound to one Qinglong panel: owns the API client and all
/// loaded data (system info, crons, envs) plus mutation helpers.
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

    func cronLog(id: String) async -> String {
        (try? await client.cronLog(id: id)) ?? "（无法获取日志）"
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
