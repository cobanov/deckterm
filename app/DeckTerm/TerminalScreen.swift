import SwiftUI
import SwiftTerm

/// Full-screen terminal with a thin key bar under it. Swipe in from the left edge to go back,
/// from the right edge for the panel (snippets, look). The deck's Bluetooth keyboard types; the on-screen one
/// shows only from the bar's key. Hold a finger on the terminal and slide it for arrow keys.
/// Going back keeps the session open: the bar's tabs, the list and ⌘1–9 switch between them.
struct TerminalScreen: View {
    @ObservedObject var sessions: Sessions
    /// ⌘1–9: the list's device by index, connected or brought back.
    let device: (Int) -> Void
    @ObservedObject private var housing = Housing.shared
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("font") private var font = TermFont.jetBrains
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("tutorialSeen") private var tutorialSeen = false
    @State private var panelShown = false
    @State private var panelDrag: CGFloat = 0

    var body: some View {
        if let model = sessions.shown { screen(model) }
    }

    private func screen(_ model: TerminalModel) -> some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                TerminalHost(model: model, fontSize: fontSize, font: font, theme: theme, commands: [
                    .init(input: "=", title: "Bigger text") { fontSize = min(fontSize + 1, 32) },
                    .init(input: "-", title: "Smaller text") { fontSize = max(fontSize - 1, 8) },
                    .init(input: ",", title: "Panel") { showPanel(!panelShown) },
                    .init(input: "w", title: "Back to list") { back() },
                ] + (1...9).map { n in .init(input: "\(n)", title: "Device \(n)") { device(n - 1) } })
                .clearsHousing(housing.onLeft)
                // Edge to edge on both sides: the camera never reaches down to the bar, only the rounded corners do.
                KeyBar(model: model, sessions: sessions, theme: theme, font: font, panel: { showPanel(true) })
                    .ignoresSafeArea(.container, edges: .horizontal)
            }
            .ignoresSafeArea(.container, edges: .bottom)  // not .keyboard: the bar rides on the on-screen keyboard

            // Swipe zones at the very edges, narrower than the gap the terminal leaves there.
            HStack {
                edge { if $0 > 60 { back() } }
                Spacer()
                edge { if $0 < -60 { showPanel(true) } }
            }
            .ignoresSafeArea()

            SwiftUI.Color.black.opacity(panelShown ? 0.4 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(panelShown)
                .onTapGesture { showPanel(false) }
                .accessibilityLabel("Close panel")
                .accessibilityHidden(!panelShown)
            // Always mounted and slid by offset, so opening, dragging and closing are one motion.
            SidePanel(model: model, housingOnLeft: housing.onLeft, fontSize: $fontSize, font: $font, theme: $theme,
                      back: back, disconnect: { sessions.close(model) }, hide: { showPanel(false) })
                .offset(x: panelShown ? max(panelDrag, 0) : 460)
                .allowsHitTesting(panelShown)
                .accessibilityHidden(!panelShown)
                // Simultaneous, so the panel's own scrolling keeps working; only a sideways drag moves it.
                .simultaneousGesture(DragGesture(minimumDistance: 10)
                    .onChanged { drag in
                        if abs(drag.translation.width) > abs(drag.translation.height) { panelDrag = drag.translation.width }
                    }
                    .onEnded { drag in
                        let sideways = abs(drag.translation.width) > abs(drag.translation.height)
                        if sideways && drag.predictedEndTranslation.width > 120 { showPanel(false) }
                        withAnimation(.snappy) { panelDrag = 0 }
                    })

            if !tutorialSeen {
                Tutorial(theme: theme, font: font) { withAnimation { tutorialSeen = true } }
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func back() {
        panelShown = false
        sessions.active = nil
    }

    private func showPanel(_ shown: Bool) {
        withAnimation(.snappy) { panelShown = shown }
        if !shown { _ = sessions.shown?.terminal.becomeFirstResponder() }  // the snippet field may have taken the keyboard
    }

    private func edge(_ swiped: @escaping (CGFloat) -> Void) -> some View {
        SwiftUI.Color.clear
            .frame(width: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 15).onEnded { swiped($0.translation.width) })
    }
}

/// The open connections. They outlive the terminal screen, so each shell stays where it was while another shows.
@MainActor final class Sessions: ObservableObject {
    @Published private(set) var open: [TerminalModel] = []
    /// The one on screen; nil shows the list.
    @Published var active: TerminalModel? {
        didSet { if let active { shown = active } }
    }
    /// The last one on screen, kept through the screen's closing animation.
    private(set) var shown: TerminalModel?
    /// A connection learned what its host runs: (device id, logo name).
    var detected: (UUID, String) -> Void = { _, _ in }

