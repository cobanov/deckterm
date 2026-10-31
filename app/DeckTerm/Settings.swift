import SwiftUI
import GhosttyTerminal

/// A key the bar under the terminal can carry. Raw values are stored in UserDefaults, so they never change.
enum BarKey: String, CaseIterable, Identifiable {
    case esc, tab, enter, ctrlC, ctrlD, ctrlZ, ctrlL, ctrlR, ctrlA, ctrlE, ctrlU, ctrlW,
         pipe, tilde, slash, dash, left, down, up, right, home, end, pageUp, pageDown

    var id: Self { self }

    /// The bar until Settings changes it.
    static let standard: [BarKey] = [.esc, .tab, .enter, .ctrlC, .ctrlD, .ctrlZ, .pipe, .tilde, .left, .down, .up, .right]

    /// The bar as stored under "barKeys": raw values, comma separated. Unknown ones are dropped.
    static func list(_ stored: String) -> [BarKey] {
        stored.split(separator: ",").compactMap { BarKey(rawValue: String($0)) }
    }

    static func store(_ keys: [BarKey]) -> String { keys.map(\.rawValue).joined(separator: ",") }

    var title: String {
        switch self {
        case .esc: "esc"
        case .tab: "tab"
        case .enter: "enter"
        case .ctrlC: "^C"
        case .ctrlD: "^D"
        case .ctrlZ: "^Z"
        case .ctrlL: "^L"
        case .ctrlR: "^R"
        case .ctrlA: "^A"
        case .ctrlE: "^E"
        case .ctrlU: "^U"
        case .ctrlW: "^W"
        case .pipe: "|"
        case .tilde: "~"
        case .slash: "/"
        case .dash: "-"
        case .left: "←"
        case .down: "↓"
        case .up: "↑"
        case .right: "→"
        case .home: "home"
        case .end: "end"
        case .pageUp: "pgup"
        case .pageDown: "pgdn"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .esc: "Escape"
        case .tab: "Tab"
        case .enter: "Enter"
        case .ctrlC: "Control C"
        case .ctrlD: "Control D"
        case .ctrlZ: "Control Z"
        case .ctrlL: "Control L"
        case .ctrlR: "Control R"
        case .ctrlA: "Control A"
        case .ctrlE: "Control E"
        case .ctrlU: "Control U"
        case .ctrlW: "Control W"
        case .pipe: "Pipe"
        case .tilde: "Tilde"
        case .slash: "Slash"
        case .dash: "Dash"
        case .left: "Left"
        case .down: "Down"
        case .up: "Up"
        case .right: "Right"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page up"
        case .pageDown: "Page down"
        }
    }

    /// Keys go through libghostty's encoder, so the program's key mode decides the bytes; characters are typed.
    @MainActor func press(on terminal: UITerminalView) {
        switch self {
        case .esc: terminal.sendKey(.escape)
        case .tab: terminal.sendKey(.tab)
        case .enter: terminal.sendKey(.enter)
        case .ctrlC: terminal.sendKey(.c, modifiers: .ctrl)
        case .ctrlD: terminal.sendKey(.d, modifiers: .ctrl)
        case .ctrlZ: terminal.sendKey(.z, modifiers: .ctrl)
        case .ctrlL: terminal.sendKey(.l, modifiers: .ctrl)
        case .ctrlR: terminal.sendKey(.r, modifiers: .ctrl)
        case .ctrlA: terminal.sendKey(.a, modifiers: .ctrl)
        case .ctrlE: terminal.sendKey(.e, modifiers: .ctrl)
        case .ctrlU: terminal.sendKey(.u, modifiers: .ctrl)
        case .ctrlW: terminal.sendKey(.w, modifiers: .ctrl)
        case .pipe: terminal.insertText("|")
        case .tilde: terminal.insertText("~")
        case .slash: terminal.insertText("/")
        case .dash: terminal.insertText("-")
        case .left: terminal.sendKey(.arrowLeft)
        case .down: terminal.sendKey(.arrowDown)
        case .up: terminal.sendKey(.arrowUp)
        case .right: terminal.sendKey(.arrowRight)
        case .home: terminal.sendKey(.home)
        case .end: terminal.sendKey(.end)
        case .pageUp: terminal.sendKey(.pageUp)
        case .pageDown: terminal.sendKey(.pageDown)
        }
    }
}

/// How the iPhone holds the screen, as Settings chose: landscape by default, the way the deck holds it. iPadOS
/// windows turn and resize freely, so the choice is the iPhone's alone. Stored by raw value.
enum Rotation: String, CaseIterable {
    case landscape, portrait, auto

    /// nil on iPad.
    private static var chosen: Rotation? {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }
        return UserDefaults.standard.string(forKey: "orientation").flatMap(Rotation.init) ?? .landscape
    }

    static var mask: UIInterfaceOrientationMask {
        switch chosen {
        case nil: .all
        case .landscape: .landscape
        case .portrait: .portrait
        case .auto: .allButUpsideDown
        }
    }

    /// Whether a scene in `orientation` stays that way: the one Settings chose, and in Auto the way the phone is held.
    static func stands(_ orientation: UIInterfaceOrientation, held: UIDeviceOrientation = UIDevice.current.orientation) -> Bool {
        switch chosen {
        case nil: true
        case .landscape: orientation.isLandscape
        case .portrait: orientation.isPortrait
        case .auto: held == .portrait ? orientation.isPortrait : held.isLandscape ? orientation.isLandscape : true
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .landscape: "Landscape"
        case .portrait: "Portrait"
        case .auto: "Auto"
        }
    }

    /// After the setting changed: the screen turns to the new choice now.
    static func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            var controller = scene.keyWindow?.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

