import SwiftUI
import StoreKit

@main
struct DeckTermApp: App {
    init() {
        TermFont.register()
        // Tips that complete outside the tip jar (Ask to Buy, an interrupted purchase) arrive here; finished, they stop coming back.
        Task.detached {
            for await case .verified(let transaction) in Transaction.updates { await transaction.finish() }
        }
    }

    var body: some Scene {
        WindowGroup {
            ServerList()
                .preferredColorScheme(.dark)
                .fontDesign(.monospaced)  // system text (forms, menus) in SF Mono, next to the chosen face
        }
    }
}

/// The devices as cards, a grid for the landscape screen. ⌘1–9 opens one, ⌘N adds one.
struct ServerList: View {
    @StateObject private var store = Store()
    @AppStorage("welcomed") private var welcomed = false
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("font") private var font = TermFont.jetBrains
    @State private var editing: Server?
    @State private var connected: Server?
    @State private var keyShown = false
    @State private var importing = false
    @State private var aboutShown = false
    @State private var notice: String?

    var body: some View {
        Group {
            if welcomed {
                list
            } else {
                WelcomeScreen(addDevice: { welcomed = true; editing = Server() },
                              addKey: { keyShown = true },
                              restore: { importing = true },
                              skip: { welcomed = true })
            }
        }
        .tint(theme.accent)
        .sheet(item: $editing) { ServerForm(server: $0, store: store) }
        .sheet(isPresented: $keyShown) { KeyForm() }
        .sheet(isPresented: $aboutShown) { AboutSheet() }
        .fullScreenCover(item: $connected) { TerminalScreen(server: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: restore)
        .alert("Backup", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
        } message: {
            Text(notice ?? "")
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let count = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: url)).restore(into: store)
            welcomed = true
            notice = String(localized: "Restored \(count) devices and your settings. Passwords and the SSH key are not in backups: paste the key once.")
        } catch {
            notice = String(localized: "Couldn't read the backup: \(error.localizedDescription)")
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Mark(theme: theme, font: font, size: 28)
                Text(verbatim: "deckterm").font(font.font(18, bold: true))
                Spacer()
                Menu {
                    ShareLink(item: Backup(store), preview: SharePreview("DeckTerm backup")) {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    Button("Restore from backup", systemImage: "square.and.arrow.down") { importing = true }
                    Divider()
                    Button("About DeckTerm", systemImage: "info.circle") { aboutShown = true }
                } label: {
                    headerIcon("ellipsis")
                }
                .accessibilityLabel("More")
                headerButton("key", "SSH key") { keyShown = true }
                headerButton("plus", "Add a device") { editing = Server() }
                    .keyboardShortcut(shortcut("n"))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            if store.servers.isEmpty {
                VStack(spacing: 10) {
                    Text("No devices yet").font(font.font(15, bold: true))
                    Text("Add an SSH server, then tap it to open its terminal.")
                        .font(font.font(12))
                        .foregroundStyle(theme.fg.opacity(0.55))
                    Button { editing = Server() } label: { Label("Add a device", systemImage: "plus") }
                        .buttonStyle(PillStyle(theme: theme, font: font, primary: true))
                        .frame(width: 220)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                        ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                            card(server, index: index)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
        .foregroundStyle(theme.fg)
        .background(theme.bg.ignoresSafeArea())
    }

    private func card(_ server: Server, index: Int) -> some View {
        Button { connected = server } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(verbatim: ">").font(font.font(15, bold: true)).foregroundStyle(theme.accent).accessibilityHidden(true)
                    Text(verbatim: server.title).font(font.font(15, bold: true)).lineLimit(1)
                    Spacer(minLength: 4)
                    if index < 9 {
                        Text(verbatim: "⌘\(index + 1)")
                            .font(font.font(11))
                            .foregroundStyle(theme.fg.opacity(0.35))
                            .accessibilityHidden(true)
                    }
                }
                Text(verbatim: "\(server.user)@\(server.address):\(server.port)")
                    .font(font.font(12))
                    .foregroundStyle(theme.fg.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.fg.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(index < 9 ? shortcut(KeyEquivalent(Character(String(index + 1)))) : nil)
        .accessibilityLabel(server.title)
        .accessibilityValue(Text(verbatim: "\(server.user)@\(server.address)"))
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = server }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(server) }
        }
    }

    /// Off while a terminal is open: its key commands would reach this screen through the responder chain.
    private func shortcut(_ key: KeyEquivalent) -> KeyboardShortcut? {
        connected == nil ? KeyboardShortcut(key) : nil
    }

    private func headerButton(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { headerIcon(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 38, height: 34)
            .foregroundStyle(theme.fg)
            .background(theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ServerForm: View {
    @State var server: Server
    let store: Store
    @State private var password = ""
    /// The pin of the device as it was opened; the address and port may change in the form before Save.
    @State private var pinned: String?
    @State private var forget = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (optional)", text: $server.name)
                TextField("Address", text: $server.address).keyboardType(.URL)
                TextField("Port", value: $server.port, format: .number.grouping(.never)).keyboardType(.numberPad)
                TextField("User", text: $server.user)
                SecureField("Password (empty uses the key)", text: $password)
                if pinned != nil && !forget {
                    Button("Forget host key", role: .destructive) { forget = true }  // on Save, so Cancel undoes it
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle(server.title.isEmpty ? String(localized: "New device") : server.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(server.cleaned == nil) }
            }
            .alert("Couldn't save the password to the Keychain", isPresented: $failed) {}
            .onAppear {
                password = Keychain.get(server.passwordAccount) ?? ""
                pinned = Pins.get(server.pinKey) != nil ? server.pinKey : nil
            }
        }
    }

    private func save() {
        guard let device = server.cleaned else { return }
        guard Keychain.set(server.passwordAccount, password) else { return failed = true }
        if forget, let pinned { Pins.set(pinned, nil) }
        store.save(device)
        dismiss()
    }
}

/// One private key for every server, pasted once.
struct KeyForm: View {
    @State private var pem = ""
    @State private var passphrase = ""
    @State private var error: String?
    private let saved = Keychain.get("privateKey") != nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pem)
                        .font(.caption.monospaced())
                        .frame(minHeight: 120)
                    SecureField("Key passphrase (if it has one)", text: $passphrase)
                } header: {
                    saved ? Text("Replaces the saved key") : Text("Private key")
                } footer: {
                    Text("Paste an OpenSSH private key (ed25519 or RSA). On a Mac, `pbcopy < ~/.ssh/id_ed25519` copies yours. The key stays in this iPhone's Keychain; its public half goes in each server's `~/.ssh/authorized_keys`.")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("SSH key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let key = pem.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        do {
            _ = try Session.keyAuth(user: "", pem: key, passphrase: passphrase.isEmpty ? nil : passphrase)
        } catch {
            return self.error = String(localized: "Couldn't read the key. Paste it in OpenSSH format (ed25519 or RSA) with its BEGIN and END lines, and its passphrase if it has one.")
        }
        guard Keychain.set("privateKey", key), Keychain.set("passphrase", passphrase) else {
            return self.error = String(localized: "Couldn't save to the Keychain.")
        }
        dismiss()
    }
}
