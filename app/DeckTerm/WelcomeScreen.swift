import SwiftUI

/// What shows while there are no devices: the mark beside the first steps, or above them on an upright phone.
/// Shown in its final state, with no entrance animation.
struct WelcomeScreen: View {
    let addDevice: () -> Void
    let restore: () -> Void
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("font") private var font = TermFont.jetBrains
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.verticalSizeClass) private var height

    var body: some View {
        let layout = width == .compact && height == .regular ? AnyLayout(VStackLayout(spacing: 40)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            VStack(spacing: 14) {
                Mark(theme: theme, size: 72)
                Text(verbatim: "deckterm")
                    .font(font.font(34, bold: true))
                    .foregroundStyle(theme.fg)
                Text("The SSH terminal for your cyberdeck")
                    .font(font.font(13))
                    .foregroundStyle(theme.fg.opacity(0.55))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Button(action: addDevice) { Label("Add a device", systemImage: "plus") }
                    .buttonStyle(PillStyle(theme: theme, font: font, primary: true))
                Button(action: restore) { Label("Restore from backup", systemImage: "square.and.arrow.down") }
                    .buttonStyle(PillStyle(theme: theme, font: font))
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal)
        .background(theme.bg.ignoresSafeArea())
    }
}
