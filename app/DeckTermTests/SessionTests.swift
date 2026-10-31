import XCTest
@testable import DeckTerm

/// Logs into this Mac's own sshd from the simulator with the Mac's key, through the app's Session.
final class SessionTests: XCTestCase {
    private final class Output: @unchecked Sendable {
        var text = ""
        var system: String?
        var ended: String??
    }

    private var server = Server(address: "127.0.0.1")

    override func setUpWithError() throws {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"],
              let pem = try? String(contentsOfFile: home + "/.ssh/id_ed25519") else {
            throw XCTSkip("Needs the simulator, the Mac's ~/.ssh/id_ed25519 and Remote Login on.")
        }
        server.user = URL(fileURLWithPath: home).lastPathComponent
        XCTAssertTrue(Keychain.set("privateKey", pem))
        Keychain.set("passphrase", nil)
        Pins.set(server.pinKey, nil)
    }

    private func run(until done: @escaping (Output) -> Bool, then: (Session) -> Void = { _ in }) -> Output {
        let output = Output()
        let finished = expectation(description: "session")
        finished.assertForOverFulfill = false
        let session = Session()
        session.start(server, cols: 80, rows: 24, output: { bytes in
            DispatchQueue.main.async {
                output.text += String(decoding: bytes, as: UTF8.self)
                if done(output) { finished.fulfill() }
            }
        }, detected: { system in
            DispatchQueue.main.async {
                output.system = system
                if done(output) { finished.fulfill() }
            }
        }, ended: { message in
            DispatchQueue.main.async {
                output.ended = .some(message)
                finished.fulfill()
            }
        })
        then(session)
        wait(for: [finished], timeout: 20)
        return output
    }

    func testShellRunsAndExitsCleanly() {
        // $((6*7)) shows the shell ran the line, not just echoed what was typed.
        let shell = run(until: { $0.text.contains("deckterm 42") && $0.system != nil }) {
            $0.send(ArraySlice("echo deckterm $((6*7))\r".utf8))
        }
        XCTAssertTrue(shell.text.contains("deckterm 42"), shell.text)
        XCTAssertEqual(shell.system, "macos", "the Mac's own sshd answers uname with Darwin")
        XCTAssertTrue(Pins.get(server.pinKey)?.hasPrefix("SHA256:") == true)

        let exit = run(until: { _ in false }) { $0.send(ArraySlice("exit\r".utf8)) }
        XCTAssertEqual(exit.ended, .some(nil), "exit on a live connection ends without a message")
    }

    func testChangedHostKeyIsRefused() {
        Pins.set(server.pinKey, "SHA256:not-this-host")
        let refused = run(until: { _ in false })
        XCTAssertTrue(refused.ended??.contains("SHA256:") == true, "shows the key the server presented: \(String(describing: refused.ended))")
        XCTAssertEqual(Pins.get(server.pinKey), "SHA256:not-this-host", "a mismatch must not overwrite the pin")
    }

    /// A session whose connection is up, for SFTP beside the shell.
    @MainActor private func connected() async throws -> Session {
        let session = Session()
        session.start(server, cols: 80, rows: 24, output: { _ in }, detected: { _ in }, ended: { _ in })
        for _ in 0..<100 where session.client == nil { try await Task.sleep(for: .milliseconds(100)) }
        _ = try XCTUnwrap(session.client)
        return session
    }

    /// Up and back down over the shell's own connection, in more than one piece, and never over a file already there.
    @MainActor func testFilesRoundTrip() async throws {
        let session = try await connected()
        defer { session.close() }
        let sftp = try await XCTUnwrap(session.client).openSFTP()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data((0..<600_000).map { UInt8($0 % 251) })
        try bytes.write(to: local)
        let remote = try await sftp.getRealPath(atPath: ".") + "/deckterm-test-\(UUID().uuidString)"

        try await sftp.upload(local, to: remote)
        do {
            try await sftp.upload(local, to: remote)
            XCTFail("uploaded over the file already there")
        } catch {}
        try await sftp.download(remote, to: local.appendingPathExtension("back"))
        try await sftp.remove(at: remote)
        XCTAssertEqual(try Data(contentsOf: local.appendingPathExtension("back")), bytes)
    }

    /// Citadel leaves every listed folder open, and sftp-server holds a file for each (256 on a Mac): a long session
    /// lists more than that.
    @MainActor func testManyListingsKeepWorking() async throws {
        let session = try await connected()
        defer { session.close() }
        let files = RemoteFiles { session.client }
        for _ in 0..<300 { await files.load() }
        XCTAssertNil(files.failure)
        XCTAssertFalse(files.entries.isEmpty)
    }
}
