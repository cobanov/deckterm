import SwiftUI
import GhosttyTerminal

/// Full-screen terminal with a thin key bar under it. Swipe in from the left edge to go back,
/// from the right edge for the panel (snippets, files). The deck's Bluetooth keyboard types; the on-screen one
/// follows Settings and the bar's key (Sessions.keyboardUp). Hold a finger on the terminal and slide it for arrow keys.
/// Going back keeps the session open: the bar's tabs, the list and ⌘1–9 switch between them. ⌘T opens another
/// connection to the device in a tab, ⌘D beside it in the same tab, and ⌘[ ⌘] move between panes.
struct TerminalScreen: View {
    @ObservedObject var sessions: Sessions
    /// ⌘1–9: the list's device by index, connected or brought back.
    let device: (Int) -> Void
    @ObservedObject private var housing = Housing.shared
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("font") private var font = TermFont.jetBrains
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("tutorialSeen") private var tutorialSeen = false
    /// Settings' "On-screen keyboard": whether a terminal taking the keys brings the keyboard up.
    @AppStorage("keyboardShown") private var keyboardShown = false
    @State private var panelShown = false
    @State private var panelDrag: CGFloat = 0
    @State private var settingsShown = false
    @State private var filesShown = false

    var body: some View {
        if let model = sessions.shown { screen(model) }
    }

    private func screen(_ model: TerminalModel) -> some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                // Every tab stays mounted, the others hidden and not drawing: a terminal taken out of the window
                // and put back left its place empty for a frame, a grey flash on every switch of tabs.
                ZStack {
                    ForEach(sessions.tabs) { tab in
                        grid(tab.panes, model: model, showing: tab.panes.contains { $0 === model })
                    }
                    // Closing: its tab is gone, the screen not yet.
                    if !sessions.tabs.contains(where: { $0.panes.contains { $0 === model } }) {
                        grid([model], model: model, showing: true)
                    }
                }
                .clearsHousing(housing.onLeft)
                .padding(.horizontal, housing.onLeft == nil ? 6 : 0)  // upright or on an iPad: off the glass's edge
                // Edge to edge: the camera never reaches down to the bar. Above the home indicator, the rounded
                // corners are clear of it too.
                KeyBar(model: model, sessions: sessions, theme: theme, font: font, panel: { showPanel(true) })
                    .ignoresSafeArea(.container, edges: .horizontal)
            }

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
            SidePanel(model: model, font: font, theme: theme,
                      back: back, disconnect: { sessions.close(model) }, hide: { showPanel(false) },
                      newTab: { showPanel(false); sessions.newTab(model.server) },
                      split: { showPanel(false); sessions.split(model.server) },
                      settings: { settingsShown = true },
                      expandFiles: { showPanel(false); filesShown = true })
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
        .sheet(isPresented: $settingsShown, onDismiss: focus) { SettingsScreen() }
        .fullScreenCover(isPresented: $filesShown, onDismiss: focus) {
            FilesScreen(model: model, theme: theme, font: font) { filesShown = false }
        }
        .onChange(of: keyboardShown) { sessions.keyboardUp = keyboardShown }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// One tab's panes; `model` has the keys.
    private func grid(_ panes: [TerminalModel], model: TerminalModel, showing: Bool) -> some View {
        PaneGrid {
            ForEach(panes) { pane in
                TerminalHost(model: pane, focused: pane === model, visible: showing, keyboardShown: sessions.keyboardUp,
                             fontSize: fontSize, font: font, theme: theme, commands: commands(model))
                    // Dimmed while another pane has the keys, as Ghostty does.
                    .overlay { theme.bg.opacity(pane === model ? 0 : 0.35).allowsHitTesting(false) }
            }
        }
        // The line between panes; a color background would spread into the camera's safe area.
        .background(theme.fg.opacity(0.15), ignoresSafeAreaEdges: [])
        .opacity(showing ? 1 : 0)
        .allowsHitTesting(showing)
        .accessibilityHidden(!showing)
    }

    private func commands(_ model: TerminalModel) -> [DeckTerminal.Command] {
        [
            .init(input: "=", title: "Bigger text") { fontSize = min(fontSize + 1, 32) },
            .init(input: "-", title: "Smaller text") { fontSize = max(fontSize - 1, 8) },
            .init(input: ",", title: "Panel") { showPanel(!panelShown) },
            .init(input: "w", title: "Back to list") { back() },
            .init(input: "t", title: "New tab") { sessions.newTab(model.server) },
            .init(input: "d", title: "Split") { sessions.split(model.server) },
            .init(input: "[", title: "Previous pane") { sessions.cycle(-1) },
            .init(input: "]", title: "Next pane") { sessions.cycle(1) },
        ] + (1...9).map { n in .init(input: "\(n)", title: "Device \(n)") { device(n - 1) } }
    }

    private func back() {
        panelShown = false
        sessions.active = nil
    }

    private func showPanel(_ shown: Bool) {
        withAnimation(.snappy) { panelShown = shown }
        if !shown { focus() }  // the snippet field may have taken the keyboard
    }

    private func focus() { _ = sessions.shown?.terminal.becomeFirstResponder() }

    private func edge(_ swiped: @escaping (CGFloat) -> Void) -> some View {
        SwiftUI.Color.clear
            .frame(width: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 15).onEnded { swiped($0.translation.width) })
    }
}

