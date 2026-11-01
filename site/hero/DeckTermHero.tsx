import type { ReactNode } from 'react'
import { Keyboard, PanelRight, Plus, Settings } from 'lucide-react'
// From the kit's own files, not its index, so a page bundles only these parts and their styles
import { Stage } from './kit/stage'
import { Phone } from './kit/phone'
import type { Act } from './kit/act'
import './deckterm.css'

import alpine from './os/alpinelinux.svg'
import arch from './os/archlinux.svg'
import debian from './os/debian.svg'
import fedora from './os/fedora.svg'
import freebsd from './os/freebsd.svg'
import kali from './os/kalilinux.svg'
import mint from './os/linuxmint.svg'
import nixos from './os/nixos.svg'
import pi from './os/raspberrypi.svg'
import ubuntu from './os/ubuntu.svg'
import windows from './os/windows.svg'

// DeckTerm's site hero: an iPhone held sideways, driven from the keyboard.
// Beats: the device list (the opening); ⌘1 on the deck's keyboard opens nuc,
// the terminal covering the list as the app's full-screen cover does; the
// session connects (the tab's logo turns from yellow to green, Ubuntu says
// hello); two commands are typed and answered; after a hold, `exit` logs out
// and the cover goes down onto the same list, which is where the loop began.
//
// Everything on the phone is laid out in the app's own points (874 × 402,
// the island's side inset 62, the other side 8 on the list and 26 on the
// terminal, 13pt JetBrains Mono, a 30pt key bar) and drawn in its classic
// theme: black, #e6e6e6, the green accent, surfaces mixed 7% and 14% toward
// the foreground. The terminal's colors are the app's Terminal.app palette.
//
// The kit's Phone is upright only, so the phone is turned a quarter left and
// the screen's contents a quarter right inside it: the island ends up on the
// left, where DeckTerm keeps its housing inset.
//
// Real strings: the twelve devices (their names, logins and ⌘ hints), the
// two commands and their output, the key bar. The terminal's content matches
// the screen in the cyberdeck renders further down the page.

type S = {
  pressed: boolean
  term: boolean
  live: boolean
  c1: string
  o1: boolean
  c2: string
  o2: number
  c3: string
  bye: boolean
}

const C1 = 'uptime -p'
const C2 = 'docker ps --format {{.Names}}'
const C3 = 'exit'
const CONTAINERS = ['watchdock', 'grafana', 'prometheus', 'caddy', 'ntfy', 'terminal-army']

const initial: S = { pressed: false, term: false, live: false, c1: '', o1: false, c2: '', o2: 0, c3: '', bye: false }
const poster: S = { ...initial, term: true, live: true, c1: C1, o1: true, c2: C2, o2: CONTAINERS.length }

async function script(a: Act<S>) {
  await a.wait(900)
  a.mark('open')
  a.put({ pressed: true })
  await a.key('cmd+1')
  a.put({ pressed: false, term: true })
  // Connecting: the tab's logo is yellow and the cursor waits at the top
  await a.wait(750)
  a.mark('live')
  a.put({ live: true })
  await a.wait(700)
  // Each command goes with Enter on the deck's keyboard, shown under the phone like ⌘1
  await a.type('c1', C1, { interval: 55 })
  await a.key('enter')
  a.put({ o1: true })
  await a.wait(650)
  await a.type('c2', C2, { interval: 40 })
  await a.key('enter')
  a.mark('output')
  for (let i = 1; i <= CONTAINERS.length; i++) {
    a.put({ o2: i })
    await a.wait(45)
  }
  await a.wait(2600)
  a.mark('exit')
  await a.type('c3', C3, { interval: 70 })
  await a.key('enter')
  a.put({ bye: true })
  await a.wait(320)
  // The pane closed with its shell, so the cover goes down; the session is
  // cleared while it is off the screen
  a.put({ term: false })
  await a.wait(650)
  await a.snap({ live: false, c1: '', o1: false, c2: '', o2: 0, c3: '', bye: false })
  await a.wait(500)
}

