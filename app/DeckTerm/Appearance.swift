import SwiftUI
import GhosttyTerminal
import CoreText

/// Terminal color schemes. The chosen one also colors the app around the terminal.
/// Raw values are stored in UserDefaults, so they never change.
enum Theme: String, CaseIterable, Identifiable {
    case classic, green, amber, oneDark, darcula, catppuccin, dracula, gruvbox, nord, tokyoNight, solarized

    var id: Self { self }

    var name: String {
        switch self {
        case .classic: "DeckTerm"
        case .green: "Phosphor"
        case .amber: "Amber"
        case .oneDark: "One Dark"
        case .darcula: "Darcula"
        case .catppuccin: "Catppuccin"
        case .dracula: "Dracula"
        case .gruvbox: "Gruvbox"
        case .nord: "Nord"
        case .tokyoNight: "Tokyo Night"
        case .solarized: "Solarized"
        }
    }

    /// Background, foreground, cursor, selection, accent, then ANSI 0–15 (each theme's published values).
    private var hex: [UInt32] {
        switch self {
        case .classic: [0x000000, 0xE6E6E6, 0x3CE882, 0x2A4536, 0x3CE882] + Self.terminalApp
        case .green: [0x000000, 0x4DFF73, 0x4DFF73, 0x1E4D2A, 0x4DFF73] + Self.terminalApp
        case .amber: [0x000000, 0xFFB840, 0xFFB840, 0x4D3A14, 0xFFB840] + Self.terminalApp
        case .oneDark: [0x282C34, 0xABB2BF, 0x528BFF, 0x3E4451, 0x61AFEF,
                        0x3F4451, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xD7DAE0,
                        0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xFFFFFF]
        case .darcula: [0x2B2B2B, 0xA9B7C6, 0xBBBBBB, 0x214283, 0xCC7832,
                        0x000000, 0xFF6B68, 0xA8C023, 0xD6BF55, 0x5394EC, 0xAE8ABE, 0x299999, 0xBBBBBB,
                        0x555555, 0xFF8785, 0xA8C023, 0xFFFF00, 0x7EAEF1, 0xFF99FF, 0x6CDADA, 0xFFFFFF]
        case .catppuccin: [0x1E1E2E, 0xCDD6F4, 0xF5E0DC, 0x585B70, 0xCBA6F7,
                           0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE,
                           0x585B70, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xA6ADC8]
        case .dracula: [0x282A36, 0xF8F8F2, 0xF8F8F2, 0x44475A, 0xBD93F9,
                        0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
                        0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF]
        case .gruvbox: [0x282828, 0xEBDBB2, 0xEBDBB2, 0x504945, 0xFE8019,
                        0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984,
                        0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2]
        case .nord: [0x2E3440, 0xD8DEE9, 0xD8DEE9, 0x434C5E, 0x88C0D0,
                     0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
                     0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4]
        case .tokyoNight: [0x1A1B26, 0xC0CAF5, 0xC0CAF5, 0x33467C, 0x7AA2F7,
                           0x15161E, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xA9B1D6,
                           0x414868, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xC0CAF5]
        case .solarized: [0x002B36, 0x839496, 0x93A1A1, 0x073642, 0x268BD2,
                          0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                          0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3]
        }
    }

    /// SwiftTerm's default palette, which the black themes kept when the terminal moved to libghostty.
    private static let terminalApp: [UInt32] = [
        0x000000, 0xC23621, 0x25BC24, 0xADAD27, 0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
        0x818383, 0xFC391F, 0x31E722, 0xEAEC23, 0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB,
    ]

    /// The terminal's colors, as libghostty config lines.
    func colors(_ config: inout TerminalConfiguration.Builder) {
        let hex = hex.map { String(format: "#%06X", $0) }
        config.withBackground(hex[0])
        config.withForeground(hex[1])
        config.withCursorColor(hex[2])
        config.withSelectionBackground(hex[3])
        for index in 0..<16 { config.withPalette(index, color: hex[5 + index]) }
    }

    var bg: SwiftUI.Color { SwiftUI.Color(UIColor(hex[0])) }
    var fg: SwiftUI.Color { SwiftUI.Color(UIColor(hex[1])) }
    var accent: SwiftUI.Color { SwiftUI.Color(UIColor(hex[4])) }
    func ansiColor(_ index: Int) -> SwiftUI.Color { SwiftUI.Color(UIColor(hex[5 + index])) }
    /// Panels and cards: the background a step toward the foreground.
    var surface: SwiftUI.Color { SwiftUI.Color(UIColor(blend(0.07))) }
    /// Keys and fields on a surface.
    var raised: SwiftUI.Color { SwiftUI.Color(UIColor(blend(0.14))) }

    private func blend(_ amount: Double) -> UInt32 {
        let (b, f) = (hex[0], hex[1])
        return [16, 8, 0].reduce(0) { sum, shift in
            let mixed = Double(b >> shift & 0xFF) * (1 - amount) + Double(f >> shift & 0xFF) * amount
            return sum | UInt32(mixed.rounded()) << shift
        }
    }
}

/// Monospaced faces. The three bundled ones are SIL OFL (licenses beside them in Fonts/).
enum TermFont: String, CaseIterable, Identifiable {
    case jetBrains, fira, plex, sfMono, menlo

    var id: Self { self }

    var name: String {
        switch self {
        case .jetBrains: "JetBrains Mono"
        case .fira: "Fira Code"
        case .plex: "IBM Plex Mono"
        case .sfMono: "SF Mono"
        case .menlo: "Menlo"
        }
    }

