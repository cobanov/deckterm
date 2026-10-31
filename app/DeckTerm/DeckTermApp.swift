import SwiftUI
import StoreKit

@main
struct DeckTermApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate

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
        }
    }
}

/// The devices as cards, in as many columns as the screen takes. ⌘1–9 opens one, ⌘N adds one. While connections
/// are open, a tab bar (iOS 26's floating glass one) switches to them. With no devices yet, the welcome screen
/// stands in for it.
struct ServerList: View {
    @StateObject private var store = Store()
    @StateObject private var sessions = Sessions()
    @ObservedObject private var housing = Housing.shared
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("font") private var font = TermFont.jetBrains
    @State private var editing: Server?
    @State private var deleting: Server?
    @State private var importing = false
    @State private var settingsShown = false
    @State private var notice: String?
    @State private var connectionsShown = false

    var body: some View {
        Group {
            if store.servers.isEmpty {
                WelcomeScreen(addDevice: { editing = Server() }, restore: { importing = true })
            } else {
                let bar: Visibility = sessions.tabs.isEmpty ? .hidden : .visible
                TabView(selection: $connectionsShown) {
                    list.toolbar(bar, for: .tabBar)
                        .tabItem { Label("Vaults", systemImage: "server.rack") }
                        .tag(false)
                    connections.toolbar(bar, for: .tabBar)
                        .tabItem { Label("Connections", systemImage: "terminal") }
                        .tag(true)
                }
                .onChange(of: sessions.tabs.isEmpty) { _, empty in if empty { connectionsShown = false } }
            }
        }
        .tint(theme.accent)
        .sheet(item: $editing) { ServerForm(server: $0, store: store) }
        .sheet(isPresented: $settingsShown) { SettingsScreen(store: store) }
        .fullScreenCover(isPresented: Binding(get: { sessions.active != nil }, set: { if !$0 { sessions.active = nil } })) {
            TerminalScreen(sessions: sessions, device: open)
        }
        .onChange(of: store.servers) { _, servers in sessions.sync(servers) }
        .onAppear {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { housing.watch(scene) }
            sessions.detected = { [store] id, system in
                guard var server = store.servers.first(where: { $0.id == id }), server.system != system else { return }
                server.system = system
                store.save(server)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { notice = Backup.restore($0, into: store) }
        .confirmationDialog(Text(verbatim: deleting?.title ?? ""),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { server in
            Button("Delete", role: .destructive) { store.delete(server) }
        } message: { _ in
            Text("Its saved password goes too, and an open session hangs up.")
        }
        .alert("Backup", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
        } message: {
            Text(notice ?? "")
        }
    }

    /// The device at this place in the list, connected or brought back.
    private func open(_ index: Int) {
        if store.servers.indices.contains(index) { sessions.show(store.servers[index]) }
    }

    private var list: some View {
        page {
            Mark(theme: theme, font: font, size: 28)
            Text(verbatim: "deckterm").font(font.font(18, bold: true))
            Spacer()
            headerButton("gearshape", "Settings") { settingsShown = true }
            headerButton("plus", "Add a device") { editing = Server() }
                .keyboardShortcut(shortcut("n"))
        } cards: {
            ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                card(server, index: index)
            }
        }
    }

    /// A card per tab, a row per pane: tap one to go back to it, hold it to disconnect.
    private var connections: some View {
        page {
            Text("Connections").font(font.font(18, bold: true))
            Spacer()
        } cards: {
            ForEach(sessions.tabs) { tab in
                VStack(spacing: 0) {
                    ForEach(tab.panes) { pane in
                        if pane !== tab.panes.first { Rectangle().fill(theme.fg.opacity(0.08)).frame(height: 1) }
                        ConnectionRow(model: pane, theme: theme, font: font) { sessions.active = pane }
                            .contextMenu {
                                Button("Disconnect", systemImage: "xmark", role: .destructive) { sessions.close(pane) }
                            }
                    }
                }
                .tile(theme)
            }
        }
    }

    /// Cards in as many columns as fit, under a header row, clear of the housing.
    private func page<Header: View, Cards: View>(@ViewBuilder header: () -> Header,
                                                 @ViewBuilder cards: () -> Cards) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10, content: header)
                .frame(minHeight: 34)
                .padding(.horizontal)
                // iPadOS draws its window controls over the top-leading corner and reports no inset for them.
                .padding(.leading, UIDevice.current.model == "iPhone" ? 0 : 56)
                .padding(.vertical, 10)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)], spacing: 12, content: cards)
                    .padding([.horizontal, .bottom])
            }
        }
        .clearsHousing(housing.onLeft, corner: 8)
        .foregroundStyle(theme.fg)
        .background(theme.bg.ignoresSafeArea())
    }

    private func card(_ server: Server, index: Int) -> some View {
        Button { sessions.show(server) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SystemMark(system: server.system, font: font, size: 15).foregroundStyle(theme.accent)
                    Text(verbatim: server.title).font(font.font(15, bold: true)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let session = sessions.model(for: server) { LiveDot(model: session, theme: theme) }
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
            .tile(theme)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(index < 9 ? shortcut(KeyEquivalent(Character(String(index + 1)))) : nil)
        .accessibilityLabel(server.title)
        .accessibilityValue(Text(verbatim: "\(server.user)@\(server.address)"))
        .contextMenu {
            Button("Open in new tab", systemImage: "plus.square.on.square") { sessions.newTab(server) }
            if !sessions.tabs.isEmpty {
                Button("Open beside", systemImage: "rectangle.split.2x1") { sessions.split(server) }
            }
            Button("Edit", systemImage: "pencil") { editing = server }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = server }
        }
    }

    /// Off while a terminal is open: its key commands would reach this screen through the responder chain.
    private func shortcut(_ key: KeyEquivalent) -> KeyboardShortcut? {
        sessions.active == nil ? KeyboardShortcut(key) : nil
    }

    private func headerButton(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 34)
                .foregroundStyle(theme.fg)
                .background(theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension View {
    /// A card on the list's background.
    func tile(_ theme: Theme) -> some View {
        background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.fg.opacity(0.08)))
    }
}