const DEVICES: { name: string; os: string; login: string }[] = [
  { name: 'nuc', os: ubuntu, login: 'cobanov@192.168.1.10:22' },
  { name: 'nas', os: debian, login: 'cobanov@192.168.1.20:22' },
  { name: 'pi', os: pi, login: 'pi@192.168.1.31:22' },
  { name: 'spark', os: ubuntu, login: 'cobanov@192.168.1.40:22' },
  { name: 'white', os: fedora, login: 'cobanov@192.168.1.12:22' },
  { name: 'choso', os: arch, login: 'cobanov@192.168.1.14:22' },
  { name: 'vps', os: alpine, login: 'root@203.0.113.7:22' },
  { name: 'router', os: freebsd, login: 'admin@192.168.1.1:22' },
  { name: 'hope', os: nixos, login: 'cobanov@192.168.1.16:22' },
  { name: 'laptop', os: mint, login: 'cobanov@192.168.1.23:22' },
  { name: 'kali', os: kali, login: 'kali@192.168.1.50:22' },
  { name: 'desktop', os: windows, login: 'cobanov@192.168.1.60:22' },
]

const KEYS = ['esc', 'tab', 'enter', '^C', '^D', '^Z', '|', '~', '←', '↓', '↑', '→']

// The phone's body runs 13pt past the screen on each side (the pro frame's
// band and glass), so its landscape outline is 900 × 428pt
const BODY = { w: 900, h: 428 }

export function DeckTermHero() {
  return (
    <Stage<S>
      width={1000}
      height={588}
      compact={{ below: 560, width: 350, height: COMPACT.height }}
      fill
      theme="dark"
      initial={initial}
      poster={poster}
      script={script}
      className="dt"
    >
      {(s, _rect, layout) =>
        layout === 'compact' ? (
          <div className="dt-frame">
            <Deck s={s} width={BODY.w * COMPACT.scale} top={16} />
          </div>
        ) : (
          <Deck s={s} width={1000} top={56} />
        )
      }
    </Stage>
  )
}

// In a phone's column the whole phone would be too small to read, so it is
// drawn at a size whose terminal reads (18pt at 0.59 is about 10.5px), its left
// edge on the column's and running off the right edge of the screen (the page
// lets the figure out past its padding there): its island side, both commands
// and nuc's column of cards stay in. The scale puts the edge in the gap after
// the key bar's ^Z, so no key is sliced. The band below the phone is where the
// keystrokes show
// 595.5 = the bezel (13) + the screen out to that gap (582.5)
const COMPACT_SCALE = 350 / 595.5
const COMPACT = { scale: COMPACT_SCALE, height: Math.round(16 + BODY.h * COMPACT_SCALE + 56) }

// Wide, the phone whole across the column with an even band above and below:
// the one below is where the deck's keystrokes show, under the phone as its
// keyboard sits
function Deck({ s, width, top, left = 0 }: { s: S; width: number; top: number; left?: number }) {
  const scale = width / BODY.w
  const tall = BODY.h * scale
  return (
    <div className="dt-device" style={{ width, height: tall, top, left }}>
      <Phone
        width={tall}
        status={false}
        dark
        className="dt-phone"
        style={{ left: (width - tall) / 2, top: (tall - width) / 2 }}
      >
        <div className="dt-screen">
          <List pressed={s.pressed} />
          <Terminal s={s} />
        </div>
      </Phone>
    </div>
  )
}

