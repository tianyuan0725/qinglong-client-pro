import Foundation

/// Owns the list of configured Qinglong panels (loaded from the Keychain).
@MainActor
final class ConnectionStore: ObservableObject {
    @Published var connections: [Connection] = []

    init() { load() }

    func load() {
        connections = KeychainHelper.accounts().compactMap { account in
            guard let data = KeychainHelper.load(account: account),
                  let conn = try? JSONDecoder().decode(Connection.self, from: data) else { return nil }
            return conn
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func save(_ conn: Connection) {
        if let data = try? JSONEncoder().encode(conn) {
            KeychainHelper.save(data, account: conn.id)
        }
        load()
    }

    func delete(_ conn: Connection) {
        KeychainHelper.delete(account: conn.id)
        connections.removeAll { $0.id == conn.id }
    }

    func connection(withId id: String) -> Connection? {
        connections.first { $0.id == id }
    }
}