    func show(_ server: Server) {
        if let model = open.first(where: { $0.server.id == server.id }) { return active = model }
        let model = TerminalModel(server: server)
        model.close = { [weak self, weak model] in if let model { self?.close(model) } }
        model.detected = { [weak self] system in self?.detected(server.id, system) }
        open.append(model)
        active = model
    }

    func close(_ model: TerminalModel) {
        model.disconnect()
        open.removeAll { $0 === model }
        if active === model { active = nil }
    }

    func model(for server: Server) -> TerminalModel? { open.first { $0.server.id == server.id } }

    /// After an edit or a delete in the list: titles follow, deleted devices hang up.
    func sync(_ servers: [Server]) {
        for model in open {
            if let server = servers.first(where: { $0.id == model.server.id }) {
                if server != model.server { model.server = server }
            } else {
                close(model)
            }
        }
    }
}

/// One connection, and the bridge between its terminal view and the SSH session.
final class TerminalModel: ObservableObject, TerminalViewDelegate {
    enum State: Equatable {
        case connecting, live, ended(String)
    }

    @Published var server: Server
    @Published private(set) var state = State.connecting
    /// Off by default: the deck's Bluetooth keyboard types.
    @Published private(set) var keyboardShown = false
    /// Owned here, not by the screen, so the scrollback survives switching away.
    let box = TerminalBox()
    var terminal: TerminalView { box.terminal }
    var close: () -> Void = {}
    var detected: (String) -> Void = { _ in }
    private let pad = ArrowPad()
    private var session: Session?
    private var size = (cols: 80, rows: 24)
    private var font: TermFont?
    private var fontSize = 0.0
    private var theme: Theme?

    init(server: Server) {
        self.server = server
        terminal.terminalDelegate = self
        terminal.inputAccessoryView = nil  // SwiftTerm's own key bar; ours is KeyBar
        terminal.inputView = UIView()      // an empty keyboard, so a tap never raises the on-screen one
        pad.attach(to: terminal)
        connect()
    }

    deinit { session?.close() }

    func connect() {
        session?.close()
        terminal.feed(text: "Connecting to \(server.user)@\(server.address)…\r\n")
        state = .connecting
        let session = Session()
        self.session = session
        // Before the first layout the size is a guess; the layout's sizeChanged resizes the PTY.
        session.start(server, cols: size.cols, rows: size.rows,
            output: { [weak self] bytes in DispatchQueue.main.async { self?.received(bytes) } },
            detected: { [weak self] system in DispatchQueue.main.async { self?.detected(system) } },
            ended: { [weak self] message in DispatchQueue.main.async { self?.ended(message) } })
    }

    func disconnect() {
        session?.close()
        session = nil
    }

    /// The look, applied only when it changed: installing colors redraws the whole screen.
    func apply(font: TermFont, size: Double, theme: Theme) {
        if self.font != font || fontSize != size {
            (self.font, fontSize) = (font, size)
            let normal = font.uiFont(size), bold = font.uiFont(size, bold: true)
            terminal.setFonts(normal: normal, bold: bold, italic: normal.italic, boldItalic: bold.italic)
        }
        if self.theme != theme {
            self.theme = theme
            terminal.installColors(theme.ansi)
            terminal.nativeForegroundColor = theme.foreground
            terminal.nativeBackgroundColor = theme.background  // only the background setter redraws
            terminal.caretColor = theme.cursor
            terminal.selectedTextBackgroundColor = theme.selection
        }
    }

    func toggleKeyboard() {
        keyboardShown.toggle()
        terminal.inputView = keyboardShown ? nil : UIView()  // nil is the system keyboard, an empty view none
        _ = terminal.becomeFirstResponder()
        terminal.reloadInputViews()
    }

    private func received(_ bytes: ArraySlice<UInt8>) {
        if state == .connecting { state = .live }
        terminal.feed(byteArray: bytes)
    }

