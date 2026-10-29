import SwiftUI

/// First launch, laid out for landscape: the mark on the left, the first steps on the right.
/// Shown in its final state, with no entrance animation.
struct WelcomeScreen: View {
    let addDevice: () -> Void
    let addKey: () -> Void
    let restore: () -> Void
    let skip: () -> Void
    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("font") private var font = TermFont.jetBrains

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Mark(theme: theme, font: font, size: 72)
                Text("deckterm")
                    .font(font.font(34, bold: true))
                    .foregroundStyle(theme.fg)
                Text("Bluetooth klavyen için SSH terminali")
                    .font(font.font(13))
                    .foregroundStyle(theme.fg.opacity(0.55))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Button(action: addDevice) { Label("Cihaz ekle", systemImage: "plus") }
                    .buttonStyle(PillStyle(theme: theme, font: font, primary: true))
                Button(action: addKey) { Label("SSH anahtarı ekle", systemImage: "key") }
                    .buttonStyle(PillStyle(theme: theme, font: font))
                Button(action: restore) { Label("Yedekten geri yükle", systemImage: "square.and.arrow.down") }
                    .buttonStyle(PillStyle(theme: theme, font: font))
                Button("Şimdilik geç", action: skip)
                    .font(font.font(13))
                    .foregroundStyle(theme.fg.opacity(0.55))
                    .padding(.top, 8)
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)  // full height, so the overlays reach the screen's corners
        .overlay(alignment: .topTrailing) {
            Button(action: skip) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .frame(width: 36, height: 36)
                    .background(theme.raised, in: Circle())
            }
            .accessibilityLabel("Kapat")
            .padding(.top, 12)
        }
        .overlay(alignment: .bottom) {
            HStack {
                Text("Sürüm \(version)")
                Spacer()
                Text("Anahtarlar ve parolalar yalnız bu iPhone'da kalır")
            }
            .font(font.font(11))
            .foregroundStyle(theme.fg.opacity(0.4))
            .padding(.bottom, 8)
        }
        .padding(.horizontal)
        .background(theme.bg.ignoresSafeArea())
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
    }
}
