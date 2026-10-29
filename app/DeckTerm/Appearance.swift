import SwiftUI
import SwiftTerm
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

    /// SwiftTerm's own default palette, which the black themes keep.
    private static let terminalApp: [UInt32] = [
        0x000000, 0xC23621, 0x25BC24, 0xADAD27, 0x492EE1, 0xD338D3, 0x33BBC8, 0xCBCCCD,
        0x818383, 0xFC391F, 0x31E722, 0xEAEC23, 0x5833FF, 0xF935F8, 0x14F0F0, 0xE9EBEB,
    ]

    var background: UIColor { UIColor(hex[0]) }
    var foreground: UIColor { UIColor(hex[1]) }
    var cursor: UIColor { UIColor(hex[2]) }
    var selection: UIColor { UIColor(hex[3]) }
    var ansi: [SwiftTerm.Color] {
        hex[5...].map { SwiftTerm.Color(red: UInt16($0 >> 16 & 0xFF) * 257, green: UInt16($0 >> 8 & 0xFF) * 257,
                                        blue: UInt16($0 & 0xFF) * 257) }
    }

    var bg: SwiftUI.Color { SwiftUI.Color(background) }
    var fg: SwiftUI.Color { SwiftUI.Color(foreground) }
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

    func font(_ size: CGFloat, bold: Bool = false) -> SwiftUI.Font { SwiftUI.Font(uiFont(size, bold: bold) as CTFont) }

    /// Registers the bundled faces at launch, instead of a hand-kept Info.plist for UIAppFonts.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

/// The app icon's `>_`, drawn in the current theme.
struct Mark: View {
    let theme: Theme
    let font: TermFont
    let size: CGFloat

    var body: some View {
        Text(verbatim: ">_")
            .font(font.font(size * 0.4, bold: true))
            .foregroundStyle(theme.accent)
            .frame(width: size, height: size)
            .background(theme.raised, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
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
final class Housing: ObservableObject {
    static let shared = Housing()
    @Published private(set) var onLeft = true
    private var watcher: NSKeyValueObservation?

    func watch(_ scene: UIWindowScene) {
        guard watcher == nil else { return }
        watcher = scene.observe(\.effectiveGeometry, options: [.initial, .new]) { [weak self] scene, _ in
            // Interface landscapeRight has the home side on the right, so the top of the phone on the left.
            let onLeft = scene.effectiveGeometry.interfaceOrientation != .landscapeLeft
            DispatchQueue.main.async { if self?.onLeft != onLeft { self?.onLeft = onLeft } }
        }
    }
}

extension View {
    /// The system inset on the camera's side, only `corner` on the other.
    func clearsHousing(_ onLeft: Bool, corner: CGFloat = 20) -> some View {
        padding(onLeft ? .trailing : .leading, corner)
            .ignoresSafeArea(.container, edges: onLeft ? .trailing : .leading)
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
