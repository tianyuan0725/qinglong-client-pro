import Foundation

/// Owns the list of configured Qinglong panels (loaded from the Keychain).
/// 面板顺序按管理员手动排列持久化（UserDefaults），不再按名称排序。
@MainActor
final class ConnectionStore: ObservableObject {
    @Published var connections: [Connection] = []

    private let orderKey = "qlpro_connectionOrder"

    init() { load() }

    func load() {
        let all = KeychainHelper.accounts().compactMap { account -> Connection? in
            guard let data = KeychainHelper.load(account: account),
                  let conn = try? JSONDecoder().decode(Connection.self, from: data) else { return nil }
            return conn
        }
        let order = persistedOrder()
        var ordered: [Connection] = []
        for id in order {
            if let c = all.first(where: { $0.id == id }) { ordered.append(c) }
        }
        // 新面板（不在顺序表中）追加在末尾
        ordered.append(contentsOf: all.filter { c in !order.contains(c.id) })
        connections = ordered
    }

    func save(_ conn: Connection) {
        if let data = try? JSONEncoder().encode(conn) {
            KeychainHelper.save(data, account: conn.id)
        }
        load()
        persistOrder()
    }

    func delete(_ conn: Connection) {
        KeychainHelper.delete(account: conn.id)
        connections.removeAll { $0.id == conn.id }
        persistOrder()
    }

    /// 拖拽排序（账号排序功能）。
    func move(from source: IndexSet, to destination: Int) {
        connections.move(fromOffsets: source, toOffset: destination)
        persistOrder()
    }

    func connection(withId id: String) -> Connection? {
        connections.first { $0.id == id }
    }

    // MARK: - 顺序持久化

    private func persistedOrder() -> [String] {
        (UserDefaults.standard.string(forKey: orderKey) ?? "")
            .split(separator: ",")
            .map(String.init)
    }

    private func persistOrder() {
        UserDefaults.standard.set(connections.map { $0.id }.joined(separator: ","), forKey: orderKey)
    }
}