/// The open connections, as tabs of panes, any number to one device. They outlive the terminal screen, so each
/// shell stays where it was while another shows.
@MainActor final class Sessions: ObservableObject {
    /// Panes on screen together, each its own connection.
    struct Tab: Identifiable {
        let id = UUID()
        var panes: [TerminalModel]
    }

    /// shortcut: two panes, halves along the longer side; a split tree once someone asks for more.
    static let maxPanes = 2

    @Published private(set) var tabs: [Tab] = [] {
        didSet { keepAlive() }
    }
    /// The pane with the keys; nil shows the list.
    @Published var active: TerminalModel? {
        didSet {
            guard let active else { return }
            shown = active
            // Another tab's pane is mounted, hidden, and takes the keys at once; a new one is off screen until the
            // next layout and can't yet, so the one leaving lets go of them now, not mid-update (see TerminalHost).
            if !active.terminal.isFirstResponder && !active.terminal.becomeFirstResponder() {
                _ = oldValue?.terminal.resignFirstResponder()
            }
        }
    }
    /// The on-screen keyboard, for now. With Settings' "On-screen keyboard" on, every terminal taking the keys
    /// brings it up (a tap, a new tab or pane, back from the list or a sheet), even after the bar's key put it away;
    /// off, only the bar's key does. The key never changes the setting.
    @Published var keyboardUp = false
    /// The last one on screen, kept through the screen's closing animation.
    private(set) var shown: TerminalModel?
    /// A connection learned what its host runs: (device id, logo name).
    var detected: (UUID, String) -> Void = { _, _ in }

    var open: [TerminalModel] { tabs.flatMap(\.panes) }

    /// The names of the connections not dropped. One that dropped stays as a pane, waiting for Enter, but keeps
    /// nothing running: with it, the island went on saying "1 connection" with none up.
    var alive: [String] {
        open.filter { if case .ended = $0.state { false } else { true } }.map(\.server.title)
    }

    /// After every change to the panes, their states or their names.
    private func keepAlive() {
        if #available(iOS 26.0, *) { Keepalive.shared.update(alive) }
    }

    /// The device's open session, or a new one.
    func show(_ server: Server) {
        if let model = model(for: server) { return active = model }
        newTab(server)
    }

    /// Another connection to the device, in a tab of its own.
    func newTab(_ server: Server) {
        let model = make(server)
        tabs.append(Tab(panes: [model]))
        active = model
    }

