# DeckTerm

A small SSH terminal for iPhone, made for the phone in the lid of a [cyberdeck](https://github.com/cobanov/cyberdeck).
Site: [deckterm.cobanov.dev](https://deckterm.cobanov.dev).

It runs in landscape only. The Bluetooth keyboard types, so the on-screen keyboard stays hidden until the keyboard key
in the bar brings it up. Saved devices show as cards; tap one, or press ⌘1–9, to open its terminal (⌘N adds a
device). A thin bar under the terminal holds the connection status and the keys a small keyboard lacks (esc, tab, ^C,
arrows). Hold a finger on the terminal and slide it to send arrow keys. Swipe in from the left edge to go back to the
list, from the right edge for the panel: snippets (tap runs one, a long press pastes or deletes it), the font
(JetBrains Mono, Fira Code, IBM Plex Mono, SF Mono, Menlo), its size, and the theme (One Dark, Darcula, Catppuccin,
Dracula, Gruvbox, Nord, Tokyo Night, Solarized and three black ones), which colors the whole app. ⌘W goes back, ⌘= and
⌘- resize the text, ⌘, opens the panel. The bundled fonts are SIL OFL; their licenses sit beside them in
`app/DeckTerm/Fonts/`.

One private key serves every device: run `pbcopy < ~/.ssh/id_ed25519` on the Mac and paste it under the key button.
A device with a password uses that instead. Host keys are pinned on first connect, and a changed key is refused.

The `…` menu above the cards exports a backup (`deckterm-yedek.json`: devices, pinned host keys, theme, font, snippets)
and restores one, also from the first-launch screen. Passwords and the private key stay out of it, since the file may
end up in Files or iCloud; paste the key once on the new phone. A restore adds or replaces devices by id and never
overwrites a host key the phone has already pinned.

## Build

```sh
cd app && xcodegen generate      # then open DeckTerm.xcodeproj, or:
scripts/release.sh install       # Ad Hoc build onto the iPhone 12 mini over USB
scripts/release.sh testflight    # upload to TestFlight
```

The tests log into this Mac's own sshd (Remote Login on) with `~/.ssh/id_ed25519`:
`xcodebuild test -scheme DeckTerm -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation`.
To get Control or Escape on Caps Lock, use iOS Settings → General → Keyboard → Hardware Keyboard → Modifier Keys.

## Site

`site/` is deckterm.cobanov.dev, static files on Cloudflare: `cd site && wrangler deploy`. After changing
`app/DeckTerm/Acknowledgements.txt`, run `python3 site/build_licenses.py` to rebuild `licenses.html`.
