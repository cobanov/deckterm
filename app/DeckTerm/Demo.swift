import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

/// A host inside the app, for App Review and anyone without a server at hand: Citadel's own SSH server on the
/// loopback, with a small shell and SFTP over a folder in the sandbox. The demo device connects to it like to any
/// other, so the terminal, tabs, splits and Files run their real code; only the machine is made up (herdrchat's Demo).
actor Demo {
    static let shared = Demo()
    static let address = "127.0.0.1"
    /// Fixed, so the device keeps one host key pin. An unusual number: every app on the phone shares the loopback.
    static let port = 22022

    private var server: SSHServer?

    /// Adds the demo device, with a password in the Keychain like any other.
    @MainActor static func add(to store: Store) {
        let device = Server(name: "Demo", address: address, port: port, user: "demo")
        Keychain.set(device.passwordAccount, "demo")
        store.save(device)
    }

    /// Starts the server unless it's up. iOS may close a suspended app's listening socket, so this runs on each connect.
    func serve() async throws {
        guard server == nil else { return }
        let paths = DemoPaths(home: try Self.home())
        let server = try await SSHServer.host(host: Self.address, port: Self.port,
                                              hostKeys: [NIOSSHPrivateKey(ed25519Key: Self.hostKey)],
                                              authenticationDelegate: AnyPassword())
        server.enableShell(withDelegate: DemoShell(paths: paths))
        server.enableSFTP(withDelegate: DemoFiles(paths: paths))
        server.closeFuture.whenComplete { _ in Task { await self.closed() } }
        self.server = server
    }

    private func closed() { server = nil }

    /// From a constant, not random: it only guards a loopback socket, and the pin must hold across reinstalls and restores.
    private static let hostKey = try! Curve25519.Signing.PrivateKey(
        rawRepresentation: Data(SHA256.hash(data: Data("DeckTerm demo host".utf8))))

    /// Seeded once; what someone uploads stays until they delete it.
    private static func home() throws -> URL {
        let home = URL.applicationSupportDirectory.appending(path: "demo-home", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: home.path) { return home }
        try FileManager.default.createDirectory(at: home.appending(path: "project"), withIntermediateDirectories: true)
        try Data(notes.utf8).write(to: home.appending(path: "notes.txt"))
        try Data("# project\n\nA small folder to look around in.\n".utf8).write(to: home.appending(path: "project/README.md"))
        return home
    }

    private static let notes = """
        Notes from the deck.

        - Swipe in from the right edge: snippets, and this host's files.
        - Swipe in from the left edge: back to your devices.
        - Hold and slide on the terminal: arrow keys.
        - Cmd-D splits the screen, Cmd-T opens a new tab.

        """
}

extension Server {
    var isDemo: Bool { address == Demo.address && port == Demo.port }
}

/// Paths as the client writes them, kept inside /home/demo: anything above it is home itself, so nothing outside
/// the sandbox folder can be named.
struct DemoPaths: Sendable {
    static let root = "/home/demo"
    let home: URL

    /// `path` made absolute against `cwd` and normalized, and the file it names.
    func resolve(_ path: String, from cwd: String = root) -> (path: String, url: URL) {
        var parts = path.hasPrefix("/") ? [] : cwd.split(separator: "/").map(String.init)
        for part in path.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(String(part)) }
        }
        guard parts.count >= 2, parts[0] == "home", parts[1] == "demo" else { return (Self.root, home) }
        return ("/" + parts.joined(separator: "/"), parts.dropFirst(2).reduce(home) { $0.appending(path: $1) })
    }
}

/// Any password: the demo device keeps one in the Keychain only because every device does.
private struct AnyPassword: NIOSSHServerUserAuthenticationDelegate {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }

    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        responsePromise.succeed(.success)
    }
}

