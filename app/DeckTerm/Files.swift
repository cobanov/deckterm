import SwiftUI
import Citadel
import NIOCore
import os

/// The session's host over SFTP, on the connection its shell already has: no second login, and it ends with the shell.
/// The panel and the full screen show the same one, so both stay in the same folder.
@MainActor final class RemoteFiles: ObservableObject {
    struct Entry: Identifiable {
        let name: String
        let attributes: SFTPFileAttributes
        var id: String { name }
        var isFolder: Bool { attributes.isFolder }
        var isLink: Bool { (attributes.permissions ?? 0) & 0o170000 == 0o120000 }
    }

    /// Empty until the first listing finds the home folder.
    @Published private(set) var path = ""
    @Published private(set) var entries: [Entry] = []
    /// What's under way; one thing at a time.
    @Published private(set) var busy: String?
    @Published var failure: String?
    private let connection: () -> SSHClient?
    private var sftp: SFTPClient?
    /// shortcut: Citadel 0.12.1 never closes a folder it lists, and sftp-server holds a file open for each (256 on a
    /// Mac), so every 100th listing closes the channel for a fresh one; drop this once Citadel closes the handle.
    private var listings = 0

    init(connection: @escaping () -> SSHClient?) {
        self.connection = connection
    }

    func child(_ name: String) -> String { path == "/" ? "/" + name : path + "/" + name }

    /// Lists `path`, or the folder already shown, or home the first time.
    func load(_ path: String? = nil) async {
        await run(String(localized: "Loading…")) { sftp in
            let target = try await sftp.getRealPath(atPath: path ?? (self.path.isEmpty ? "." : self.path))
            let names = try await sftp.listDirectory(atPath: target)
            self.listings += 1
            if self.listings % 100 == 0 { try? await sftp.close() }
            self.path = target
            self.entries = names.flatMap(\.components)
                .filter { $0.filename != "." && $0.filename != ".." }
                .map { Entry(name: $0.filename, attributes: $0.attributes) }
                .sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
            self.failure = nil
        }
    }

    /// A link counts as what it points to.
    func isFolder(_ entry: Entry) async -> Bool {
        guard entry.isLink else { return entry.isFolder }
        return (try? await client().getAttributes(at: child(entry.name)))?.isFolder ?? false
    }

    /// Where a host's file lands in `folder`. The name is the host's word: one with a "/" (`../../Library/x`) wrote
    /// outside the folder, and the share sheet's cleanup then deleted the folder it landed in.
    nonisolated static func local(_ name: String, in folder: URL) -> URL {
        folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_"))
    }

