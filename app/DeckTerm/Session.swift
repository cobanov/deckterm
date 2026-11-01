import Foundation
import Citadel
import Crypto
import NIOCore
import NIOPosix
import NIOSSH

/// One SSH shell in a PTY. The connection handling follows herdrchat's SshConnection and SshShell,
/// which earned it in the field.
final class Session: @unchecked Sendable {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private enum Event {
        case data([UInt8])
        case resize(cols: Int, rows: Int)
        /// The size again, unchanged: traffic on an idle connection, see `heartbeat`.
        case heartbeat
    }

    /// Citadel sends no keepalive and keeps its socket to itself, so a NAT that dropped an idle connection left the
    /// pane green and dead for good. Every minute the PTY's size goes out again: it keeps the NAT's mapping open, and on
    /// a link already gone the write makes the socket fail, which ends the session. The same size changes nothing on
    /// the host (no SIGWINCH).
    private static let heartbeat = Duration.seconds(60)

    private let events: AsyncStream<Event>
    private let input: AsyncStream<Event>.Continuation
    private var task: Task<Void, Never>?
    /// The connection while the shell is open, for SFTP beside it. Set and read on the main thread.
    private(set) var client: SSHClient?

    init() {
        (events, input) = AsyncStream.makeStream()
    }

    /// Queued until the shell is open, so keys and resizes sent while connecting are not lost.
    func send(_ bytes: ArraySlice<UInt8>) { input.yield(.data(Array(bytes))) }
    func resize(cols: Int, rows: Int) { input.yield(.resize(cols: cols, rows: rows)) }

    /// Hang up. Reports nothing: closing is the app's own doing.
    func close() {
        input.finish()
        task?.cancel()
    }