    private var faces: (regular: String, bold: String)? {
        switch self {
        case .jetBrains: ("JetBrainsMono-Regular", "JetBrainsMono-Bold")
        case .fira: ("FiraCode-Regular", "FiraCode-Bold")
        case .plex: ("IBMPlexMono", "IBMPlexMono-Bold")
        case .menlo: ("Menlo-Regular", "Menlo-Bold")
        case .sfMono: nil
        }
    }

    func uiFont(_ size: CGFloat, bold: Bool = false) -> UIFont {
        guard let faces, let font = UIFont(name: bold ? faces.bold : faces.regular, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        return font
    }

    /// The name libghostty's `font-family` finds it by; it picks the bold face itself.
    var family: String { uiFont(13).familyName }

    func font(_ size: CGFloat, bold: Bool = false) -> SwiftUI.Font { SwiftUI.Font(uiFont(size, bold: bold) as CTFont) }

    /// Registers the bundled faces at launch, instead of a hand-kept Info.plist for UIAppFonts.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

/// The app icon's hinge, drawn flat in the current theme: the lid in the accent, the base a step deeper.
struct Mark: View {
    let theme: Theme
    let size: CGFloat

    var body: some View {
        ZStack {
            Hinge(arm: 1).fill(theme.accent.opacity(0.6))
            Hinge(arm: -1).fill(theme.accent)
            Hinge(arm: nil).fill(theme.accent, style: FillStyle(eoFill: true))
        }
        .padding(size * 0.2)
        .frame(width: size, height: size)
        .background(theme.raised, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// One part of the icon's mark, in the 256-unit grid of site/public/img/icon.svg: a `>` whose arms (30° each way,
/// 40 wide) open on a pin at (183, 128). `arm` -1 is the lid, 1 the base, nil the pin with its hole.
struct Hinge: Shape {
    let arm: CGFloat?

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 192  // the mark's box is 32...224 on both axes
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.midX + (x - 128) * s, y: rect.midY + (y - 128) * s) }
        var path = Path()
        guard let arm else {
            for r: CGFloat in [30, 10] { path.addEllipse(in: CGRect(origin: p(183 - r, 128 - r), size: CGSize(width: 2 * r * s, height: 2 * r * s))) }
            return path
        }
        let ux = -cos(CGFloat.pi / 6), uy = arm * sin(CGFloat.pi / 6)
        // From inside the pin's ring (18) out to the end (150), 20 either side of the arm's centre line.
        path.addLines([(18, 20), (150, 20), (150, -20), (18, -20)].map { t, h in p(183 + t * ux - h * uy, 128 + t * uy + h * ux) })
        path.closeSubpath()
        return path
    }
}

/// The host's logo once a connection has learned what it runs, else the prompt. Colored by the caller.
struct SystemMark: View {
    let system: String?
    let font: TermFont
    let size: CGFloat

    var body: some View {
        Group {
            switch system {
            case "macos": Image(systemName: "applelogo").font(.system(size: size))
            case let name?: Image(name).resizable().scaledToFit().frame(width: size, height: size)
            case nil: Text(verbatim: ">").font(font.font(size * 1.1, bold: true))
            }
        }
        .frame(width: size + 2)
        .accessibilityHidden(true)
    }
}

/// Which side of the landscape screen the camera is on. iOS insets both sides by its depth;
/// the other side gives that room back and only keeps clear of the rounded corners.
/// Nil when no side has it: an iPhone held upright, or an iPad.
final class Housing: ObservableObject {
    static let shared = Housing()
    @Published private(set) var onLeft: Bool? = true
    private var watcher: NSKeyValueObservation?

    func watch(_ scene: UIWindowScene) {
        guard watcher == nil else { return }
        watcher = scene.observe(\.effectiveGeometry, options: [.initial, .new]) { [weak self] scene, _ in
            let orientation = scene.effectiveGeometry.interfaceOrientation
            // Interface landscapeRight has the home side on the right, so the top of the phone on the left.
            let onLeft = scene.traitCollection.userInterfaceIdiom == .phone && orientation.isLandscape
                ? orientation != .landscapeLeft : nil
            DispatchQueue.main.async { if self?.onLeft != onLeft { self?.onLeft = onLeft } }
        }
    }
}

extension View {
    /// The system inset on the camera's side. On the other, `corner` and `top` together keep the top corner clear of
    /// the screen's rounding: sized for the largest, 62 pt on a Pro Max, where (62 - 26)² + (62 - 12)² < 62².
    /// One view either way, so turning the phone keeps what's on screen.
    func clearsHousing(_ onLeft: Bool?, corner: CGFloat = 26, top: CGFloat = 12) -> some View {
        let side: Edge.Set = onLeft == true ? .trailing : onLeft == false ? .leading : []
        return padding(side, corner).padding(.top, onLeft == nil ? 0 : top).ignoresSafeArea(.container, edges: side)
    }
}

/// A symbol on a raised key: the side panel's and the files' buttons, one size so their rows match.
struct IconKey: View {
    let symbol: String
    let label: LocalizedStringKey
    let theme: Theme
    let action: () -> Void

    init(_ symbol: String, _ label: LocalizedStringKey, theme: Theme, action: @escaping () -> Void) {
        (self.symbol, self.label, self.theme, self.action) = (symbol, label, theme, action)
    }

    var body: some View {
        Button(action: action) { Self.face(symbol, theme: theme) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    /// Its look, for a menu that opens from the same kind of key.
    static func face(_ symbol: String, theme: Theme) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 32, height: 30)
            .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Full-width capsule button; the primary one is the theme's foreground, inverted.
struct PillStyle: ButtonStyle {
    let theme: Theme
    let font: TermFont
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font.font(15, bold: primary))
            .foregroundStyle(primary ? theme.bg : theme.fg)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(primary ? theme.fg : theme.raised, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private extension UIColor {
    convenience init(_ hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