    /// Another connection to the device, beside a pane (the one last on screen unless named); in a new tab when that
    /// one is full.
    func split(_ server: Server, beside pane: TerminalModel? = nil) {
        guard let beside = pane ?? shown, let t = tabs.firstIndex(where: { $0.panes.contains { $0 === beside } }),
              tabs[t].panes.count < Self.maxPanes,
              let p = tabs[t].panes.firstIndex(where: { $0 === beside }) else { return newTab(server) }
        let model = make(server)
        tabs[t].panes.insert(model, at: p + 1)
        active = model
    }

    func close(_ model: TerminalModel) {
        model.disconnect()
        guard let t = tabs.firstIndex(where: { $0.panes.contains { $0 === model } }),
              let p = tabs[t].panes.firstIndex(where: { $0 === model }) else { return }
        let rest = tabs[t].panes.filter { $0 !== model }
        // The keys move to a neighbor while the closing pane is still on screen.
        if active === model { active = rest.isEmpty ? nil : rest[max(p - 1, 0)] }
        if rest.isEmpty { tabs.remove(at: t) } else { tabs[t].panes = rest }
    }

    /// ⌘[ ⌘]: the pane before or after, on into the next tab.
    func cycle(_ step: Int) {
        let all = open
        guard let active, let i = all.firstIndex(where: { $0 === active }) else { return }
        self.active = all[(i + step + all.count) % all.count]
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
        keepAlive()  // a renamed device, which changes no tab
    }

    private func make(_ server: Server) -> TerminalModel {
        let model = TerminalModel(server: server)
        model.close = { [weak self, weak model] in if let model { self?.close(model) } }
        model.detected = { [weak self] system in self?.detected(server.id, system) }
        model.stateChanged = { [weak self] in self?.keepAlive() }
        // A tap on another pane gives it the keys; the bar and the panel follow.
        model.terminal.tookKeys = { [weak self, weak model] in
            guard let self, let model else { return }
            if UserDefaults.standard.bool(forKey: "keyboardShown") && !self.keyboardUp { self.keyboardUp = true }
            guard self.active != nil, self.active !== model else { return }
            self.active = model
        }
        return model
    }
}

/// One connection, and the bridge between its terminal view and the SSH session.
@MainActor final class TerminalModel: ObservableObject, TerminalSurfaceOpenURLDelegate {
    enum State: Equatable {
        case connecting, live, ended(String)
    }

    /// One for every session, so a change of look reaches them all. No theme: libghostty-spm's would override ours.
    private static let controller = TerminalController(configuration: .default, theme: TerminalTheme())

    @Published var server: Server
    @Published private(set) var state = State.connecting {
        didSet { if state != oldValue { stateChanged() } }
    }
    /// Owned here, not by the screen, so the scrollback survives switching away.
    let terminal = DeckTerminal(frame: .zero)
    var close: () -> Void = {}
    var detected: (String) -> Void = { _ in }
    var stateChanged: () -> Void = {}
    /// SFTP on the shell's own connection.
    private(set) lazy var files = RemoteFiles { [weak self] in self?.session?.client }
    private let pad = ArrowPad()
    private var session: Session?
    private var size = (cols: 80, rows: 24)
    /// libghostty's end of the shell: the host's bytes go in, keys and grid sizes come out. No local PTY on iOS.
    private lazy var io = InMemoryTerminalSession(
        write: { [weak self] data in DispatchQueue.main.async { self?.send(Array(data)) } },
        resize: { [weak self] grid in
            DispatchQueue.main.async { self?.resized(cols: Int(grid.columns), rows: Int(grid.rows)) }
        })

    init(server: Server) {
        self.server = server
        terminal.controller = Self.controller
        terminal.configuration = TerminalSurfaceOptions(backend: .inMemory(io))
        terminal.delegate = self
        terminal.inputAccessoryItems = []  // libghostty's own key bar; ours is KeyBar
        pad.attach(to: terminal)
        connect()
    }

    deinit { session?.close() }

