import SwiftUI

@main
struct DeckTermApp: App {
    init() { TermFont.register() }

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
        .fullScreenCover(item: $connected) { TerminalScreen(server: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: restore)
        .alert("Yedek", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
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
            notice = "\(count) cihaz ve ayarlar geri yüklendi. Parolalar ve SSH anahtarı yedekte yok: anahtarı bir kez yapıştır."
        } catch {
            notice = "Yedek okunamadı: \(error.localizedDescription)"
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Mark(theme: theme, font: font, size: 28)
                Text("deckterm").font(font.font(18, bold: true))
                Spacer()
                Menu {
                    ShareLink(item: Backup(store), preview: SharePreview("DeckTerm yedeği")) {
                        Label("Yedeği dışa aktar", systemImage: "square.and.arrow.up")
                    }
                    Button("Yedekten geri yükle", systemImage: "square.and.arrow.down") { importing = true }
                } label: {
                    headerIcon("ellipsis")
                }
                .accessibilityLabel("Yedek")
                headerButton("key", "SSH anahtarı") { keyShown = true }
                headerButton("plus", "Cihaz ekle") { editing = Server() }
                    .keyboardShortcut(shortcut("n"))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            if store.servers.isEmpty {
                VStack(spacing: 10) {
                    Text("Henüz cihaz yok").font(font.font(15, bold: true))
                    Text("Bir SSH sunucusu ekle; dokununca terminali açılır.")
                        .font(font.font(12))
                        .foregroundStyle(theme.fg.opacity(0.55))
                    Button { editing = Server() } label: { Label("Cihaz ekle", systemImage: "plus") }
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
                    Text(">").font(font.font(15, bold: true)).foregroundStyle(theme.accent).accessibilityHidden(true)
                    Text(server.title).font(font.font(15, bold: true)).lineLimit(1)
                    Spacer(minLength: 4)
                    if index < 9 {
                        Text("⌘\(index + 1)")
                            .font(font.font(11))
                            .foregroundStyle(theme.fg.opacity(0.35))
                            .accessibilityHidden(true)
                    }
                }
                Text("\(server.user)@\(server.address):\(String(server.port))")
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
        .accessibilityValue("\(server.user)@\(server.address)")
        .contextMenu {
            Button("Düzenle", systemImage: "pencil") { editing = server }
            Button("Sil", systemImage: "trash", role: .destructive) { store.delete(server) }
        }
    }

    /// Off while a terminal is open: its key commands would reach this screen through the responder chain.
    private func shortcut(_ key: KeyEquivalent) -> KeyboardShortcut? {
        connected == nil ? KeyboardShortcut(key) : nil
    }

    private func headerButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
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
    @State private var pinned = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ad (isteğe bağlı)", text: $server.name)
                TextField("Adres", text: $server.address).keyboardType(.URL)
                TextField("Port", value: $server.port, format: .number.grouping(.never)).keyboardType(.numberPad)
                TextField("Kullanıcı", text: $server.user)
                SecureField("Parola (boşsa anahtar kullanılır)", text: $password)
                if pinned {
                    Button("Host anahtarını unut", role: .destructive) {
                        Pins.set(server.pinKey, nil)
                        pinned = false
                    }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle(server.title.isEmpty ? "Yeni cihaz" : server.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet", action: save).disabled(!valid) }
            }
            .alert("Parola Keychain'e yazılamadı", isPresented: $failed) {}
            .onAppear {
                password = Keychain.get(server.passwordAccount) ?? ""
                pinned = Pins.get(server.pinKey) != nil
            }
        }
    }

    private var valid: Bool {
        !trimmed(server.address).isEmpty && !trimmed(server.user).isEmpty && (1...65535).contains(server.port)
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard Keychain.set(server.passwordAccount, password) else { return failed = true }
        server.address = trimmed(server.address)
        server.user = trimmed(server.user)
        store.save(server)
        dismiss()
    }
}

/// One private key for every server: the Mac's own, pasted once.
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
                    SecureField("Anahtar parolası (şifreliyse)", text: $passphrase)
                } header: {
                    Text(saved ? "Kayıtlı anahtarın yerine geçer" : "Özel anahtar")
                } footer: {
                    Text("Mac'te `pbcopy < ~/.ssh/id_ed25519` çalıştır, buraya yapıştır. Anahtar bu iPhone'un Keychain'inde kalır.")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("SSH anahtarı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let key = pem.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        do {
            _ = try Session.keyAuth(user: "", pem: key, passphrase: passphrase.isEmpty ? nil : passphrase)
        } catch {
            return self.error = "Anahtar okunamadı. OpenSSH biçiminde (ed25519 ya da RSA), BEGIN/END satırlarıyla yapıştır; şifreliyse parolasını gir."
        }
        guard Keychain.set("privateKey", key), Keychain.set("passphrase", passphrase) else {
            return self.error = "Keychain'e yazılamadı."
        }
        dismiss()
    }
}