/// A few commands over the same folder as SFTP, so what Files uploads shows up in `ls`. No programs, no pipes.
/// shortcut: Citadel's server never ends a shell's streams after a disconnect, so each demo shell leaves a parked task
/// until the app quits; fine for a demo, revisit if Citadel fixes ShellServerInboundHandler.
private struct DemoShell: ShellDelegate {
    let paths: DemoPaths

    func startShell(inbound: AsyncStream<ShellClientEvent>, outbound: ShellOutboundWriter, context: SSHShellContext) async throws {
        var line: [UInt8] = [], cwd = DemoPaths.root, out: [UInt8] = []
        var escape = 0, previous: UInt8 = 0  // escape: 1 after ESC, 2 inside a sequence
        func say(_ text: String) { out += Array(text.replacingOccurrences(of: "\n", with: "\r\n").utf8) }
        func prompt() {
            let folder = "~" + cwd.dropFirst(DemoPaths.root.count)
            say("\u{1B}[32mdemo@deckterm\u{1B}[0m:\u{1B}[34m\(folder)\u{1B}[0m$ ")
        }
        say(Self.welcome)
        prompt()
        outbound.write(out)
        for await case .stdin(let buffer) in inbound {
            out = []
            for byte in buffer.readableBytesView {
                defer { previous = byte }
                switch (escape, byte) {
                case (1, 0x5B), (1, 0x4F): escape = 2; continue  // CSI or SS3: arrows and function keys, not handled
                case (1, _), (2, 0x40...0x7E): escape = 0; continue
                case (2, _): continue
                default: break
                }
                switch byte {
                case 0x1B: escape = 1
                case 0x0A where previous == 0x0D: break
                case 0x0D, 0x0A:
                    say("\n")
                    guard run(String(decoding: line, as: UTF8.self), cwd: &cwd, say: say) else {
                        return await end(out, outbound)
                    }
                    line = []
                    prompt()
                case 0x7F, 0x08:
                    guard !line.isEmpty else { break }
                    while line.count > 1, line[line.count - 1] & 0xC0 == 0x80 { line.removeLast() }  // a character's UTF-8 tail
                    line.removeLast()
                    say("\u{8} \u{8}")
                case 0x03:
                    say("^C\n")
                    line = []
                    prompt()
                case 0x04 where line.isEmpty:
                    say("logout\n")
                    return await end(out, outbound)
                case 0x0C:
                    say("\u{1B}[H\u{1B}[2J")
                    prompt()
                    out += line
                case 0x20...:
                    line.append(byte)
                    out.append(byte)
                default:
                    break  // Tab and other control keys: no completion here
                }
            }
            if !out.isEmpty { outbound.write(out) }
        }
    }

