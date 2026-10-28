import Foundation
import Security

struct Server: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var address = ""
    var port = 22
    var user = ""

    var title: String { name.isEmpty ? address : name }
    /// Host keys are pinned per address, so pointing a server somewhere else starts a fresh pin.
    var pinKey: String { "\(address):\(port)" }
    var passwordAccount: String { "password.\(id.uuidString)" }
}

/// The server list, in UserDefaults. Secrets live in the Keychain, never here.
final class Store: ObservableObject {
    @Published var servers: [Server] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(servers), forKey: "servers") }
    }

    init() {
        let data = UserDefaults.standard.data(forKey: "servers") ?? Data()
        servers = (try? JSONDecoder().decode([Server].self, from: data)) ?? []
    }

    func save(_ server: Server) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        Keychain.set(server.passwordAccount, nil)
    }
}

/// SHA-256 host key fingerprints, keyed by `Server.pinKey`.
enum Pins {
    private static var all: [String: String] {
        UserDefaults.standard.dictionary(forKey: "pins") as? [String: String] ?? [:]
    }

    static func get(_ key: String) -> String? { all[key] }

    static func set(_ key: String, _ fingerprint: String?) {
        var pins = all
        pins[key] = fingerprint
        UserDefaults.standard.set(pins, forKey: "pins")
    }
}

enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Empty or nil deletes. Updates in place, so a failed write keeps the old secret.
    @discardableResult
    static func set(_ account: String, _ value: String?) -> Bool {
        guard let value, !value.isEmpty else {
            return [errSecSuccess, errSecItemNotFound].contains(SecItemDelete(query(account) as CFDictionary))
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}
