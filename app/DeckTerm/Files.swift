import SwiftUI
import Citadel
import NIOCore

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

    init(connection: @escaping () -> SSHClient?) {
        self.connection = connection
    }

    func child(_ name: String) -> String { path == "/" ? "/" + name : path + "/" + name }

    /// Lists `path`, or the folder already shown, or home the first time.
    func load(_ path: String? = nil) async {
        await run(String(localized: "Loading…")) { sftp in
            let target = try await sftp.getRealPath(atPath: path ?? (self.path.isEmpty ? "." : self.path))
            let names = try await sftp.listDirectory(atPath: target)
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

    /// Into a fresh temporary folder, for the share sheet.
    func download(_ entry: Entry) async -> URL? {
        var saved: URL?
        await run(String(localized: "Downloading \(entry.name)…")) { sftp in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(entry.name)
            try await sftp.download(self.child(entry.name), to: url)
            saved = url
        }
        return saved
    }

    func upload(_ urls: [URL]) async {
        for url in urls {
            let ok = await run(String(localized: "Uploading \(url.lastPathComponent)…")) { sftp in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try await sftp.upload(url, to: self.child(url.lastPathComponent))
            }
            if !ok { break }
        }
        await load()
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
        do {
            try await work(try await client())
            return true
        } catch {
            if case SFTPError.errorStatus(let status) = error, !status.message.isEmpty {
                failure = status.message
            } else {
                failure = error.localizedDescription
            }
            return false
        }
    }

    /// Opened on first use and again after a reconnect.
    private func client() async throws -> SFTPClient {
        if let sftp, sftp.isActive { return sftp }
        guard let connection = connection(), connection.isConnected else {
            throw Session.Failure(errorDescription: String(localized: "Not connected."))
        }
        let sftp = try await connection.openSFTP()
        self.sftp = sftp
        return sftp
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
                icon("chevron.up", "Up") { Task { await files.load(files.path + "/..") } }
                    .disabled(files.path.isEmpty || files.path == "/")
                Text(verbatim: files.path)
                    .font(font.font(11))
                    .foregroundStyle(theme.fg.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                icon("arrow.clockwise", "Refresh") { Task { await files.load() } }
                icon("folder.badge.plus", "New folder") { name = ""; naming = .folder }
                    .disabled(files.path.isEmpty)
                icon("square.and.arrow.up", "Upload") { importing = true }
                    .disabled(files.path.isEmpty)
                icon(corner.symbol, corner.label, corner.action)
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
        .sheet(isPresented: Binding(get: { shared != nil }, set: { if !$0 { shared = nil } })) {
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
                        Text(Int64(size), format: .byteCount(style: .file)).frame(minWidth: wide ? 80 : 0, alignment: .trailing)
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

    private func icon(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 28)
                .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