    private func ended(_ message: String?) {
        guard let message else { return close() }
        state = .ended(message)
        terminal.feed(text: "\r\n\u{1b}[33m\(message)\u{1b}[0m\r\nEnter: reconnect · Esc: close\r\n")
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard case .ended = state else { return session?.send(data) ?? () }
        switch Array(data) {
        case [13]: connect()
        case [27]: close()
        default: break
        }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        size = (newCols, newRows)
        session?.resize(cols: newCols, rows: newRows)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { UIApplication.shared.open(url) }
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

extension TerminalModel.State {
    func color(_ theme: Theme) -> SwiftUI.Color {
        switch self {
        case .connecting: theme.ansiColor(11)
        case .live: theme.ansiColor(10)
        case .ended: theme.ansiColor(9)
        }
    }
}

/// The terminal, wrapped to carry the app's ⌘ commands. Not on the terminal itself: SwiftTerm's canPerformAction
/// refuses every action but its menu's and can't be overridden. UIKit asks this view next, up from the terminal.
final class TerminalBox: UIView {
    struct Command {
        let input: String
        let title: String
        let action: () -> Void
    }

    let terminal = TerminalView(frame: .zero)
    var commands: [Command] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminal.frame = bounds
        terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(terminal)
    }

    required init?(coder: NSCoder) { nil }

    override var keyCommands: [UIKeyCommand]? {
        commands.map {
            let command = UIKeyCommand(title: $0.title, action: #selector(run), input: $0.input, modifierFlags: .command)
            command.wantsPriorityOverSystemBehavior = true  // ⌘W and ⌘, are the system's Close and Settings otherwise
            return command
        }
    }

    @objc private func run(_ command: UIKeyCommand) {
        commands.first { $0.input == command.input }?.action()
    }
}

/// Shows the active session's terminal; the session owns it, this only gives it a place on screen.
private struct TerminalHost: UIViewRepresentable {
    let model: TerminalModel
    let fontSize: Double
    let font: TermFont
    let theme: Theme
    let commands: [TerminalBox.Command]

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ host: UIView, context: Context) {
        let box = model.box
        box.commands = commands
        model.apply(font: font, size: fontSize, theme: theme)
        guard box.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        box.frame = host.bounds
        box.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(box)
        DispatchQueue.main.async {
            _ = box.terminal.becomeFirstResponder()
            // Back in a window, SwiftTerm repaints only the rows that changed since, often none, so the screen stayed
            // blank. Setting a color is its public way to repaint every row.
            box.terminal.nativeBackgroundColor = box.terminal.nativeBackgroundColor
        }
    }
}

/// Hold a finger on the terminal, then slide it: every step sends an arrow key, with a tick.
final class ArrowPad: NSObject, UIGestureRecognizerDelegate {
    enum Arrow { case left, right, up, down }

    private weak var view: TerminalView?
    private var anchor = CGPoint.zero
    private let tick = UISelectionFeedbackGenerator()

    func attach(to view: TerminalView) {
        self.view = view
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = 0.3
        hold.delegate = self
        view.addGestureRecognizer(hold)
    }

    @objc private func held(_ hold: UILongPressGestureRecognizer) {
        // In the container: the terminal scrolls under the finger, and nil gives unrotated screen axes in landscape.
        let point = hold.location(in: hold.view?.superview)
        switch hold.state {
        case .began:
            anchor = point
            tick.selectionChanged()
        case .changed, .ended:  // a quick flick can arrive only with the lift
            let arrows = Self.arrows(from: &anchor, to: point)
            // A finger held still first also opened SwiftTerm's copy and paste menu (a UIMenuController); sliding means arrows.
            if !arrows.isEmpty { UIMenuController.shared.hideMenu() }
            for arrow in arrows {
                switch arrow {
                case .left: view?.sendKeyLeft()
                case .right: view?.sendKeyRight()
                case .up: view?.sendKeyUp()
                case .down: view?.sendKeyDown()
                }
                tick.selectionChanged()
            }
        default:
            break
        }
    }

    /// One arrow per `step` points along the longer axis; moves the anchor by what it used.
    static func arrows(from anchor: inout CGPoint, to point: CGPoint, step: CGFloat = 18) -> [Arrow] {
        var arrows: [Arrow] = []
        while true {
            let dx = point.x - anchor.x, dy = point.y - anchor.y
            guard max(abs(dx), abs(dy)) >= step else { return arrows }
            if abs(dx) >= abs(dy) {
                arrows.append(dx > 0 ? .right : .left)
                anchor = CGPoint(x: anchor.x + (dx > 0 ? step : -step), y: point.y)  // drop the drift across
            } else {
                arrows.append(dy > 0 ? .down : .up)
                anchor = CGPoint(x: point.x, y: anchor.y + (dy > 0 ? step : -step))
            }
        }
    }

    /// Alongside SwiftTerm's own long press, whose copy and paste menu still opens when the finger stays put.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other is UILongPressGestureRecognizer
    }
}

