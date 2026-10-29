import Foundation
import Security
import CoreTransferable
import UniformTypeIdentifiers

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

    /// Address and user trimmed, or nil when the device couldn't connect. Both the form and backup restore save this.
    var cleaned: Server? {
        var server = self
        server.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        server.user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return server.address.isEmpty || server.user.isEmpty || !(1...65535).contains(port) ? nil : server
    }
}

/// The server list, in UserDefaults. Secrets live in the Keychain, never here.
final class Store: ObservableObject {
    @Published var servers: [Server] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(servers), forKey: "servers") }
    }

    init() {
        let data = UserDefaults.standard.data(forKey: "servers") ?? Data()
        do {
            servers = data.isEmpty ? [] : try JSONDecoder().decode([Server].self, from: data)
        } catch {
            servers = []
            // Kept aside, since the next save writes over "servers": a build that reads it can bring the devices back.
            UserDefaults.standard.set(data, forKey: "servers.unreadable")
        }
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

/// Devices, pinned host keys and settings as one JSON file, to share and restore on another phone.
/// Passwords and the private key stay in the Keychain: the file may land in Files or iCloud.
struct Backup: Codable, Transferable {
    var servers: [Server]
    var pins: [String: String]
    var theme: String?
    var font: String?
    var fontSize: Double?
    var snippets: String?

    init(_ store: Store) {
        let defaults = UserDefaults.standard
        servers = store.servers
        pins = Pins.all
        theme = defaults.string(forKey: "theme")
        font = defaults.string(forKey: "font")
        fontSize = defaults.object(forKey: "fontSize") as? Double
        snippets = defaults.string(forKey: "snippets")
    }

    /// Adds devices or replaces them by id and takes the settings. A host key this phone already pinned wins.
    /// Returns how many devices were taken; ones the device form would refuse are skipped.
    func restore(into store: Store) -> Int {
        let valid = servers.compactMap(\.cleaned)
        valid.forEach(store.save)
        Pins.all = Pins.all.merging(pins) { current, _ in current }
        let defaults = UserDefaults.standard
        for (key, value) in [("theme", theme), ("font", font), ("snippets", snippets)] where value != nil {
            defaults.set(value, forKey: key)
        }
        if let fontSize { defaults.set(min(max(fontSize, 8), 32), forKey: "fontSize") }
        return valid.count
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json).suggestedFileName("deckterm-yedek.json")
    }
}

/// SHA-256 host key fingerprints, keyed by `Server.pinKey`.
enum Pins {
    static var all: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "pins") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "pins") }
    }

    static func get(_ key: String) -> String? { all[key] }
    static func set(_ key: String, _ fingerprint: String?) { all[key] = fingerprint }
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
