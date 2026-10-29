import XCTest
@testable import DeckTerm

/// A backup carried to a phone that already has a pin of its own. Runs in the app's own UserDefaults, next to its
/// real devices, so it uses addresses of its own and puts every key back.
final class BackupTests: XCTestCase {
    private let keys = ["servers", "pins", "theme", "font", "fontSize", "snippets"]
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
        XCTAssertEqual(Pins.get(nuc.pinKey), "SHA256:here")
        XCTAssertEqual(Pins.get("10.9.9.2:22"), "SHA256:new")
        XCTAssertEqual(defaults.string(forKey: "theme"), "nord")
        XCTAssertEqual(defaults.double(forKey: "fontSize"), 32)
        XCTAssertEqual(defaults.string(forKey: "snippets"), "htop\ndf -h")
    }
}