/// Calls `ended` as each turn of the screen finishes, after iOS's own animation; the scene reports the new
/// orientation as the turn starts.
struct TurnEnd: UIViewControllerRepresentable {
    let ended: () -> Void

    func makeUIViewController(context: Context) -> Watcher { Watcher() }
    func updateUIViewController(_ watcher: Watcher, context: Context) { watcher.ended = ended }

    final class Watcher: UIViewController {
        var ended: () -> Void = {}

        override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.ended() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Rotation.mask
    }
}

/// How DeckTerm looks and behaves: the key bar, the font and theme, the screen; backups and About from the list.
/// The side panel keeps what a session uses.
struct SettingsScreen: View {
    @AppStorage("barKeys") private var barKeys = BarKey.store(BarKey.standard)
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("font") private var font = TermFont.jetBrains
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("orientation") private var orientation = Rotation.landscape
    @AppStorage("keyboardShown") private var keyboardShown = false
    /// The device list's, for backups; the terminal's Settings has none.
    var store: Store?
    @State private var importing = false
    @State private var notice: String?
    @State private var aboutShown = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Key bar") {
                    NavigationLink {
                        KeyBarSettings()
                    } label: {
                        Text(verbatim: BarKey.list(barKeys).map(\.title).joined(separator: " "))
                            .font(font.font(13))
                            .lineLimit(1)
                    }
                }
                Section("Font") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                        ForEach(TermFont.allCases) { face in
                            Button { font = face } label: {
                                Text(verbatim: face.name)
                                    .font(face.font(12))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                                    .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(selection(face == font))
                            }
                            .buttonStyle(.plain)  // several buttons in one row: plain keeps each tap to its own
                            .accessibilityAddTraits(face == font ? .isSelected : [])
                        }
                    }
                    Stepper(value: $fontSize, in: 8...32) {
                        Text("Size \(Int(fontSize)) pt").font(font.font(13))
                    }
                }
                Section("Theme") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                        ForEach(Theme.allCases) { scheme in
                            Button { theme = scheme } label: { swatch(scheme) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: scheme.name))
                                .accessibilityAddTraits(scheme == theme ? .isSelected : [])
                        }
                    }
                }
                Section {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Picker("Orientation", selection: $orientation) {
                            ForEach(Rotation.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    Toggle("On-screen keyboard", isOn: $keyboardShown)
                } header: {
                    Text("Screen")
                } footer: {
                    Text("Landscape is how the deck holds the phone; Auto turns with it. With the on-screen keyboard off, it shows only from the key bar's keyboard button; on, it comes up with every tap, new tab or pane, even after the button put it away.")
                }
                if let store {
                    Section("Backup") {
                        ShareLink(item: Backup(store), preview: SharePreview("DeckTerm backup")) {
                            Label("Export backup", systemImage: "square.and.arrow.up")
                        }
                        Button("Restore from backup", systemImage: "square.and.arrow.down") { importing = true }
                    }
                }
                Section {
                    Button("About DeckTerm", systemImage: "info.circle") { aboutShown = true }
                }
                Section {
                } footer: {
                    Text("Hold and slide on the terminal: arrow keys. Swipe in from the left edge: your devices; from the right: snippets and files. ⌘W back · ⌘1–9 devices · ⌘T new tab · ⌘D split · ⌘[ ⌘] panes · ⌘= ⌘- text size · ⌘, panel")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: orientation) { Rotation.apply() }
            .sheet(isPresented: $aboutShown) { AboutSheet() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { picked in
                if let store { notice = Backup.restore(picked, into: store) }
            }
            .alert("Backup", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            } message: {
                Text(notice ?? "")
            }
        }
    }

    private func swatch(_ scheme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: scheme.name).font(font.font(11, bold: true)).foregroundStyle(scheme.fg).lineLimit(1)
            HStack(spacing: 3) {
                ForEach(1..<7) { Circle().fill(scheme.ansiColor($0)).frame(width: 8, height: 8) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scheme.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.fg.opacity(0.12)))
        .overlay(selection(scheme == theme))
    }

    private func selection(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(selected ? theme.accent : .clear, lineWidth: 2)
    }
}

/// The bar's keys in order, and the rest of the catalog to add from.
private struct KeyBarSettings: View {
    @AppStorage("barKeys") private var barKeys = BarKey.store(BarKey.standard)
    @AppStorage("font") private var font = TermFont.jetBrains

    var body: some View {
        let shown = BarKey.list(barKeys)
        List {
            Section {
                ForEach(shown) { row($0) }
                    .onMove { from, to in
                        var keys = shown
                        keys.move(fromOffsets: from, toOffset: to)
                        barKeys = BarKey.store(keys)
                    }
                    .onDelete { offsets in
                        var keys = shown
                        keys.remove(atOffsets: offsets)
                        barKeys = BarKey.store(keys)
                    }
            } header: {
                Text("On the bar")
            } footer: {
                Text("Drag to reorder. The keys scroll when they don't fit.")
            }
            Section("More keys") {
                ForEach(BarKey.allCases.filter { !shown.contains($0) }) { key in
                    Button { barKeys = BarKey.store(shown + [key]) } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            row(key)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                Button("Back to the standard keys") { barKeys = BarKey.store(BarKey.standard) }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Key bar")
    }

    private func row(_ key: BarKey) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: key.title)
                .font(font.font(13))
                .frame(minWidth: 44)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(key.label)
        }
        .contentShape(Rectangle())
    }
}
