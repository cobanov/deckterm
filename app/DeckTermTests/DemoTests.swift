import XCTest
@testable import DeckTerm

/// The demo host through the app's own Session and SFTP code, as App Review meets it: no network, no Mac sshd.
final class DemoTests: XCTestCase {
    private let demo = Server(name: "Demo", address: Demo.address, port: Demo.port, user: "demo")

    override func setUp() {
        Keychain.set(demo.passwordAccount, "demo")
    }

    override func tearDown() {
        Keychain.set(demo.passwordAccount, nil)
    }

    func testPathsStayInHome() {
        let paths = DemoPaths(home: URL(fileURLWithPath: "/sandbox/demo-home"))
        XCTAssertEqual(paths.resolve(".").path, "/home/demo")
        XCTAssertEqual(paths.resolve("project/../notes.txt").url.path, "/sandbox/demo-home/notes.txt")
        XCTAssertEqual(paths.resolve("README.md", from: "/home/demo/project").path, "/home/demo/project/README.md")
        for outside in ["..", "/", "/etc/passwd", "../../../../etc", "/home/demo/../../x", "/home/demox"] {
            XCTAssertEqual(paths.resolve(outside).url.path, "/sandbox/demo-home", outside)
        }
    }

    func testShellRunsCommandsAndExits() {
        let output = Output()
        let ended = expectation(description: "ended")
        let session = Session()
        session.start(demo, cols: 80, rows: 24, output: { bytes in
            DispatchQueue.main.async { output.text += String(decoding: bytes, as: UTF8.self) }
        }, detected: { _ in }, ended: { message in
            DispatchQueue.main.async {
                output.ended = .some(message)
                ended.fulfill()
            }
        })
        session.send(ArraySlice("ls\rcat notes.txt\rnope\rexit\r".utf8))
        wait(for: [ended], timeout: 20)
        XCTAssertTrue(output.text.contains("notes.txt"), output.text)
        XCTAssertTrue(output.text.contains("Notes from the deck."), output.text)
        XCTAssertTrue(output.text.contains("nope: not on this demo host"), output.text)
        XCTAssertEqual(output.ended, .some(nil), "exit ends the session without a message")
    }

    /// The Files panel's calls: list home, upload, refuse an upload over a file already there, download, delete.
    @MainActor func testFilesRoundTrip() async throws {
        let session = Session()
        session.start(demo, cols: 80, rows: 24, output: { _ in }, detected: { _ in }, ended: { _ in })
        defer { session.close() }
        for _ in 0..<100 where session.client == nil { try await Task.sleep(for: .milliseconds(100)) }
        let files = RemoteFiles { session.client }
        await files.load()
        XCTAssertNil(files.failure)
        XCTAssertEqual(files.path, "/home/demo")
        XCTAssertTrue(files.entries.contains { $0.name == "project" && $0.isFolder })

        let name = "deckterm-test-\(UUID().uuidString)"
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let bytes = Data((0..<600_000).map { UInt8($0 % 251) })
        try bytes.write(to: local)
        await files.upload([local])
        XCTAssertNil(files.failure)
        XCTAssertTrue(files.entries.contains { $0.name == name && $0.attributes.size == UInt64(bytes.count) })
        await files.upload([local])
        XCTAssertNotNil(files.failure, "uploaded over the file already there")

        let entry = try XCTUnwrap(files.entries.first { $0.name == name })
        let back = await files.download(entry)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(back)), bytes)
        await files.delete(entry)
        XCTAssertFalse(files.entries.contains { $0.name == name })
    }

    private final class Output: @unchecked Sendable {
        var text = ""
        var ended: String??
    }
}
