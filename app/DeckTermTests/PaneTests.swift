import XCTest
@testable import DeckTerm

final class PaneTests: XCTestCase {
    func testGridFollowsTheLongerSide() {
        let wide = CGRect(x: 0, y: 0, width: 201, height: 101)
        XCTAssertEqual(PaneGrid.frames(1, in: wide), [wide])
        XCTAssertEqual(PaneGrid.frames(2, in: wide), [CGRect(x: 0, y: 0, width: 100, height: 101),
                                                      CGRect(x: 101, y: 0, width: 100, height: 101)])
        XCTAssertEqual(PaneGrid.frames(2, in: CGRect(x: 0, y: 0, width: 101, height: 201)),
                       [CGRect(x: 0, y: 0, width: 101, height: 100), CGRect(x: 0, y: 101, width: 101, height: 100)],
                       "upright, two panes stack")
    }

    func testLaunchWaitsForTheChosenOrientation() {
        defer { UserDefaults.standard.removeObject(forKey: "orientation") }
        UserDefaults.standard.removeObject(forKey: "orientation")
        XCTAssertTrue(Rotation.stands(.landscapeRight, held: .portrait), "landscape by default, however it's held")
        XCTAssertFalse(Rotation.stands(.portrait, held: .portrait))
        UserDefaults.standard.set("portrait", forKey: "orientation")
        XCTAssertFalse(Rotation.stands(.landscapeLeft, held: .landscapeLeft))
        UserDefaults.standard.set("auto", forKey: "orientation")
        XCTAssertFalse(Rotation.stands(.landscapeRight, held: .portrait), "Auto waits for the turn to how it's held")
        XCTAssertTrue(Rotation.stands(.portrait, held: .portrait))
        XCTAssertTrue(Rotation.stands(.landscapeRight, held: .faceUp), "flat on a table: no turn to wait for")
    }

    func testKeyRowsComeOutEven() {
        XCTAssertTrue(KeyRows.shape(12, width: 386) == (2, 6), "12 keys upright: two rows of six, not seven and five")
        XCTAssertTrue(KeyRows.shape(13, width: 386) == (2, 7))
        XCTAssertTrue(KeyRows.shape(5, width: 386) == (1, 5))
        XCTAssertTrue(KeyRows.shape(3, width: 10) == (3, 1), "narrower than one key: one per row")
    }

    @MainActor func testKeyboardFollowsTheSetting() throws {
        defer { UserDefaults.standard.removeObject(forKey: "keyboardShown") }
        let sessions = Sessions()
        sessions.show(Server(address: "127.0.0.1", port: 1, user: "nobody"))
        let terminal = try XCTUnwrap(sessions.active).terminal
        UserDefaults.standard.set(false, forKey: "keyboardShown")
        terminal.tookKeys()
        XCTAssertFalse(sessions.keyboardUp, "off: only the bar's key raises it")
        UserDefaults.standard.set(true, forKey: "keyboardShown")
        sessions.keyboardUp = false  // put away with the bar's key
        terminal.tookKeys()
        XCTAssertTrue(sessions.keyboardUp, "on: a tap or a new pane brings it back")
        sessions.sync([])
    }

    /// A dropped connection keeps its pane, for Enter, but no longer keeps the app running in the background.
    @MainActor func testOnlyLiveConnectionsKeepTheAppRunning() async throws {
        let sessions = Sessions()
        sessions.show(Server(name: "refused", address: "127.0.0.1", port: 1, user: "nobody"))
        XCTAssertEqual(sessions.alive, ["refused"], "connecting counts")
        for _ in 0..<50 where !sessions.alive.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(sessions.alive, [])
        XCTAssertEqual(sessions.open.count, 1, "the pane stays")
        sessions.sync([])
    }

    /// Port 1 refuses at once: the panes stay open with an error, and nothing logs in.
    @MainActor func testTabsAndPanes() throws {
        let sessions = Sessions()
        let server = Server(address: "127.0.0.1", port: 1, user: "nobody")
        sessions.show(server)
        let first = try XCTUnwrap(sessions.active)
        sessions.split(server)
        let second = try XCTUnwrap(sessions.active)
        sessions.newTab(server)
        let third = try XCTUnwrap(sessions.active)
        XCTAssertEqual(sessions.tabs.map { $0.panes.map(\.id) }, [[first.id, second.id], [third.id]])

        sessions.cycle(1)
        XCTAssertTrue(sessions.active === first, "past the last pane, back to the first tab")
        sessions.cycle(-1)
        XCTAssertTrue(sessions.active === third)
        sessions.show(server)
        XCTAssertTrue(sessions.active === first, "the device's card opens its first session")

        sessions.split(server)
        XCTAssertEqual(sessions.tabs.map(\.panes.count), [2, 1, 1], "a full tab overflows into a new one")
        sessions.split(server, beside: third)
        XCTAssertEqual(sessions.tabs.map(\.panes.count), [2, 2, 1], "beside a named pane, in its tab")

        sessions.active = second
        sessions.close(second)
        XCTAssertTrue(sessions.active === first, "the keys go to the pane beside")
        sessions.close(third)
        XCTAssertEqual(sessions.tabs.map(\.panes.count), [1, 1, 1])
        sessions.sync([])
        XCTAssertTrue(sessions.tabs.isEmpty, "a deleted device hangs up all its sessions")
        XCTAssertNil(sessions.active)
    }
}