function List({ pressed }: { pressed: boolean }) {
  return (
    <div className="dt-list">
      <header className="dt-head">
        <Mark />
        <span className="dt-brand">deckterm</span>
        <span className="dt-hbtn"><Settings size={16} strokeWidth={2} /></span>
        <span className="dt-hbtn"><Plus size={16} strokeWidth={2} /></span>
      </header>
      <div className="dt-grid">
        {DEVICES.map((d, i) => (
          <div key={d.name} className="dt-card" data-pressed={(i === 0 && pressed) || undefined}>
            <span className="dt-card__line">
              <Os src={d.os} size={15} />
              <span className="dt-card__name">{d.name}</span>
              {i < 9 && <span className="dt-card__key">⌘{i + 1}</span>}
            </span>
            <span className="dt-card__login">{d.login}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

// The terminal's grid, at 18pt (the app's 13 with ⌘= pressed five times, a size a
// deck held at arm's length wants): JetBrains Mono's cells are 0.6em wide
const CELL = { w: 10.8, h: 24 }
const PROMPT = 'cobanov@nuc:~$ '

function Terminal({ s }: { s: S }) {
  const lines: ReactNode[] = []
  // Where the cursor is, in cells: at the top while the session connects,
  // then after whatever was written last
  let cur = { row: 0, col: 0 }
  const prompt = (typed: string) => {
    lines.push(<Prompt typed={typed} />)
    cur = { row: lines.length - 1, col: PROMPT.length + typed.length }
  }
  if (s.live) {
    lines.push('Welcome to Ubuntu 24.04.3 LTS')
    prompt(s.c1)
    if (s.o1) {
      lines.push('up 6 weeks, 3 hours, 17 minutes')
      prompt(s.c2)
    }
    if (s.o2) {
      CONTAINERS.slice(0, s.o2).forEach((c) => lines.push(c))
      if (s.o2 === CONTAINERS.length) prompt(s.c3)
      else cur = { row: lines.length, col: 0 }
    }
    if (s.bye) {
      lines.push('logout')
      cur = { row: lines.length, col: 0 }
    }
  }
  return (
    <div className="dt-term" data-open={s.term || undefined}>
      <div className="dt-lines">
        {lines.map((l, i) => (
          <div key={i} className="dt-line">{l}</div>
        ))}
        {/* One cursor, stepping cell to cell as a terminal's does */}
        <span className="dt-cur" data-snap style={{ transform: `translate(${cur.col * CELL.w}px, ${cur.row * CELL.h}px)` }} />
      </div>
      <KeyBar live={s.live} />
    </div>
  )
}

function Prompt({ typed }: { typed: string }) {
  return (
    <>
      <b className="dt-g">cobanov@nuc</b>:<b className="dt-b">~</b>$ <span data-typing>{typed}</span>
    </>
  )
}

function KeyBar({ live }: { live: boolean }) {
  return (
    <div className="dt-bar">
      <span className="dt-tab">
        <Os src={ubuntu} size={11} className="dt-tab__logo" data-live={live || undefined} />
        nuc
      </span>
      <span className="dt-keys">
        {KEYS.map((k) => (
          <span key={k} className="dt-key">{k}</span>
        ))}
      </span>
      <span className="dt-icon"><Keyboard size={16} strokeWidth={1.75} /></span>
      <span className="dt-icon"><PanelRight size={16} strokeWidth={1.75} /></span>
    </div>
  )
}

// A system's logo from the app's own asset catalog, in the current color
function Os({ src, size, className, ...rest }: { src: string; size: number; className?: string; 'data-live'?: true }) {
  return (
    <span
      {...rest}
      className={`dt-os${className ? ` ${className}` : ''}`}
      style={{ width: size + 2, height: size, ['--src' as string]: `url("${src}")` }}
      aria-hidden
    />
  )
}

// The app's mark, as Mark draws it in the list's header: the icon's hinge on
// a raised tile, the base arm at 60%
function Mark() {
  return (
    <span className="dt-mark" aria-hidden>
      <svg viewBox="32 32 192 192">
        <path fill="currentColor" opacity="0.6" d="M157.41 119.68 L43.1 185.68 L63.1 220.32 L177.41 154.32 Z" />
        <path fill="currentColor" d="M177.41 101.68 L63.1 35.68 L43.1 70.32 L157.41 136.32 Z" />
        <path fill="currentColor" fillRule="evenodd" d="M153 128 A30 30 0 1 0 213 128 A30 30 0 1 0 153 128 Z M173 128 A10 10 0 1 0 193 128 A10 10 0 1 0 173 128 Z" />
      </svg>
    </span>
  )
}