    /// Into a fresh temporary folder, for the share sheet, which deletes it when it closes.
    func download(_ entry: Entry) async -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = Self.local(entry.name, in: folder)
        if await run(String(localized: "Downloading \(entry.name)…"), { sftp in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await sftp.download(self.child(entry.name), to: url)
        }) {
            return url
        }
        try? FileManager.default.removeItem(at: folder)  // what a failed download left
        return nil
    }

    func upload(_ urls: [URL]) async {
        var refused: String?
        for url in urls {
            let ok = await run(String(localized: "Uploading \(url.lastPathComponent)…")) { sftp in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try await sftp.upload(url, to: self.child(url.lastPathComponent))
            }
            if !ok {
                refused = failure
                break
            }
        }
        await load()  // what went up before a refusal shows; the listing clears `failure`, so the reason goes back
        if let refused { failure = refused }
    }

    func makeFolder(_ name: String) async {
        if await run(String(localized: "Creating \(name)…"), { try await $0.createDirectory(atPath: self.child(name)) }) {
            await load()
        }
    }

    /// SFTP's rename fails rather than replace a file already there.
    func rename(_ entry: Entry, to name: String) async {
        if await run(String(localized: "Renaming \(entry.name)…"), {
            try await $0.rename(at: self.child(entry.name), to: self.child(name))
        }) {
            await load()
        }
    }

    /// A folder only when it's empty: SFTP has no recursive delete, and that's a safe limit to keep.
    func delete(_ entry: Entry) async {
        if await run(String(localized: "Deleting \(entry.name)…"), { sftp in
            if entry.isFolder { try await sftp.rmdir(at: self.child(entry.name)) } else { try await sftp.remove(at: self.child(entry.name)) }
        }) {
            await load()
        }
    }

    /// False when it failed, with the reason in `failure`, or when something else was still under way.
    @discardableResult
    private func run(_ label: String, _ work: (SFTPClient) async throws -> Void) async -> Bool {
        guard busy == nil else { return false }
        busy = label
        defer { busy = nil }
        // A refusal comes bare or wrapped; its message is the server's own ("Permission denied"), NSError's isn't.
        do {
            try await work(try await client())
            return true
        } catch let status as SFTPMessage.Status where !status.message.isEmpty {
            failure = status.message
        } catch SFTPError.errorStatus(let status) where !status.message.isEmpty {
            failure = status.message
        } catch {
            failure = error.localizedDescription
        }
        return false
    }

    /// Opened on first use and again after a reconnect.
    private func client() async throws -> SFTPClient {
        if let sftp, sftp.isActive { return sftp }
        guard let connection = connection(), connection.isConnected else {
            throw Session.Failure(errorDescription: String(localized: "Not connected."))
        }
        let sftp = try await Self.open(connection)
        self.sftp = sftp
        return sftp
    }

    /// Citadel waits for ever on a host without SFTP (no `Subsystem sftp` in its sshd): the refusal comes back as an
    /// event it never reads, and the panel said "Loading…" for good. Its own wait ends with the connection.
    private static func open(_ connection: SSHClient) async throws -> SFTPClient {
        let pending = OSAllocatedUnfairLock<CheckedContinuation<SFTPClient, Error>?>(initialState: nil)
        @Sendable func finish(_ result: Result<SFTPClient, Error>) -> Bool {
            guard let continuation = pending.withLock({ state in defer { state = nil }; return state }) else { return false }
            continuation.resume(with: result)
            return true
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending.withLock { $0 = continuation }
            Task {
                do {
                    let sftp = try await connection.openSFTP()
                    if !finish(.success(sftp)) { try? await sftp.close() }  // too late: the panel already said so
                } catch {
                    _ = finish(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(15))
                _ = finish(.failure(Session.Failure(errorDescription: String(localized: "The host didn't open SFTP. Its sshd may not offer it: OpenSSH needs a Subsystem sftp line."))))
            }
        }
    }
}

extension SFTPFileAttributes {
    var isFolder: Bool { (permissions ?? 0) & 0o170000 == 0o040000 }
}

extension SFTPClient {
    /// In pieces, so a big file never sits in memory whole.
    func download(_ path: String, to url: URL) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        try await withFile(filePath: path, flags: .read) { file in
            var offset: UInt64 = 0
            while true {
                let piece = try await file.read(from: offset, length: 1 << 18)
                if piece.readableBytes == 0 { return }
                try output.write(contentsOf: Data(piece.readableBytesView))
                offset += UInt64(piece.readableBytes)
            }
        }
    }

    /// Never over a file already there: the exclusive create fails instead.
    func upload(_ url: URL, to path: String) async throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        try await withFile(filePath: path, flags: [.write, .create, .forceCreate]) { file in
            var offset: UInt64 = 0
            while let data = try input.read(upToCount: 1 << 18), !data.isEmpty {
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
            }
        }
    }
}

/// The host's files. Tap a folder to open it, a file to save or share it; hold one to rename or delete it.
struct FilesView: View {
    private enum Naming {
        case folder, rename(RemoteFiles.Entry)
    }

