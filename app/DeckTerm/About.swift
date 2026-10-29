import SwiftUI
import StoreKit

/// Version, the tip jar, and the links the App Store asks for: privacy, terms, support, licenses.
struct AboutSheet: View {
    static let tips = ["dev.cobanov.deckterm.tip.small", "dev.cobanov.deckterm.tip.medium", "dev.cobanov.deckterm.tip.large"]
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
    }

    @AppStorage("theme") private var theme = Theme.classic
    @AppStorage("font") private var font = TermFont.jetBrains
    @State private var thanked = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Mark(theme: theme, font: font, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: "DeckTerm").font(font.font(18, bold: true))
                            Text("The SSH terminal for your cyberdeck").font(.footnote).foregroundStyle(.secondary)
                            Text("Version \(Self.version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(Self.tips, id: \.self) { ProductView(id: $0).productViewStyle(.compact) }
                } header: {
                    Text("Tip jar")
                } footer: {
                    thanked ? Text("Thank you! That means a lot.")
                        : Text("DeckTerm is free, with no ads and no tracking. If it earns a place in your deck, a tip keeps it going. Tips unlock nothing.")
                }
                Section {
                    link("Website", "https://deckterm.cobanov.dev")
                    link("Support", "https://deckterm.cobanov.dev/support")
                    link("Privacy Policy", "https://deckterm.cobanov.dev/privacy")
                    link("Terms of Use", "https://deckterm.cobanov.dev/terms")
                    link("Security", "https://deckterm.cobanov.dev/security")
                    NavigationLink("Open-source licenses") { LicensesView() }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onInAppPurchaseCompletion { _, result in
                if case .success(.success(.verified(let transaction))) = result {
                    await transaction.finish()  // a consumable: finished, it is spent
                    thanked = true
                }
            }
        }
    }

    private func link(_ title: LocalizedStringKey, _ url: String) -> some View {
        Link(title, destination: URL(string: url)!)
    }
}

/// Acknowledgements.txt, one page per "### name version" section: the MIT and Apache licenses ask for their notices.
private struct LicensesView: View {
    private let sections: [(title: String, text: String)] = {
        let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")
        let all = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return all.components(separatedBy: "\n### ").dropFirst().map { section in
            let lines = section.split(separator: "\n", maxSplits: 1)
            return (String(lines[0]), lines.count > 1 ? String(lines[1]) : "")
        }
    }()

    var body: some View {
        List {
            Section {
                ForEach(sections, id: \.title) { section in
                    NavigationLink(section.title) {
                        ScrollView {
                            Text(verbatim: section.text)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding()
                        }
                        .navigationTitle(section.title)
                    }
                }
            } header: {
                Text("DeckTerm is built on these open-source projects. Thank you to their authors.")
            }
        }
        .navigationTitle("Open-source licenses")
    }
}