    func connect() {
        session?.close()
        io.receive("Connecting to \(server.user)@\(server.address)…\r\n")
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

    /// The look of every session. libghostty reconfigures only when it changed.
    static func apply(font: TermFont, size: Double, theme: Theme) {
        controller.setTerminalConfiguration(TerminalConfiguration { config in
            config.withFontFamily(font.family)
            config.withFontSize(Float(size))
            theme.colors(&config)
        })
    }

    private func received(_ bytes: ArraySlice<UInt8>) {
        if state == .connecting { state = .live }
        io.receive(Data(bytes))
    }

    private func ended(_ message: String?) {
        guard let message else { return close() }
        state = .ended(message)
        io.receive("\r\n\u{1b}[33m\(message)\u{1b}[0m\r\nEnter: reconnect · Esc: close\r\n")
    }

    /// The terminal's keys, encoded by libghostty.
    private func send(_ bytes: [UInt8]) {
        guard case .ended = state else { return session?.send(bytes[...]) ?? () }
        switch bytes {
        case [13]: connect()
        case [27]: close()
        default: break
        }
    }

    private func resized(cols: Int, rows: Int) {
        size = (cols, rows)
        session?.resize(cols: cols, rows: rows)
    }

    func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        if let url = URL(string: url) { UIApplication.shared.open(url) }
    }
}

extension TerminalModel: Identifiable {}

extension TerminalModel.State {
    /// What the color says, for VoiceOver.
    var label: LocalizedStringKey {
        switch self {
        case .connecting: "Connecting"
        case .live: "Connected"
        case .ended: "Disconnected"
        }
    }

    func color(_ theme: Theme) -> SwiftUI.Color {
        switch self {
        case .connecting: theme.ansiColor(11)
        case .live: theme.ansiColor(10)
        case .ended: theme.ansiColor(9)
        }
    }
}

/// libghostty's terminal view with the app's ⌘ commands, and the on-screen keyboard only on request.
final class DeckTerminal: UITerminalView {
    struct Command {
        let input: String
        let title: String
        let action: () -> Void
    }

    var commands: [Command] = []
    /// After it took the keys, from a tap or in code.
    var tookKeys: () -> Void = {}
    var keyboardShown = false {
        didSet { if keyboardShown != oldValue { reloadInputViews() } }
    }
    private let noKeyboard = UIView()

    /// An empty keyboard while hidden, so focus never raises the on-screen one; nil is the system keyboard.
    override var inputView: UIView? { keyboardShown ? nil : noKeyboard }

    /// A tap still clicks, but only focuses (and so raises the keyboard when Settings says so, see
    /// Sessions.keyboardUp): resigning would cut off the Bluetooth keyboard too.
    override func toggleSoftwareKeyboard() { _ = becomeFirstResponder() }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        tookKeys()
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + commands.map {
            let command = UIKeyCommand(title: $0.title, action: #selector(runCommand), input: $0.input, modifierFlags: .command)
            command.wantsPriorityOverSystemBehavior = true  // ⌘W and ⌘, are the system's Close and Settings otherwise
            return command
        }
    }

    /// libghostty sends every press to the terminal, where ⌘= zoomed it instead of changing the app's size; the
    /// app's chords stop here.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // One set can hold ⌘ and the letter together.
        let chords = presses.filter { press in
            guard let key = press.key,
                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]) == .command else { return false }
            return run(key.charactersIgnoringModifiers)
        }
        super.pressesBegan(presses.subtracting(chords), with: event)
    }

    @objc private func runCommand(_ command: UIKeyCommand) {
        _ = run(command.input ?? "")
    }

    /// The chord arrives as a key command, to pressesBegan, or both: the first runs it, for this runloop turn.
    private var claimed: String?
    private func run(_ input: String) -> Bool {
        guard let command = commands.first(where: { $0.input == input }) else { return false }
        if claimed != input {
            claimed = input
            DispatchQueue.main.async { [weak self] in self?.claimed = nil }
            command.action()
        }
        return true
    }
}