    @ObservedObject var files: RemoteFiles
    let live: Bool
    let theme: Theme
    let font: TermFont
    /// The panel's way to the full screen, or the full screen's way back.
    let corner: (symbol: String, label: LocalizedStringKey, action: () -> Void)
    var wide = false
    @State private var importing = false
    @State private var shared: URL?
    @State private var naming: Naming?
    @State private var name = ""
    @State private var deleting: RemoteFiles.Entry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // Off while something is under way, as the rows are: RemoteFiles does one thing at a time and
                // drops what comes meanwhile, so an upload picked during a download went nowhere, unsaid.
                IconKey("chevron.up", "Up", theme: theme) { Task { await files.load(files.path + "/..") } }
                    .disabled(files.path.isEmpty || files.path == "/" || files.busy != nil)
                Text(verbatim: files.path)
                    .font(font.font(11))
                    .foregroundStyle(theme.fg.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                IconKey("arrow.clockwise", "Refresh", theme: theme) { Task { await files.load() } }
                    .disabled(files.busy != nil)
                IconKey("folder.badge.plus", "New folder", theme: theme) { name = ""; naming = .folder }
                    .disabled(files.path.isEmpty || files.busy != nil)
                IconKey("square.and.arrow.up", "Upload", theme: theme) { importing = true }
                    .disabled(files.path.isEmpty || files.busy != nil)
                IconKey(corner.symbol, corner.label, theme: theme, action: corner.action)
            }
            if let failure = files.failure {
                Text(verbatim: failure)
                    .font(font.font(12))
                    .foregroundStyle(theme.ansiColor(9))
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(files.entries) { row($0) }
                }
            }
            .scrollIndicators(.hidden)
            if let busy = files.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: busy).font(font.font(11)).lineLimit(1)
                }
                .foregroundStyle(theme.fg.opacity(0.55))
            } else {
                Text("Tap: open or save · Hold: rename or delete")
                    .font(font.font(10))
                    .foregroundStyle(theme.fg.opacity(0.45))
            }
        }
        // The first listing waits for the shell's connection.
        .task(id: live) { if live && files.path.isEmpty { await files.load() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await files.upload(urls) } }
        }
        .sheet(isPresented: Binding(get: { shared != nil }, set: { if !$0 { discard() } })) {
            if let shared { ShareSheet(url: shared).presentationDetents([.medium, .large]) }
        }
        .alert(naming.map { if case .rename = $0 { "Rename" } else { "New folder" } } ?? "",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save", action: commitName)
        }
        .confirmationDialog(Text(verbatim: deleting?.name ?? ""),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { entry in
            Button("Delete", role: .destructive) { Task { await files.delete(entry) } }
        } message: { entry in
            entry.isFolder ? Text("Only an empty folder can be deleted.") : Text("This can't be undone.")
        }
    }

    private func row(_ entry: RemoteFiles.Entry) -> some View {
        Button { open(entry) } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.isFolder ? "folder.fill" : entry.isLink ? "link" : "doc")
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(entry.isFolder ? theme.accent : theme.fg.opacity(0.55))
                Text(verbatim: entry.name).font(font.font(13)).lineLimit(1)
                Spacer(minLength: 4)
                Group {
                    if wide, let modified = entry.attributes.accessModificationTime?.modificationTime {
                        Text(modified, format: .dateTime.year().month().day().hour().minute())
                    }
                    if !entry.isFolder, let size = entry.attributes.size {
                        // Clamped: SFTP's size is unsigned, and one past Int64.max from the host stopped the app.
                        Text(Int64(clamping: size), format: .byteCount(style: .file)).frame(minWidth: wide ? 80 : 0, alignment: .trailing)
                    }
                }
                .font(font.font(10))
                .foregroundStyle(theme.fg.opacity(0.45))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(files.busy != nil)
        .contextMenu {
            if !entry.isFolder {
                Button("Save or share", systemImage: "square.and.arrow.down") { save(entry) }
            }
            Button("Rename", systemImage: "pencil") { name = entry.name; naming = .rename(entry) }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
        }
    }

    private func open(_ entry: RemoteFiles.Entry) {
        Task {
            if await files.isFolder(entry) { await files.load(files.child(entry.name)) } else { save(entry) }
        }
    }

    private func save(_ entry: RemoteFiles.Entry) {
        Task { shared = await files.download(entry) }
    }

    /// The downloaded copy goes when the share sheet closes; whatever it was shared to has its own by then.
    private func discard() {
        if let shared { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        shared = nil
    }

    private func commitName() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), let naming else { return }
        Task {
            switch naming {
            case .folder: await files.makeFolder(name)
            case .rename(let entry) where entry.name != name: await files.rename(entry, to: name)
            case .rename: break
            }
        }
    }
}

/// The files with room for dates, over the terminal.
struct FilesScreen: View {
    @ObservedObject var model: TerminalModel
    let theme: Theme
    let font: TermFont
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SystemMark(system: model.server.system, font: font, size: 15)
                    .foregroundStyle(model.state.color(theme))
                Text(verbatim: model.server.title).font(font.font(15, bold: true)).lineLimit(1)
            }
            FilesView(files: model.files, live: model.state == .live, theme: theme, font: font,
                      corner: ("arrow.down.right.and.arrow.up.left", "Back to the terminal", close), wide: true)
        }
        .padding()
        .foregroundStyle(theme.fg)
        .background(theme.bg.ignoresSafeArea())
        .tint(theme.accent)
    }
}

/// Save to Files, AirDrop, or another app.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