    /// `output` gets the shell's raw bytes. `ended` fires once, off the main thread: nil when the shell
    /// exited on a live connection (the person typed `exit`), else what went wrong. `detected` gets the host's logo name.
    func start(_ server: Server, cols: Int, rows: Int,
               output: @escaping @Sendable (ArraySlice<UInt8>) -> Void,
               detected: @escaping @Sendable (String) -> Void,
               ended: @escaping @Sendable (String?) -> Void) {
        let events = self.events, input = self.input
        task = Task {
            let validator = PinValidator(pinKey: server.pinKey)
            // A group per connection: Citadel never closes the socket of a failed handshake, and shutting
            // the group down is the only handle on it. Left open, sshd starts refusing the phone.
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            do {
                if server.isDemo { try await Demo.shared.serve() }
                let auth = try Self.auth(for: server)
                var settings = SSHClientSettings(
                    host: server.address,
                    port: server.port,
                    authenticationMethod: { auth },
                    hostKeyValidator: .custom(validator)
                )
                settings.group = group
                let client = try await SSHClient.connect(to: settings)
                await MainActor.run { self.client = client }
                let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: max(cols, 1),
                    terminalRowHeight: max(rows, 1),
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )
                do {
                    try await client.withPTY(pty) { inbound, outbound in
                        // Once the shell has its channel: a host allowing one per connection would refuse it otherwise.
                        Task { if let system = await Self.system(of: client) { detected(system) } }
                        try await withThrowingTaskGroup(of: Void.self) { tasks in
                            tasks.addTask {
                                var size = (cols: max(cols, 1), rows: max(rows, 1))
                                for await event in events {
                                    switch event {
                                    case .data(let bytes):
                                        try await outbound.write(ByteBuffer(bytes: bytes))
                                    case .resize(let cols, let rows):
                                        size = (cols, rows)
                                        try await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
                                    case .heartbeat:
                                        try await outbound.changeSize(cols: size.cols, rows: size.rows, pixelWidth: 0, pixelHeight: 0)
                                    }
                                }
                            }
                            // Not to Windows: its ConPTY may repaint the screen on any resize, even to the same size.
                            if server.system != "windows" {
                                tasks.addTask {
                                    while true {
                                        try await Task.sleep(for: Self.heartbeat)
                                        input.yield(.heartbeat)
                                    }
                                }
                            }
                            defer { tasks.cancelAll() }
                            do {
                                for try await chunk in inbound {
                                    switch chunk {
                                    case .stdout(let buffer), .stderr(let buffer):
                                        output(ArraySlice(buffer.readableBytesView))
                                    }
                                }
                            } catch is SSHClient.CommandFailed {
                                // A non-zero exit status is still the shell ending on its own.
                            }
                        }
                    }
                } catch ChannelError.alreadyClosed {
                    // The host closed the channel first; withPTY's own close after it is not news.
                }
                let live = client.isConnected
                await MainActor.run { self.client = nil }
                try? await client.close()
                if !Task.isCancelled { ended(live ? nil : String(localized: "Connection lost.")) }
            } catch {
                await MainActor.run { self.client = nil }
                if !Task.isCancelled { ended(Self.describe(error, presented: validator.presented)) }
            }
            try? await group.shutdownGracefully()
        }
    }

    /// What the host runs, from one short command beside the shell. It ends with the connection at the latest.
    private static func system(of client: SSHClient) async -> String? {
        var output = ""
        do {
            for try await chunk in try await client.executeCommandStream("uname -s; cat /etc/os-release") {
                switch chunk {
                case .stdout(let buffer), .stderr(let buffer): output += String(buffer: buffer)
                }
                if output.utf8.count > 16_384 { break }
            }
        } catch {
            // A non-zero exit (a Mac has no os-release, Windows no uname) still leaves its output.
        }
        return Server.system(from: output)
    }

    static func auth(for server: Server) throws -> SSHAuthenticationMethod {
        if let password = Keychain.get(server.passwordAccount) {
            return .passwordBased(username: server.user, password: password)
        }
        guard let pem = Keychain.get("privateKey") else {
            throw Failure(errorDescription: String(localized: "No private key: add one under SSH key in this device's form, or give the device a password."))
        }
        return try keyAuth(user: server.user, pem: pem, passphrase: Keychain.get("passphrase"))
    }

    /// ed25519 only: Citadel signs with RSA through SHA-1, which OpenSSH 8.8 and later refuse, so an RSA key is
    /// named here rather than failing every login. The key form calls this to check a pasted key.
    static func keyAuth(user: String, pem: String, passphrase: String?) throws -> SSHAuthenticationMethod {
        if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: passphrase.map { Data($0.utf8) }) {
            return .ed25519(username: user, privateKey: key)
        }
        if (try? SSHKeyDetection.detectPrivateKeyType(from: pem)) == .rsa {
            throw Failure(errorDescription: String(localized: "DeckTerm can't use RSA keys: it would sign with SHA-1, which OpenSSH 8.8 and later refuse. Make an ed25519 key with `ssh-keygen -t ed25519` and add its public half to each server."))
        }
        throw Failure(errorDescription: String(localized: "Couldn't read the key. Paste an ed25519 key in OpenSSH format with its BEGIN and END lines, and its passphrase if it has one."))
    }

    private static func describe(_ error: Error, presented: String?) -> String {
        if let presented {
            return String(localized: "Host key changed! The server presented \(presented). If you expected this, edit the device → Forget host key.")
        }
        let text = String(describing: error)
        if text.contains("authenticationFailed") || text.contains("allAuthenticationOptionsFailed") {
            return String(localized: "The server refused the login: check the user, the key or the password.")
        }
        return error.localizedDescription
    }
}

/// Trust on first use: pin the host key's fingerprint on first contact, refuse a different key later.
private final class PinValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let pinKey: String
    /// Set during the handshake on a mismatch, read after connect throws.
    var presented: String?

    init(pinKey: String) {
        self.pinKey = pinKey
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBuffer()
        _ = hostKey.write(to: &buffer)
        // What `ssh-keygen -lf` prints: unpadded base64 of SHA-256 over the key's wire encoding.
        let digest = Data(SHA256.hash(data: Data(buffer.readableBytesView))).base64EncodedString()
        let fingerprint = "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
        // On the main thread, with every other use of the pins: each connection has a thread of its own, and two
        // first handshakes at once each wrote back the whole set, so one pin was lost.
        DispatchQueue.main.async { [self] in
            if let pinned = Pins.get(pinKey), pinned != fingerprint {
                presented = fingerprint
                validationCompletePromise.fail(Session.Failure(errorDescription: "host key mismatch"))
                return
            }
            Pins.set(pinKey, fingerprint)
            validationCompletePromise.succeed(())
        }
    }
}