    /// Citadel sends output from a task of its own and closes the channel as soon as the shell returns, which dropped
    /// what the last line printed. shortcut: a fixed pause, since Citadel can't be asked whether it has sent it all.
    private func end(_ out: [UInt8], _ outbound: ShellOutboundWriter) async {
        outbound.write(out)
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Returns false when the session should end.
    private func run(_ line: String, cwd: inout String, say: (String) -> Void) -> Bool {
        let words = line.split(separator: " ").map(String.init)
        guard let command = words.first else { return true }
        let args = Array(words.dropFirst())
        let current = cwd
        func resolve(_ arg: String) -> (path: String, url: URL) {
            paths.resolve(arg == "~" || arg.hasPrefix("~/") ? DemoPaths.root + arg.dropFirst() : arg, from: current)
        }
        func isFolder(_ url: URL) -> Bool {
            var folder: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue
        }
        switch command {
        case "help":
            say(Self.help)
        case "ls":
            let target = resolve(args.first ?? ".")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: target.url.path) else {
                let name = args.first ?? "."
                say(FileManager.default.fileExists(atPath: target.url.path) ? name + "\n" : "ls: \(name): No such file or directory\n")
                break
            }
            let shown = names.sorted().map { isFolder(target.url.appending(path: $0)) ? "\u{1B}[1;34m\($0)\u{1B}[0m" : $0 }
            if !shown.isEmpty { say(shown.joined(separator: "  ") + "\n") }
        case "cat":
            if args.isEmpty { say("usage: cat <file>\n") }
            for arg in args {
                let url = resolve(arg).url
                if isFolder(url) {
                    say("cat: \(arg): Is a directory\n")
                } else if let data = FileManager.default.contents(atPath: url.path) {
                    say(String(data: data.prefix(256 << 10), encoding: .utf8) ?? "cat: \(arg): not a text file\n")
                } else {
                    say("cat: \(arg): No such file or directory\n")
                }
            }
        case "cd":
            let target = resolve(args.first ?? "~")
            if isFolder(target.url) { cwd = target.path } else { say("cd: no such folder: \(args.first ?? "~")\n") }
        case "pwd":
            say(cwd + "\n")
        case "echo":
            say(args.joined(separator: " ") + "\n")
        case "whoami":
            say("demo\n")
        case "date":
            say(Date.now.formatted(date: .complete, time: .standard) + "\n")
        case "colors":
            var palette = ""
            for color in 0..<256 {
                palette += "\u{1B}[48;5;\(color)m  "
                // The 16 system colors, the 6×6×6 cube in rows of 36, then the grays.
                if color == 15 || color == 255 || (16...231).contains(color) && (color - 16) % 36 == 35 { palette += "\u{1B}[0m\n" }
            }
            say(palette)
        case "clear":
            say("\u{1B}[H\u{1B}[2J")
        case "exit", "logout":
            say("logout\n")
            return false
        default:
            say("\(command): not on this demo host. Type help for what is.\n")
        }
        return true
    }

    private static let welcome = """
        Welcome to DeckTerm's demo host. It runs inside the app, on this device: nothing goes over the network.
        Type help for its commands. Swipe in from the right edge for snippets and this host's files.

        """

    private static let help = """
        Commands on this demo host:
          ls [folder]    list files (what you upload in Files shows up here)
          cat <file>     print a file
          cd [folder]    change folder
          pwd, whoami, date, echo
          colors         the 256-color palette
          clear          clear the screen, or Ctrl-L
          exit           close the session
        It is a stand-in: add your own server for vim, htop and tmux.

        """
}

/// SFTP over the demo folder. Citadel's server sends no reply when stat, realpath, open or opendir throw, and the
/// client waits for good, so those never throw: a missing file reads as empty, a refused write fails on write.
private struct DemoFiles: SFTPDelegate {
    let paths: DemoPaths

    static func attributes(of url: URL) -> SFTPFileAttributes {
        guard let info = try? FileManager.default.attributesOfItem(atPath: url.path) else { return SFTPFileAttributes() }
        let modified = info[.modificationDate] as? Date ?? .now
        var attributes = SFTPFileAttributes(size: (info[.size] as? NSNumber)?.uint64Value,
                                            accessModificationTime: .init(accessTime: modified, modificationTime: modified))
        attributes.permissions = info[.type] as? FileAttributeType == .typeDirectory ? 0o040755 : 0o100644
        attributes.uidgid = .init(userId: 1000, groupId: 1000)
        return attributes
    }

    private static func isFolder(_ url: URL) -> Bool {
        (attributes(of: url).permissions ?? 0) & 0o170000 == 0o040000
    }

    func fileAttributes(atPath path: String, context: SSHContext) async throws -> SFTPFileAttributes {
        Self.attributes(of: paths.resolve(path).url)
    }

    func openFile(_ filePath: String, withAttributes: SFTPFileAttributes, flags: SFTPOpenFileFlags, context: SSHContext) async throws -> SFTPFileHandle {
        let url = paths.resolve(filePath).url
        guard flags.contains(.write) else { return DemoFile(url: url, writable: false) }
        let exists = FileManager.default.fileExists(atPath: url.path)
        // Exclusive create on a file already there, or a write to one that isn't without create.
        if exists ? flags.contains(.forceCreate) : !flags.contains(.create) { return DemoFile(url: url, writable: false) }
        if !exists || flags.contains(.truncate) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        return DemoFile(url: url, writable: true)
    }

