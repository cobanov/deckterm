import SwiftUI

/// What shows while there are no devices, laid out for landscape: the mark on the left, the first steps on the right.
/// Shown in its final state, with no entrance animation.
struct WelcomeScreen: View {
    let addDevice: () -> Void
    let addKey: () -> Void
    let restore: () -> Void
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("font") private var font = TermFont.jetBrains

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Mark(theme: theme, font: font, size: 72)
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
                Button(action: addKey) { Label("Add an SSH key", systemImage: "key") }
                    .buttonStyle(PillStyle(theme: theme, font: font))
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