private extension UIFont {
    var italic: UIFont {
        fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitItalic))
            .map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}

/// The thin strip under the terminal: a tab per open session, and the keys a small keyboard lacks.
private struct KeyBar: View {
    @ObservedObject var model: TerminalModel
    @ObservedObject var sessions: Sessions
    let theme: Theme
    let font: TermFont
    let panel: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(sessions.open, id: \.server.id) { tab in
                        SessionTab(model: tab, active: tab === model, theme: theme, font: font,
                                   select: { sessions.active = tab }, close: { sessions.close(tab) })
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 3) {
                if case .ended = model.state {
                    key("connect", "Reconnect") { model.connect() }
                }
                key("esc", "Escape") { model.terminal.send([0x1b]) }
                key("tab", "Tab") { model.terminal.send([0x09]) }
                key("^C", "Control C") { model.terminal.send([0x03]) }
                key("^D", "Control D") { model.terminal.send([0x04]) }
                key("^Z", "Control Z") { model.terminal.send([0x1a]) }
                key("|", "Pipe") { model.terminal.send(txt: "|") }
                key("~", "Tilde") { model.terminal.send(txt: "~") }
                key("←", "Left") { model.terminal.sendKeyLeft() }
                key("↓", "Down") { model.terminal.sendKeyDown() }
                key("↑", "Up") { model.terminal.sendKeyUp() }
                key("→", "Right") { model.terminal.sendKeyRight() }
                icon(model.keyboardShown ? "keyboard.chevron.compact.down" : "keyboard",
                     model.keyboardShown ? "Hide keyboard" : "Show keyboard", model.toggleKeyboard)
                icon("sidebar.right", "Panel", panel)
            }
            .fixedSize()
        }
        .font(font.font(12))
        .foregroundStyle(theme.fg)
        .padding(.horizontal, 26)
        .frame(height: 30)
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .top) { Rectangle().fill(theme.fg.opacity(0.08)).frame(height: 1).ignoresSafeArea() }
    }

    private func key(_ title: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .padding(.horizontal, 7)
                .frame(minWidth: 30, minHeight: 24)
                .background(theme.raised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func icon(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 24) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// One open session in the key bar: the host's logo in the connection's color, and its name. Hold it to disconnect.
private struct SessionTab: View {
    @ObservedObject var model: TerminalModel
    let active: Bool
    let theme: Theme
    let font: TermFont
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 5) {
                SystemMark(system: model.server.system, font: font, size: 11)
                    .foregroundStyle(model.state.color(theme))
                Text(verbatim: model.server.title).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .foregroundStyle(theme.fg.opacity(active ? 1 : 0.5))
            .background(active ? theme.raised : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: model.server.title))
        .accessibilityAddTraits(active ? .isSelected : [])
        .contextMenu { Button("Disconnect", systemImage: "xmark", role: .destructive, action: close) }
    }
}

/// The right-hand panel: the connection, snippets, and the look.
private struct SidePanel: View {
    enum Tab: String { case snippets, look }

