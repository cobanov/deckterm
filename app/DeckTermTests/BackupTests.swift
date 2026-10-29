import XCTest
@testable import DeckTerm

/// A backup carried to a phone that already has a pin of its own. Runs in the app's own UserDefaults, next to its
/// real devices, so it uses addresses of its own and puts every key back.
final class BackupTests: XCTestCase {
    private let keys = ["servers", "servers.unreadable", "pins", "theme", "font", "fontSize", "snippets"]
    private var saved: [String: Any] = [:]

    override func setUp() {
        keys.forEach { saved[$0] = UserDefaults.standard.object(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.set(saved[$0], forKey: $0) }
    }

    func testRestoreTakesDevicesAndSettingsButKeepsLocalPins() throws {
        let defaults = UserDefaults.standard
        let store = Store()
        let nuc = Server(name: "backup-test", address: "10.9.9.1", user: "me")
        store.save(nuc)
        Pins.set(nuc.pinKey, "SHA256:there")
        defaults.set("nord", forKey: "theme")
        defaults.set(40.0, forKey: "fontSize")
        defaults.set("htop\ndf -h", forKey: "snippets")
        var backup = try JSONDecoder().decode(Backup.self, from: JSONEncoder().encode(Backup(store)))
        backup.servers.append(Server(name: "broken", address: "", user: "me"))
        backup.servers.append(Server(name: "padded", address: " 10.9.9.3 ", user: "me "))
        backup.pins["10.9.9.2:22"] = "SHA256:new"

        // The other phone: without the device, with its own pin for the same host and other settings.
        store.delete(nuc)
        Pins.set(nuc.pinKey, "SHA256:here")
        defaults.set("classic", forKey: "theme")
        defaults.set(13.0, forKey: "fontSize")
        defaults.set("", forKey: "snippets")
        let other = Store()
        XCTAssertEqual(backup.restore(into: other), backup.servers.count - 1, "all but the broken one")
        XCTAssertTrue(other.servers.contains { $0.id == nuc.id })
        XCTAssertFalse(other.servers.contains { $0.name == "broken" })
        XCTAssertTrue(other.servers.contains { $0.address == "10.9.9.3" && $0.user == "me" }, "trimmed like the form")
        XCTAssertEqual(Pins.get(nuc.pinKey), "SHA256:here")
        XCTAssertEqual(Pins.get("10.9.9.2:22"), "SHA256:new")
        XCTAssertEqual(defaults.string(forKey: "theme"), "nord")
        XCTAssertEqual(defaults.double(forKey: "fontSize"), 32)
        XCTAssertEqual(defaults.string(forKey: "snippets"), "htop\ndf -h")
    }

    /// What the device list and backups hold today. A new Server field that old files lack fails here, not on the phone.
    func testReadsTheSavedFormat() throws {
        let json = #"[{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","name":"nuc","address":"10.0.0.5","port":2222,"user":"me"}]"#
        let servers = try JSONDecoder().decode([Server].self, from: Data(json.utf8))
        XCTAssertEqual(servers.map(\.pinKey), ["10.0.0.5:2222"])
    }

    func testUnreadableDevicesAreKeptAside() {
        let unreadable = Data("not a device list".utf8)
        UserDefaults.standard.set(unreadable, forKey: "servers")
        XCTAssertEqual(Store().servers, [])
        XCTAssertEqual(UserDefaults.standard.data(forKey: "servers.unreadable"), unreadable)
    }
}