/// An open connection in the Connections tab: the host's logo in the connection's color, its name and state.
private struct ConnectionRow: View {
    @ObservedObject var model: TerminalModel
    let theme: Theme
    let font: TermFont
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SystemMark(system: model.server.system, font: font, size: 15)
                        .foregroundStyle(model.state.color(theme))
                    Text(verbatim: model.server.title).font(font.font(15, bold: true)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(model.state.label).font(font.font(11)).foregroundStyle(model.state.color(theme))
                }
                Text(verbatim: "\(model.server.user)@\(model.server.address):\(model.server.port)")
                    .font(font.font(12))
                    .foregroundStyle(theme.fg.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// On a card whose device has a session open: the connection's color.
private struct LiveDot: View {
    @ObservedObject var model: TerminalModel
    let theme: Theme

    var body: some View {
        Circle().fill(model.state.color(theme)).frame(width: 7, height: 7).accessibilityLabel(model.state.label)
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
    @State private var keySaved = false
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
                Section {
                    NavigationLink { KeyForm() } label: {
                        LabeledContent("SSH key", value: keySaved ? String(localized: "Saved") : String(localized: "None"))
                            .onAppear { keySaved = Keychain.get("privateKey") != nil }  // again on coming back
                    }
                } footer: {
                    Text("One ed25519 key for every device. A device with a password uses the password.")
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

/// One private key for every server, pasted once, from the device form.
struct KeyForm: View {
    @State private var pem = ""
    @State private var passphrase = ""
    @State private var error: String?
    private let saved = Keychain.get("privateKey") != nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextEditor(text: $pem)
                    .font(.caption.monospaced())
                    .frame(minHeight: 120)
                SecureField("Key passphrase (if it has one)", text: $passphrase)
            } header: {
                saved ? Text("Replaces the saved key") : Text("Private key")
            } footer: {
                Text("Paste an OpenSSH ed25519 private key. On a Mac, `pbcopy < ~/.ssh/id_ed25519` copies yours. The key stays in this iPhone's Keychain; its public half goes in each server's `~/.ssh/authorized_keys`.")
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let key = pem.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        do {
            _ = try Session.keyAuth(user: "", pem: key, passphrase: passphrase.isEmpty ? nil : passphrase)
        } catch {
            return self.error = error.localizedDescription
        }
        guard Keychain.set("privateKey", key), Keychain.set("passphrase", passphrase) else {
            return self.error = String(localized: "Couldn't save to the Keychain.")
        }
        dismiss()
    }
}