    @ObservedObject var model: TerminalModel
    let housingOnLeft: Bool
    @Binding var fontSize: Double
    @Binding var font: TermFont
    @Binding var theme: Theme
    let back: () -> Void
    let disconnect: () -> Void
    let hide: () -> Void
    @AppStorage("panelTab") private var tab = Tab.snippets
    /// One command per line. shortcut: no multi-line snippets; store a list if a script snippet is ever wanted.
    @AppStorage("snippets") private var snippets = ""
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SystemMark(system: model.server.system, font: font, size: 14)
                    .foregroundStyle(model.state.color(theme))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: model.server.title).font(font.font(14, bold: true))
                    Text(verbatim: "\(model.server.user)@\(model.server.address):\(model.server.port)")
                        .font(font.font(11))
                        .foregroundStyle(theme.fg.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                icon("arrow.clockwise", "Reconnect") { model.connect() }
                icon("xmark", "Disconnect", disconnect)
                icon("square.grid.2x2", "Back to list", back)
            }
            Picker("Section", selection: $tab) {
                Text("Snippets").tag(Tab.snippets)
                Text("Look").tag(Tab.look)
            }
            .pickerStyle(.segmented)
            ScrollView {
                switch tab {
                case .snippets: snippetList
                case .look: look
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .padding(.trailing, housingOnLeft ? 6 : 0)
        .foregroundStyle(theme.fg)
        // The background reaches the screen edge; the content keeps clear of the rounded corners and the camera.
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .leading) { Rectangle().fill(theme.fg.opacity(0.1)).frame(width: 1).ignoresSafeArea() }
        // Pinned to the screen's edge when the camera is on the other side. Ignoring the safe area on the panel
        // itself would widen it and leave the gap on its left instead.
        .frame(maxWidth: .infinity, alignment: .trailing)
        .ignoresSafeArea(.container, edges: housingOnLeft ? .trailing : [])
    }

    private var lines: [String] { snippets.split(separator: "\n").map(String.init) }

    private var snippetList: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("New snippet: type a command, then Enter", text: $draft)
                .font(font.font(13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(add)
                .padding(9)
                .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 4)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, command in
                Button { send(command, run: true) } label: {
                    HStack {
                        Text(verbatim: command).font(font.font(13)).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "return").font(.system(size: 11)).foregroundStyle(theme.accent)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Runs it")
                .contextMenu {
                    Button("Paste without running", systemImage: "text.insert") { send(command, run: false) }
                    Button("Delete", systemImage: "trash", role: .destructive) { remove(index) }
                }
            }
            Text("Tap: run · Hold: paste or delete")
                .font(font.font(10))
                .foregroundStyle(theme.fg.opacity(0.45))
                .padding(.top, 4)
        }
    }

    private var look: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("Font")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], spacing: 6) {
                ForEach(TermFont.allCases) { face in
                    Button { font = face } label: {
                        Text(verbatim: face.name)
                            .font(face.font(12))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(selection(face == font))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(face == font ? .isSelected : [])
                }
            }
            Stepper(value: $fontSize, in: 8...32) {
                Text("Size \(Int(fontSize)) pt").font(font.font(12))
            }
            caption("Theme")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], spacing: 6) {
                ForEach(Theme.allCases) { scheme in
                    Button { theme = scheme } label: { swatch(scheme) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: scheme.name))
                        .accessibilityAddTraits(scheme == theme ? .isSelected : [])
                }
            }
            Text("Hold and slide: arrow keys\nSwipe from the left: the list · from the right: this panel\n⌘W back · ⌘1–9 devices · ⌘= ⌘- text size · ⌘, panel")
                .font(font.font(10))
                .foregroundStyle(theme.fg.opacity(0.45))
                .padding(.top, 4)
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

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text).textCase(.uppercase).font(font.font(10, bold: true)).foregroundStyle(theme.fg.opacity(0.45))
    }

    private func icon(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 30)
                .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func add() {
        let command = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        snippets = (lines + [command]).joined(separator: "\n")
        draft = ""
    }

    private func remove(_ index: Int) {
        var kept = lines
        kept.remove(at: index)
        snippets = kept.joined(separator: "\n")
    }

    private func send(_ command: String, run: Bool) {
        model.terminal.send(txt: run ? command + "\r" : command)
        hide()
    }
}

/// Over the first terminal, once: what the edges and a held finger do. A tap anywhere puts it away.
private struct Tutorial: View {
    let theme: Theme
    let font: TermFont
    let done: () -> Void

    var body: some View {
        ZStack {
            theme.bg.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                HStack(alignment: .top) {
                    hint("arrow.right", "Swipe in from the left edge", "Back to your devices", leading: true)
                    Spacer()
                    hint("arrow.up.and.down.and.arrow.left.and.right", "Hold and slide on the terminal", "Arrow keys", leading: nil)
                    Spacer()
                    hint("arrow.left", "Swipe in from the right edge", "Settings and snippets", leading: false)
                }
                .padding(.horizontal, 24)
                Spacer()
                Text("⌘W back · ⌘1–9 devices · ⌘, settings")
                    .font(font.font(12))
                    .foregroundStyle(theme.fg.opacity(0.55))
                Button("Got it", action: done)
                    .buttonStyle(PillStyle(theme: theme, font: font, primary: true))
                    .frame(width: 200)
                    .padding(.bottom, 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
    }

    /// `leading` nil centers it.
    private func hint(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, leading: Bool?) -> some View {
        VStack(alignment: leading == false ? .trailing : leading == true ? .leading : .center, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text(title).font(font.font(14, bold: true)).foregroundStyle(theme.fg)
            Text(detail).font(font.font(12)).foregroundStyle(theme.fg.opacity(0.6))
        }
        .multilineTextAlignment(leading == false ? .trailing : leading == true ? .leading : .center)
        .frame(maxWidth: 220, alignment: leading == false ? .trailing : leading == true ? .leading : .center)
    }
}