/// Shows one pane's terminal; the session owns it, this only gives it a place on screen.
private struct TerminalHost: UIViewRepresentable {
    let model: TerminalModel
    /// The pane with the keys, which it takes once it is on screen.
    let focused: Bool
    /// Its tab is the one showing; a hidden tab's terminal stops drawing but keeps its place.
    let visible: Bool
    let keyboardShown: Bool
    let fontSize: Double
    let font: TermFont
    let theme: Theme
    let commands: [DeckTerminal.Command]

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ host: UIView, context: Context) {
        let terminal = model.terminal
        // Until the terminal arrives (a runloop later, below), the theme's background, not the grey under the panes.
        host.backgroundColor = UIColor(theme.bg)
        terminal.setSurfaceVisible(visible)
        terminal.commands = commands
        terminal.keyboardShown = keyboardShown
        TerminalModel.apply(font: font, size: fontSize, theme: theme)
        // After SwiftUI's update, not inside it: the terminal taken off hands the keyboard focus to SwiftUI's own
        // view, which then read the graph mid-update, locked up in a cycle and was killed switching tabs. A pane
        // leaving the screen has let go of the keys before (Sessions.active).
        DispatchQueue.main.async {
            guard terminal.superview !== host else { return }
            host.subviews.forEach { $0.removeFromSuperview() }
            terminal.frame = host.bounds
            terminal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(terminal)
            if focused { _ = terminal.becomeFirstResponder() }
        }
    }
}

/// A tab's panes as halves of the longer side: side by side in landscape, stacked upright.
struct PaneGrid: Layout {
    static let gap: CGFloat = 1

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (pane, frame) in zip(subviews, Self.frames(subviews.count, in: bounds)) {
            pane.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
    }

    static func frames(_ count: Int, in bounds: CGRect) -> [CGRect] {
        count > 0 ? cells(count, perLine: count, in: bounds, wide: bounds.width >= bounds.height, gap: gap) : []
    }
}

/// `count` cells in lines of `perLine`, laid along the width (`wide`) or the height; the last line's cells share all
/// of it.
func cells(_ count: Int, perLine: Int, in bounds: CGRect, wide: Bool, gap: CGFloat) -> [CGRect] {
    let lines = (count + perLine - 1) / perLine
    let (along, across) = wide ? (bounds.width, bounds.height) : (bounds.height, bounds.width)
    let depth = (across - gap * CGFloat(lines - 1)) / CGFloat(lines)
    return (0..<count).map { i in
        let line = i / perLine, slot = i % perLine
        let slots = min(perLine, count - line * perLine)
        let length = (along - gap * CGFloat(slots - 1)) / CGFloat(slots)
        let a = CGFloat(slot) * (length + gap), c = CGFloat(line) * (depth + gap)
        return wide ? CGRect(x: bounds.minX + a, y: bounds.minY + c, width: length, height: depth)
                    : CGRect(x: bounds.minX + c, y: bounds.minY + a, width: depth, height: length)
    }
}

/// The bar's keys on a narrow screen: as few rows as fit, as even as they go, each the full width.
struct KeyRows: Layout {
    static let gap: CGFloat = 3, minWidth: CGFloat = 46, height: CGFloat = 30

