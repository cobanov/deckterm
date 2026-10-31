# DeckTerm

A small SSH terminal for iPhone and iPad, made for the phone in the lid of a [cyberdeck](https://github.com/cobanov/cyberdeck).
The terminal is [libghostty](https://ghostty.org), Ghostty's core, drawn with Metal.
Site: [deckterm.cobanov.dev](https://deckterm.cobanov.dev).

The iPhone stays in landscape unless Settings picks Portrait or Auto; the iPad turns and resizes freely. The
Bluetooth keyboard types, so the on-screen keyboard stays hidden until the keyboard key in the bar or Settings brings it
up, and it stays as last chosen. Saved devices show as cards; tap one, or press ⌘1–9, to open its terminal (⌘N adds a
device). A device can have any number of connections: ⌘T opens another in a new tab, ⌘D splits the screen in two with
another beside it, ⌘[ ⌘] move between panes, and a tap on the tab showing opens its menu (split, new tab, close a pane
or the tab). While connections are open, a tab bar under the cards (iOS 26's floating glass one) switches between
Vaults, the devices, and Connections, the open sessions. On iOS 26 and later the app keeps running in the background
while connections are open, shown in the Dynamic Island and on the Lock Screen, where it can be stopped. A thin bar
under the terminal holds the tabs and the keys a small keyboard lacks (esc, tab, enter, ^C, arrows). Hold a finger on the
terminal and slide it to send arrow keys. Swipe in from the left edge to go back to the list, from the right edge for
the panel: snippets (tap runs one, a long press pastes or deletes it) and the host's files over SFTP, on the shell's own
connection (tap a folder to open it, a file to save or share it; upload from Files; hold one to rename or delete it;
full screen shows dates). Settings, the gear in the list and in the panel, picks and orders the bar's keys and sets
the font (JetBrains Mono, Fira Code, IBM Plex Mono, SF Mono, Menlo), its size, the theme (One Dark, Darcula,
Catppuccin, Dracula, Gruvbox, Nord, Tokyo Night, Solarized and three black ones), which colors the whole app, and the
iPhone's orientation. ⌘W goes back, ⌘= and ⌘- resize the text, ⌘, opens the panel. The bundled fonts are SIL OFL; their
licenses sit beside them in `app/DeckTerm/Fonts/`.

One ed25519 private key serves every device: run `pbcopy < ~/.ssh/id_ed25519` on the Mac and paste it under SSH key in a
device's form. RSA keys are refused when pasted, since Citadel signs them with SHA-1, which OpenSSH 8.8 and later reject.
A device with a password uses that instead. Host keys are pinned on first connect, and a changed key is refused.

Settings, from the list, exports a backup (`deckterm-backup.json`: devices, pinned host keys, theme, font, snippets, the bar's keys)
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
`xcodebuild test -scheme DeckTerm -destination 'platform=iOS Simulator,name=iPhone 17'`.
To get Control or Escape on Caps Lock, use iOS Settings → General → Keyboard → Hardware Keyboard → Modifier Keys.

## Site

`site/` is deckterm.cobanov.dev, static files on Cloudflare: `cd site && wrangler deploy`. After changing
`app/DeckTerm/Acknowledgements.txt`, run `python3 site/build_licenses.py` to rebuild `licenses.html`.
