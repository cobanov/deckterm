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
    }

    private let events: AsyncStream<Event>
    private let input: AsyncStream<Event>.Continuation
    private var task: Task<Void, Never>?

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
    /// exited on a live connection (the person typed `exit`), else what went wrong.
    func start(_ server: Server, cols: Int, rows: Int,
               output: @escaping @Sendable (ArraySlice<UInt8>) -> Void,
               ended: @escaping @Sendable (String?) -> Void) {
        let events = self.events
        task = Task {
            let validator = PinValidator(pinKey: server.pinKey)
            // A group per connection: Citadel never closes the socket of a failed handshake, and shutting
            // the group down is the only handle on it. Left open, sshd starts refusing the phone.
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            do {
                let auth = try Self.auth(for: server)
                var settings = SSHClientSettings(
                    host: server.address,
                    port: server.port,
                    authenticationMethod: { auth },
                    hostKeyValidator: .custom(validator)
                )
                settings.group = group
                let client = try await SSHClient.connect(to: settings)
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
                        try await withThrowingTaskGroup(of: Void.self) { tasks in
                            tasks.addTask {
                                for await event in events {
                                    switch event {
                                    case .data(let bytes):
                                        try await outbound.write(ByteBuffer(bytes: bytes))
                                    case .resize(let cols, let rows):
                                        try await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
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
                try? await client.close()
                if !Task.isCancelled { ended(live ? nil : "Bağlantı koptu.") }
            } catch {
                if !Task.isCancelled { ended(Self.describe(error, presented: validator.presented)) }
            }
            try? await group.shutdownGracefully()
        }
    }

    static func auth(for server: Server) throws -> SSHAuthenticationMethod {
        if let password = Keychain.get(server.passwordAccount) {
            return .passwordBased(username: server.user, password: password)
        }
        guard let pem = Keychain.get("privateKey") else {
            throw Failure(errorDescription: "Özel anahtar yok: listedeki anahtar düğmesiyle ekle ya da bu sunucuya parola gir.")
        }
        return try keyAuth(user: server.user, pem: pem, passphrase: Keychain.get("passphrase"))
    }

    /// ed25519 first, RSA for older keys. The key form calls this to check a pasted key.
    static func keyAuth(user: String, pem: String, passphrase: String?) throws -> SSHAuthenticationMethod {
        let decryptionKey = passphrase.map { Data($0.utf8) }
        if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decryptionKey) {
            return .ed25519(username: user, privateKey: key)
        }
        return .rsa(username: user, privateKey: try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryptionKey))
    }

    private static func describe(_ error: Error, presented: String?) -> String {
        if let presented {
            return "Host anahtarı değişti! Sunucunun sunduğu: \(presented). Değişikliği biliyorsan sunucuyu düzenle → Host anahtarını unut."
        }
        let text = String(describing: error)
        if text.contains("authenticationFailed") || text.contains("allAuthenticationOptionsFailed") {
            return "Sunucu girişi reddetti: kullanıcıyı, anahtarı ya da parolayı kontrol et."
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
        if let pinned = Pins.get(pinKey), pinned != fingerprint {
            presented = fingerprint
            validationCompletePromise.fail(Session.Failure(errorDescription: "host key mismatch"))
            return
        }
        Pins.set(pinKey, fingerprint)
        validationCompletePromise.succeed(())
    }
}