    /// (rows, keys per row) for this many keys across this width.
    static func shape(_ count: Int, width: CGFloat) -> (rows: Int, perRow: Int) {
        let fit = max(Int((width + gap) / (minWidth + gap)), 1)
        let rows = max((count + fit - 1) / fit, 1)
        return (rows, max((count + rows - 1) / rows, 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(subviews.count) * (Self.minWidth + Self.gap) - Self.gap
        let rows = CGFloat(Self.shape(subviews.count, width: width).rows)
        return CGSize(width: width, height: rows * Self.height + (rows - 1) * Self.gap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = cells(subviews.count, perLine: Self.shape(subviews.count, width: bounds.width).perRow,
                           in: bounds, wide: true, gap: Self.gap)
        for (key, frame) in zip(subviews, frames) { key.place(at: frame.origin, proposal: ProposedViewSize(frame.size)) }
    }
}

/// Hold a finger on the terminal, then slide it: every step sends an arrow key, with a tick.
final class ArrowPad: NSObject, UIGestureRecognizerDelegate {
    enum Arrow { case left, right, up, down }

    private weak var view: UITerminalView?
    private var anchor = CGPoint.zero
    private let tick = UISelectionFeedbackGenerator()

    func attach(to view: UITerminalView) {
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
            // A finger held still first also opened libghostty's edit menu; sliding means arrows.
            if !arrows.isEmpty {
                view?.interactions.compactMap { $0 as? UIEditMenuInteraction }.forEach { $0.dismissMenu() }
            }
            for arrow in arrows {
                switch arrow {
                case .left: view?.sendKey(.arrowLeft)
                case .right: view?.sendKey(.arrowRight)
                case .up: view?.sendKey(.arrowUp)
                case .down: view?.sendKey(.arrowDown)
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

    /// Alongside libghostty's own long press, whose edit menu still opens when the finger stays put.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other is UILongPressGestureRecognizer
    }
}

/// The thin strip under the terminal: a tab per open session, and the keys a small keyboard lacks, as Settings
/// lists them.
private struct KeyBar: View {
    @ObservedObject var model: TerminalModel
    @ObservedObject var sessions: Sessions
    let theme: Theme
    let font: TermFont
    let panel: () -> Void
    @AppStorage("barKeys") private var barKeys = BarKey.store(BarKey.standard)

    var body: some View {
        // One row when the keys fit beside a little room for the tabs. Narrower (a phone held upright, a slim iPad
        // window), the keys get rows of their own under the tabs, so none hides off screen. Only the wide one keeps
        // clear of the rounded corners beside it; upright, the corners are below, past the home indicator.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                tabs.frame(minWidth: 80, idealWidth: 80, maxWidth: .infinity, alignment: .leading)
                keys(fill: false)
                icons
            }
            .frame(height: 30)
            .padding(.horizontal, 26)
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    tabs.frame(maxWidth: .infinity, alignment: .leading)
                    icons
                }
                .frame(height: 30)
                KeyRows { keys(fill: true) }
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 8)
        }
        .font(font.font(12))
        .foregroundStyle(theme.fg)
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .top) { Rectangle().fill(theme.fg.opacity(0.08)).frame(height: 1).ignoresSafeArea() }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
                ForEach(sessions.tabs) { tab in
                    SessionTab(sessions: sessions, panes: tab.panes, active: tab.panes.contains { $0 === model },
                               theme: theme, font: font)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func keys(fill: Bool) -> some View {
        if case .ended = model.state {
            key("connect", "Reconnect", fill: fill) { model.connect() }
        }
        ForEach(BarKey.list(barKeys)) { bar in
            key(bar.title, bar.label, fill: fill) { bar.press(on: model.terminal) }
        }
    }

    @ViewBuilder private var icons: some View {
        icon(sessions.keyboardUp ? "keyboard.chevron.compact.down" : "keyboard",
             sessions.keyboardUp ? "Hide keyboard" : "Show keyboard") {
            let up = !sessions.keyboardUp
            _ = model.terminal.becomeFirstResponder()  // which raises it when Settings says so; the press decides
            sessions.keyboardUp = up
        }
        icon("sidebar.right", "Panel", panel)
    }

    /// `fill`: as wide as its grid cell.
    private func key(_ title: String, _ label: LocalizedStringKey, fill: Bool,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 7)
                .frame(minWidth: 30, maxWidth: fill ? .infinity : nil, minHeight: fill ? 30 : 24)
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

/// One tab in the key bar: each pane's host logo in its connection's color, and its name. A tap on another tab
/// switches to it; on the one showing, or held, it opens the tab's menu.
private struct SessionTab: View {
    @ObservedObject var sessions: Sessions
    let panes: [TerminalModel]
    let active: Bool
    let theme: Theme
    let font: TermFont

    var body: some View {
        if active {
            Menu { menu } label: { label }
                .accessibilityAddTraits(.isSelected)
        } else {
            Button { sessions.active = panes.first } label: { label }
                .buttonStyle(.plain)
                .contextMenu { menu }
        }
    }

    private var label: some View {
        HStack(spacing: 7) {
            ForEach(panes) { pane in
                // A line between a tab's panes, so one tab of two reads apart from two tabs.
                if pane !== panes.first { Rectangle().fill(theme.fg.opacity(0.3)).frame(width: 1, height: 12) }
                PaneLabel(model: pane, theme: theme, font: font)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
        .foregroundStyle(theme.fg.opacity(active ? 1 : 0.5))
        .background(active ? theme.raised : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder private var menu: some View {
        if let first = panes.first {
            if panes.count < Sessions.maxPanes {
                Button("Split", systemImage: "rectangle.split.2x1") { sessions.split(first.server, beside: first) }
            }
            Button("New tab", systemImage: "plus.square.on.square") { sessions.newTab(first.server) }
        }
        if panes.count > 1 {
            Divider()
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                Button(role: .destructive) { sessions.close(pane) } label: {
                    Label("Close pane \(index + 1)", systemImage: "xmark.square")
                    Text(verbatim: pane.server.title)
                }
            }
        }
        Divider()
        Button(panes.count > 1 ? "Close tab" : "Disconnect", systemImage: "xmark", role: .destructive) {
            panes.forEach(sessions.close)
        }
    }
}

private struct PaneLabel: View {
    @ObservedObject var model: TerminalModel
    let theme: Theme
    let font: TermFont

    var body: some View {
        HStack(spacing: 5) {
            SystemMark(system: model.server.system, font: font, size: 11)
                .foregroundStyle(model.state.color(theme))
            Text(verbatim: model.server.title).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.server.title))
        .accessibilityValue(Text(model.state.label))
    }
}

/// The right-hand panel: the connection, snippets, and the host's files. The look is in Settings.
private struct SidePanel: View {
    enum Tab: String { case snippets, files }

    @ObservedObject var model: TerminalModel
    let font: TermFont
    let theme: Theme
    let back: () -> Void
    let disconnect: () -> Void
    let hide: () -> Void
    let newTab: () -> Void
    let split: () -> Void
    let settings: () -> Void
    let expandFiles: () -> Void
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
                    Text(verbatim: model.server.login)
                        .font(font.font(11))
                        .foregroundStyle(theme.fg.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                IconKey("arrow.clockwise", "Reconnect", theme: theme) { model.connect() }
                IconKey("xmark", "Disconnect", theme: theme, action: disconnect)
                Menu {
                    Button("New tab", systemImage: "plus.square.on.square", action: newTab)
                    Button("Split", systemImage: "rectangle.split.2x1", action: split)
                } label: {
                    IconKey.face("plus", theme: theme)
                }
                .accessibilityLabel("Another connection")
                IconKey("gearshape", "Settings", theme: theme, action: settings)
                IconKey("square.grid.2x2", "Back to list", theme: theme, action: back)
            }
            Picker("Section", selection: $tab) {
                Text("Snippets").tag(Tab.snippets)
                Text("Files").tag(Tab.files)
            }
            .pickerStyle(.segmented)
            switch tab {
            case .snippets: ScrollView { snippetList }.scrollIndicators(.hidden)
            case .files:
                FilesView(files: model.files, live: model.state == .live, theme: theme, font: font,
                          corner: ("arrow.up.left.and.arrow.down.right", "Full screen", expandFiles))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .foregroundStyle(theme.fg)
        // The background reaches the screen edge; the content stays in the safe area, clear of the rounded corners
        // and the camera.
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .leading) { Rectangle().fill(theme.fg.opacity(0.1)).frame(width: 1).ignoresSafeArea() }
        .frame(maxWidth: .infinity, alignment: .trailing)
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
        model.terminal.insertText(command)
        if run { model.terminal.sendKey(.enter) }
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
                    hint("arrow.left", "Swipe in from the right edge", "Snippets and files", leading: false)
                }
                .padding(.horizontal, 24)
                Spacer()
                Text("⌘W back · ⌘1–9 devices · ⌘T tab · ⌘D split · ⌘, panel")
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
