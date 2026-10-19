# What the other notch apps do

A survey of the field in October 2026, to decide what NotchHover builds next. It is
compiled from each app's own site, its source code where it is open, and the comparison
round-ups listed at the end. Most of those round-ups are written by people who sell one
of the apps, so treat any single claim with some care.

**How to read the matrix:** ✅ means the app's own page or source lists the feature.
A blank means the sources didn't mention it, not that the app definitely lacks it.

---

## The field

| App | Price | Open source | What it leans on |
|---|---|---|---|
| **NotchHover** | Free | ✅ GPL-3.0 | Claude Code approvals, local-only, page-aware now playing |
| [Boring Notch](https://github.com/TheBoredTeam/boring.notch) | Free | ✅ GPL-3.0 | The open-source reference: media, shelf, HUDs |
| [Atoll](https://github.com/Ebullioscopic/Atoll) | Free | ✅ | Boring Notch fork with system stats, terminal, lock screen |
| [NotchNook](https://lo.cafe/notchnook) | $25 once, or $3/mo | | The original: shelf, widgets, Shortcuts, heavy customisation |
| [Alcove](https://tryalcove.com) | $14.99 once | | Polish: Dynamic Island animations, gestures, lock screen |
| [Dynamic Notch](https://www.dynamicnotch.tech) | $5.99 once | | Breadth for little money: colour picker, weather, current task |
| [Crest](https://crestnotch.app) | Free tier; $24.99 or $2.99/mo | | Three clear states, swipeable pages, answers coding agents |
| [NotchBay](https://notchbay.com) | $9 once | | "App skins" that adapt to the front app, dictation, meetings |
| [Droppy](https://getdroppy.app) | $9.99 once | | 39 extensions, lyrics, Up Next, iPhone sync, Spotlight-style search |
| [OneNotch](https://www.tryonenotch.com) | Free tier; $9.99 lifetime | | Clipboard power tools, screenshots, coding-agent usage |
| [MacNotch](https://macnotch.io) | $22.99 once, or $3.99/mo | | ~19 optional modules, dashboard profiles |
| DynamicLake Pro | $13.99 once | | Shelf, file conversion, Up Next, Liquid Glass |

## Feature matrix

| | NotchHover | Boring | Atoll | NotchNook | Alcove | Dyn. Notch | Crest | NotchBay | Droppy | OneNotch |
|---|---|---|---|---|---|---|---|---|---|---|
| **How it opens** | | | | | | | | | | |
| Rest → hover peek → click full | ✅ | | ✅ | ✅ | | | ✅ | ✅ | | |
| Hover delay before opening | ✅ | ✅ 0.3s | | | | | | | | |
| Trackpad gestures | ✅ | ✅ | ✅ | ✅ | ✅ | | ✅ | | | |
| Haptics | ✅ | ✅ | ✅ | ✅ | | | | | | |
| Keyboard shortcut to open | ✅ | | ✅ | | | ✅ | | | | |
| Every display, notchless Macs | ✅ | ✅ | | | | | ✅ | ✅ | ✅ | ✅ |
| **Media** | | | | | | | | | | |
| Now playing with controls | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Any app playing, not just Spotify/Music | ✅ | | ✅ | | | ✅ | ✅ | | | |
| Names the browser page playing | ✅ | | | | | | | ✅ | | |
| Visualiser | 🟡 | ✅ | | | ✅ | | ✅ | | | ✅ |
| Synced lyrics | ✅ opt-in | ✅ | | | | | ✅ | | ✅ | ✅ |
| Up Next queue | | | | | | | | | ✅ | |
| **Files and text** | | | | | | | | | | |
| File shelf + AirDrop | ✅ | ✅ | ✅ | ✅ | | ✅ | ✅ | ✅ | ✅ | |
| File actions (convert, compress, OCR) | | | | | | | | | ✅ | ✅ |
| Clipboard history | ✅ | | ✅ | | | ✅ | ✅ | ✅ | ✅ | ✅ |
| Clipboard OCR / pinned boards | | | | | | | | ✅ | | ✅ |
| Quick notes | ✅ | | | ✅ | | ✅ | ✅ | | | |
| Screenshots | | | | | | | | | ✅ | ✅ |
| **Time and work** | | | | | | | | | | |
| Calendar | ✅ | ✅ | ✅ | ✅ | | ✅ | ✅ | ✅ | ✅ | ✅ |
| One-click meeting join | ✅ | | | | | ✅ | ✅ | ✅ | ✅ | |
| Meeting controls (mute, camera, leave) | ✅ | | | | | | | ✅ | ✅ | |
| Timer / Pomodoro | ✅ | ✅ | ✅ | | | ✅ | ✅ | ✅ | ✅ | ✅ |
| **System** | | | | | | | | | | |
| Volume and brightness HUD | ✅ | ✅ | | | ✅ | ✅ | | ✅ | ✅ | |
| Microphone gain and mute | ✅ | | | | | | | | | |
| Battery, AirPods and devices | ✅ | | ✅ | | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Notifications mirrored | ✅ | | | | ✅ | | | ✅ | ✅ | |
| Reply to messages from the notch | | | | | | | | ✅ | ✅ | |
| Lock screen widgets | 🟡 music, opt-in | | ✅ | | ✅ | | | ✅ | ✅ | ✅ |
| CPU, memory, network stats | | | ✅ | | | | ✅ | ✅ | ✅ | |
| Colour picker | | | ✅ | | | ✅ | | | | |
| Weather | | | ✅ | | | ✅ | ✅ | | | |
| Camera mirror | ✅ | ✅ | ✅ | | | ✅ | | | | |
| **Coding agents** | | | | | | | | | | |
| Answer approvals from the notch | ✅ | | | | | | ✅ | | | |
| Session state, tokens, plan limits | 🟡 | | ✅ | | | | ✅ | ✅ | ✅ | ✅ |
| **Beyond the notch** | | | | | | | | | | |
| Spotlight-style search / commands | | | | | | | | | ✅ | |
| Adapts to the front app | | | | | | | | ✅ | | |
| Pages or profiles of widgets | | | | | | | ✅ | | | |
| Extensions | | | | | | | | | ✅ | |
| No account, no telemetry | ✅ | | | | | | | | | |

---

## What this says

### The three states are the norm — done in October 2026

*Since this survey: NotchHover now rests, peeks after a 0.3s dwell, and opens on a click,
and has gestures, haptics, meeting join, accessory batteries and Claude Code sessions and
tokens. 🟡 on agents means no plan limits: only Anthropic's servers know them.*

Every app that gets this right separates *glancing* from *using*:

- **Crest** — a pill showing the most important live activity; hover for a peek with the
  song and its controls; click for a row of widget pages you swipe between.
- **NotchBay** — "glance to check it, hover to peek, click to expand."
- **NotchNook** — hover and the notch grows a little; click, or swipe down with two fingers,
  and it opens fully.
- **Atoll** — hover to expand, click to open the controls.

NotchHover goes from the resting bar straight to the full panel the moment the pointer
touches the notch, with no dwell. Passing it on the way to the menu bar opens it. Boring
Notch waits 0.3s of hover first, and that alone would stop most accidental opens.

### Claude Code is no longer a moat

When NotchHover's approvals were built, nothing else answered a coding agent from the
notch. Now Crest does it for free, and NotchBay, Droppy, OneNotch, Atoll and MacNotch all
track agents, most with token use and plan limits — OneNotch lists approval requests among
what it shows, though not whether you can answer them there. Approvals are still worth having; they
are no longer a reason to switch.

What is still rare:

- **Free, open source, and no account or telemetry at all.** Most of the field is paid;
  NotchBay has an anonymous install check-in, and Crest Pro needs a sign-in. (Boring Notch
  and Atoll are free and open source too; their pages don't say either way about
  telemetry.)
- **Now playing that names the page.** Most apps show the browser, or a waveform. Only
  NotchBay's browser skin also knows the tab.
- **Microphone gain and mute in the notch.** Nobody else lists it.

### Table stakes we don't have yet

In rough order of how many competitors have them, now done:

1. ~~Hover peek, and a dwell before opening~~ ✅
2. ~~One-click meeting join from the calendar~~ ✅
3. ~~Battery for AirPods and other devices~~ ✅
4. ~~Synced lyrics~~ ✅ opt-in, the one feature that goes online
5. ~~Trackpad gestures and haptics~~ ✅
6. ~~Coding-agent session state and usage~~ ✅ tokens; plan limits aren't in the transcripts
7. Lock screen widgets — 🟡 music only, opt-in; nothing more personal belongs on a locked screen

---

## Recommended next milestones

### 1. Three states (next release)

| State | Shows | Enters | Leaves |
|---|---|---|---|
| **Rest** | Today's resting bar: artwork and meter, only while something is happening | Something plays, or an activity arrives | Nothing left to show |
| **Peek** | The bar widened to about twice the notch: artwork, title, play/pause and next — or, when Claude Code is waiting, the request with **Allow** and **Deny** inline | 0.3s of hover over the notch | The pointer leaves, at once |
| **Full** | Today's panel: Home, Shelf, Notes | A click on the peek, a two-finger swipe down, or a shortcut | The pointer leaves, after the usual grace period |

The peek is the same slab morphing, so it fits the existing animation model: one more
rect between the resting bar and the panel.

### 2. Quick wins

- Meeting **Join** on the calendar card (read the event's URL; Zoom, Meet, Teams, FaceTime)
- AirPods and Bluetooth battery as live activities
- Chrome, Arc, Brave and Edge page detection, through the same AppleScript path as Safari
- Haptic tick when the panel opens

### 3. The command bar (the Raycast replacement)

Only Droppy has anything close. Opened by a shortcut, it would search across the things
NotchHover already holds — clips, notes, shelf files, apps, Shortcuts, playlists — and
run actions: "timer 25", "note …", "mute mic", "play Focus". The full panel is the
natural place for it, which is one more reason to do the three states first.

---

## Sources

- [Boring Notch source](https://github.com/TheBoredTeam/boring.notch) — settings and defaults, including the 0.3s hover dwell
- [Atoll README](https://github.com/Ebullioscopic/Atoll)
- [Crest](https://crestnotch.app/dynamic-island-mac)
- [NotchBay](https://notchbay.com)
- [Droppy](https://getdroppy.app)
- [Dynamic Notch](https://www.dynamicnotch.tech) and its [comparison](https://www.dynamicnotch.tech/best-mac-notch-apps) — written by Dynamic Notch's developer
- [Alcove](https://tryalcove.com)
- [OneNotch's comparison](https://www.tryonenotch.com/blog/best-mac-notch-apps-2026) — written by OneNotch
- [Brow's comparison](https://brow-app.com/blog/best-macbook-notch-apps-2026) — written by Brow
- [MacNotch's comparison](https://macnotch.io/compare/best-mac-notch-apps) — written by MacNotch