    func removeFile(_ filePath: String, context: SSHContext) async throws -> SFTPStatusCode {
        let url = paths.resolve(filePath).url
        guard !Self.isFolder(url) else { return .failure }
        return (try? FileManager.default.removeItem(at: url)) != nil ? .ok : .noSuchFile
    }

    func createDirectory(_ filePath: String, withAttributes: SFTPFileAttributes, context: SSHContext) async throws -> SFTPStatusCode {
        (try? FileManager.default.createDirectory(at: paths.resolve(filePath).url, withIntermediateDirectories: false)) != nil ? .ok : .failure
    }

    /// rmdir's limits: never home, never a folder with something in it.
    func removeDirectory(_ filePath: String, context: SSHContext) async throws -> SFTPStatusCode {
        let (path, url) = paths.resolve(filePath)
        guard path != DemoPaths.root, Self.isFolder(url),
              (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty == true,
              (try? FileManager.default.removeItem(at: url)) != nil else { return .failure }
        return .ok
    }

    func realPath(for canonicalUrl: String, context: SSHContext) async throws -> [SFTPPathComponent] {
        [SFTPPathComponent(filename: paths.resolve(canonicalUrl).path, longname: "", attributes: SFTPFileAttributes())]
    }

    func openDirectory(atPath path: String, context: SSHContext) async throws -> SFTPDirectoryHandle {
        DemoFolder(url: paths.resolve(path).url)
    }

    func setFileAttributes(to attributes: SFTPFileAttributes, atPath path: String, context: SSHContext) async throws -> SFTPStatusCode { .ok }

    func addSymlink(linkPath: String, targetPath: String, context: SSHContext) async throws -> SFTPStatusCode { .unsupportedOperation }

    func readSymlink(atPath path: String, context: SSHContext) async throws -> [SFTPPathComponent] { [] }

    /// Never over a file already there, as SFTP's rename.
    func rename(oldPath: String, newPath: String, flags: UInt32, context: SSHContext) async throws -> SFTPStatusCode {
        let from = paths.resolve(oldPath), to = paths.resolve(newPath)
        guard from.path != DemoPaths.root, to.path != DemoPaths.root,
              (try? FileManager.default.moveItem(at: from.url, to: to.url)) != nil else { return .failure }
        return .ok
    }
}

private struct DemoFolder: SFTPDirectoryHandle {
    let url: URL

    func listFiles(context: SSHContext) async throws -> [SFTPFileListing] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        if names.isEmpty { return [] }
        return [SFTPFileListing(path: names.map {
            SFTPPathComponent(filename: $0, longname: $0, attributes: DemoFiles.attributes(of: url.appending(path: $0)))
        })]
    }
}

private struct DemoFile: SFTPFileHandle {
    let url: URL
    let writable: Bool

    /// Empty is EOF to the client; a throw would leave it waiting. At most 32 000 bytes, as Citadel's client writes:
    /// a bigger message stalls NIO SSH (apple/swift-nio-ssh#99), and the client asks again from where this ended.
    func read(at offset: UInt64, length: UInt32) async throws -> ByteBuffer {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ByteBuffer() }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.read(upToCount: min(Int(length), 32_000)) else { return ByteBuffer() }
        return ByteBuffer(bytes: data)
    }

    func write(_ data: ByteBuffer, atOffset offset: UInt64) async throws -> SFTPStatusCode {
        guard writable, let handle = try? FileHandle(forWritingTo: url) else { return .failure }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              (try? handle.write(contentsOf: Data(data.readableBytesView))) != nil else { return .failure }
        return .ok
    }

    func close() async throws -> SFTPStatusCode { .ok }

    func readFileAttributes() async throws -> SFTPFileAttributes { DemoFiles.attributes(of: url) }

    func setFileAttributes(to attributes: SFTPFileAttributes) async throws {}
}
