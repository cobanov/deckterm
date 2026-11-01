# Rehearsal: DeckTerm hero

Gold: `dark-hero` (depth from surface steps on black, one lit color) and `phone-touch` (a phone app told as one object).
Kept their quiet black ground and one accent; changed everything else to DeckTerm's own screens, measured from the
app's source (874 × 402 pt landscape, 62 pt island inset, 30 pt key bar above the 21 pt bottom safe area, the classic
theme and Terminal.app palette).

Beats: device list → ⌘1 (keycaps under the phone, nuc's card steps up) → the terminal cover slides up, nuc's logo
yellow → green, "Welcome to Ubuntu" → `uptime -p` ↵ → `docker ps --format {{.Names}}` ↵ → six containers → hold →
`exit` ↵, `logout` → cover goes down onto the same list. Loop about 11 s.

Wide (1000 × 588): the phone whole, an even 56 px band above and below; the keystrokes show in the one below.
Compact (350 × 324, below 560 px): no camera. The phone at 0.588, its left edge on the column's, running off the
right edge of the screen (the page lets the figure past its 20 px padding below 600 px); the scale puts the crop in
the gap after the key bar's ^Z.

Captured: playground at 1100 and 390, the real page at 1280 and 390, `--states`, reduced motion at both widths,
layout probed at 360, 390, 575, 585, 599, 600, 640 and 1280 (no horizontal scroll at any).

Fresh-eye review, acted on: the terminal's lower third was empty (six containers now), the 390 zoom showed a sliver
of bezel and the whole-phone shot was unreadable (camera dropped for the fixed crop above), the key bar sat in the
screen's rounded corner (moved above the safe area, as the app has it), keystrokes only on ⌘1 (↵ now on every
command), a 2.5 s still at the seam (first wait 1400 → 900 ms).

Film lines left:
- `uneven padding` on `.dt-screen` / `.dt-term`: the screen's content sits 62 pt from the island side and 12 pt from
  the top, as iOS lays out landscape and the app draws it; the check reads the turned screen as a card.
- `kit override` (real page only): the bundled `hero.css` carries the kit's own phone rules, which the check can't
  tell from the scene's; the playground has no such line.
- `small text` at 390: the cards' logins and the key bar's keys (12 pt in the app) come out about 7.5 px. The story's
  text, the terminal, is about 11 px.
- 580–599 px wide: the figure has its bleed but the stage draws the wide design, 10 px right of center. Nothing is
  cut; it keeps the stage from ever drawing the phone design without the bleed.

Not checked: a real iPhone or Safari (Chrome only), frame pacing on a device, pause when the tab is hidden.
