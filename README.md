<p align="center">
  <img src="docs/images/icon.png" width="128" alt="NotchHover icon">
</p>

<h1 align="center">NotchHover</h1>

<p align="center">
  Your MacBook's notch, put to work.<br>
  Music, files, clipboard, notes and Claude Code approvals — one hover away.
</p>

<p align="center">
  <a href="https://github.com/BelalElrashidy/NotchHover/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/BelalElrashidy/NotchHover?label=download&color=D9622F"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-111111">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-native-111111">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/BelalElrashidy/NotchHover?color=111111"></a>
</p>

<p align="center">
  <img src="docs/images/theme-graphite.png" width="720" alt="NotchHover open beneath the notch: tabs to the left of the notch, actions to the right, and the player, calendar and controls below">
</p>

---

NotchHover turns the dead space around the MacBook notch into a small control surface.
Hover the notch and a panel grows out of it — Home, Shelf and Notes to the left of the
notch, the clipboard, mirror and settings to its right — and move away and it sinks back. While something
plays, a slim bar hugs the notch with the artwork and a live meter — and when your volume
changes or a notification lands, the notch pops to show it.

Everything runs on your Mac. There are no accounts, no servers and no analytics.

## Features

**Now playing**
- Spotify and Apple Music with artwork, scrubbing, shuffle and volume
- Anything else that plays sound is shown too — a video in your browser appears as the
  site it's on, with that site's own icon
- Pinned playlists you can start from the notch
- **Next in playlist** for Apple Music — the next three tracks beside the player, click
  one to play it (Spotify keeps its queue online, so it can't be shown)
- **A live visualizer**, if you switch it on — the bars beside the notch move with the
  music itself, in the artwork's colour
- **Synced lyrics**, if you switch them on — the line being sung, in the peek and the
  Now Playing card. Off by default, because it is the one feature that goes online
  (see [Privacy](#privacy))
- **Music on the lock screen**, if you switch it on — what's playing, with play, pause
  and skip, hanging from the notch while the Mac is locked. Nothing else ever shows there

**Rest, peek, open**
- Rest on the notch for a moment and a **peek** comes up, laid out like the Dynamic
  Island: what's playing with its scrubber and controls, a countdown to a call with
  **Join**, or the time and what's next. Click it, or
  swipe down, for the full panel; move away and it's gone
- Prefer the panel straight away? Settings → Appearance → On hover

**Live activities**
- Volume, brightness, keyboard backlight, battery and timer changes pop out of the notch
- Notification banners are mirrored into it
- **AirPods and Bluetooth accessories** pop with their charge when they connect, and again
  when one runs low
- A call with a link pops two minutes before it starts
- **Meeting controls** — on a Zoom, Teams, Webex or Google Meet call, the peek shows
  mute, camera and leave, and how long the call has run; <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd>
  mutes from anywhere. Zoom and Meet also say whether you're muted
- The resting bar takes a breath when something starts playing

**Getting things done**
- **Shelf** — drag files to the notch and it opens on drop zones: keep them on the
  shelf, AirDrop them, or drop straight onto **Convert**, **Zip** or **Copy text**. On the
  shelf, select files and the actions that fit appear: convert, resize, compress, copy
  the text out of a picture or PDF, cut out the subject, make a PDF, remove the location,
  zip — all done on your Mac
- **Clipboard history** — every clip as a card, with coloured **boards** to keep the ones
  you reuse (drag a card onto a board); search, pin and paste back with
  <kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd>
- **Screenshots** — each one you take pops out of the notch to drag anywhere, copy, mark
  up, shelve or delete; a **Screenshots** view keeps the recent ones and takes new ones —
  an area, a window, the screen, or in five seconds (<kbd>⌃</kbd><kbd>⌥</kbd><kbd>4</kbd>
  for an area)
- **Quick notes** — <kbd>⌃</kbd><kbd>⌥</kbd><kbd>N</kbd> to start one, <kbd>⌘</kbd><kbd>↩</kbd> to keep it
- **Controls** — output volume, microphone gain and mute, display brightness, keyboard backlight
- **Schedule** — a week strip over a timeline of the day, with a red line at now, all-day
  events as capsules, and a **Join** button on every Zoom, Meet, Teams, FaceTime or Webex
  call; Zoom and Teams open straight in their apps
- Countdown timer, macOS Shortcuts, app launchers, and a **Batteries** card for the Mac
  and everything connected

**Claude Code**
- Approve or deny Claude Code's tool calls from the notch, without switching windows —
  free, open source, and without an account.
- A **Claude Code** card shows each active session — project, branch, and whether it's
  running a tool, thinking or waiting for you — with today's token use. When a session
  finishes and hands the turn back, the notch tells you.
- Read from the transcripts Claude Code keeps on your Mac; only metadata, never your
  prompts or code.

**Yours to shape**
- **Quick settings in the notch** — the gear turns the panel into its settings: theme,
  hover, visualizer, lyrics, clipboard, gestures. Everything else is in the Settings
  window, a searchable sidebar with a live picture of your notch
- Six themes, from solid graphite to Liquid Glass
- Rearrange the widgets, resize the panel and the resting bar, adjust corner radius and flare

<table>
  <tr>
    <td><img src="docs/images/expanded-shelf.png" alt="The Shelf: files parked on the notch beside recent clipboard items"></td>
    <td><img src="docs/images/expanded-notes.png" alt="Quick notes, with saved notes listed beside the editor"></td>
  </tr>
  <tr>
    <td><img src="docs/images/expanded-clipboard.png" alt="Searchable clipboard history"></td>
    <td><img src="docs/images/idle-notification.png" alt="A notification popping out of the notch"></td>
  </tr>
</table>

## Keyboard and trackpad

NotchHover never needs the pointer. Press <kbd>⌘</kbd><kbd>K</kbd> in the panel for every
action and its keys — type to find one, <kbd>↩</kbd> to run it. Every global hotkey can be
changed or switched off in Settings → Shortcuts, where you can also make your own: a
link that takes a search word, an app, a script, a macOS Shortcut, or several in a row.

| Where | Keys |
|---|---|
| Anywhere | <kbd>⌃</kbd><kbd>⌥</kbd><kbd>H</kbd> Home · <kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd> Shelf · <kbd>⌃</kbd><kbd>⌥</kbd><kbd>N</kbd> Notes · <kbd>⌃</kbd><kbd>⌥</kbd><kbd>V</kbd> Clipboard — the same keys close it again · <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd> mute the call you're on · <kbd>⌃</kbd><kbd>⌥</kbd><kbd>4</kbd> screenshot an area |
| In the panel | <kbd>⌘</kbd><kbd>K</kbd> every action · <kbd>⌘</kbd><kbd>1</kbd>–<kbd>6</kbd> switch views · <kbd>⌃</kbd><kbd>⇥</kbd> next tab · <kbd>⌘</kbd><kbd>J</kbd> join the next call · <kbd>⎋</kbd> or <kbd>⌘</kbd><kbd>W</kbd> close · <kbd>⌘</kbd><kbd>,</kbd> Settings |
| Playing | <kbd>Space</kbd> play or pause · <kbd>⌘</kbd><kbd>←</kbd> <kbd>⌘</kbd><kbd>→</kbd> previous, next · <kbd>⌘</kbd><kbd>↑</kbd> <kbd>⌘</kbd><kbd>↓</kbd> volume · <kbd>⌘</kbd><kbd>⇧</kbd><kbd>M</kbd> mute the microphone |
| Clipboard | <kbd>↑</kbd> <kbd>↓</kbd> choose · <kbd>↩</kbd> copy · <kbd>⌘</kbd><kbd>↩</kbd> paste into the front app · <kbd>⌘</kbd><kbd>P</kbd> pin · <kbd>⌘</kbd><kbd>⌫</kbd> delete |
| Notes, Shelf | <kbd>⌘</kbd><kbd>↩</kbd> save · <kbd>⌘</kbd><kbd>N</kbd> new · <kbd>⌘</kbd><kbd>[</kbd> <kbd>⌘</kbd><kbd>]</kbd> other notes · <kbd>⌘</kbd><kbd>S</kbd> send the shelf · <kbd>⌘</kbd><kbd>R</kbd> show in Finder |
| Claude Code | <kbd>⌘</kbd><kbd>↩</kbd> allow · <kbd>⌘</kbd><kbd>⌫</kbd> deny |

On a trackpad, swipe two fingers **down** on the notch to open it and **up** to close it,
and **sideways** to move between tabs — or, on the resting bar, between tracks. A Force
Touch trackpad taps back when something happens. Both can be switched off in Settings.

## Install

1. Download **NotchHover-x.y.z.zip** from the [latest release](https://github.com/BelalElrashidy/NotchHover/releases/latest).
2. Unzip it and drag **NotchHover.app** into **Applications**.
3. Open it.

**The first launch will be blocked.** NotchHover isn't notarized by Apple yet, so macOS
refuses to open it the first time. To allow it, either:

- open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
  next to NotchHover; or
- run this once in Terminal:

  ```bash
  xattr -dr com.apple.quarantine /Applications/NotchHover.app
  ```

NotchHover has no Dock icon and no menu bar icon — it lives entirely in the notch. Hover
it to begin.

**Requirements:** macOS 14 Sonoma or later, on Apple silicon. Macs without a notch get a
slim strip at the top centre of the screen instead.

## Permissions

Every permission is optional. Each one only switches on the feature beside it, and macOS
asks the first time that feature is used.

| Permission | What it's for |
|---|---|
| Automation → Spotify, Music | Reading what's playing and controlling playback |
| Automation → Safari | Naming the page Safari is playing |
| Accessibility | Mirroring notification banners into the notch; pressing a call app's mute, camera and leave |
| Calendars | Your next events, and the Join button for calls |
| Bluetooth | Your accessories' battery levels |
| Camera | The mirror |

Seeing which app is playing needs no permission, and neither does naming the page in
Firefox, Zen and other Firefox-based browsers — they keep their open tabs, favicons
included, in a file NotchHover can read. Safari's favicons are locked away, so a Safari
page shows Safari's icon.

## Claude Code approvals

NotchHover can answer Claude Code's permission prompts for you. A small hook forwards
each request to the app over a loopback socket, protected by a token only your user can
read; the request appears in the notch, and your answer goes straight back to Claude Code.
If you don't answer within 50 seconds, Claude Code falls back to its own prompt — the
notch never approves anything on its own.

The hook lives in this repository, so clone it and run:

```bash
Scripts/install-claude-hook.sh
```

`Scripts/install-claude-hook.sh --uninstall` removes it, and your previous settings are
kept in `~/.claude/settings.json.notchhover-backup`.

## Privacy

NotchHover makes no network requests of its own, with two exceptions:

- Spotify only hands out artwork as a link, so album art for Spotify tracks is fetched
  from Spotify's image server. No account information is sent with that request.
- **Synced lyrics, only if you turn them on** (Settings → Privacy and permissions, off by default). For
  each Spotify or Music song, its title, artist, album and length are sent once to
  [lrclib.net](https://lrclib.net), a free, open lyrics database — no account, cookie or
  identifier goes with them. The answer, lyrics or "none", is kept in Application
  Support, so a song is never asked about twice.

Music on the lock screen is off by default too. When it's on, anyone at your locked Mac
can see the song playing and skip it; nothing else is shown there.

Clipboard history, notes and the shelf are stored in your user's Application Support
folder, readable only by you. Password managers mark what they copy as concealed, and
those entries are never recorded.

## Build from source

You'll need macOS 14 or later and **Xcode 26** (the app icon is an Icon Composer file,
which older versions can't compile).

```bash
git clone https://github.com/BelalElrashidy/NotchHover.git
cd NotchHover
Scripts/build-app.sh release --install --run
```

| Script | What it does |
|---|---|
| `Scripts/build-app.sh [debug\|release] [--install] [--run]` | Builds `build/NotchHover.app`; optionally copies it to Applications and opens it |
| `Scripts/dev.sh` | Rebuild, install, relaunch, and follow the app's log |
| `Scripts/check.sh` | Compile, render every panel state to PNGs, and run the settings self-test |
| `Scripts/release.sh` | Build `dist/NotchHover-<version>.zip` for a GitHub release |

`NotchHover --render-preview <folder>` renders each panel state to a PNG, and
`NotchHover --animation-selftest` measures the open and close animations frame by frame —
both are how layout changes get checked without a screen recording.

How it's put together is written up in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Roadmap

- **A command bar** — type to jump, search and run actions, Raycast-style
- Signed and notarized builds, so the first launch just works

The longer list, with what's built and what isn't, is in [docs/FEATURES.md](docs/FEATURES.md),
and how NotchHover compares with the other notch apps is in [docs/COMPETITORS.md](docs/COMPETITORS.md).
What changed in each release is in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Issues and pull requests are welcome. For anything larger than a fix, please open an issue
first so we can agree on the shape of it. Before sending a change that touches the panel,
run `Scripts/check.sh` and look at the rendered previews.

## Acknowledgements

NotchHover stands on ideas from [NotchNook](https://lo.cafe/notchnook),
[Boring Notch](https://github.com/TheBoredTeam/boring.notch),
[Alcove](https://tryalcove.com) and [Atoll](https://github.com/Ebullioscopic/Atoll).

## License

NotchHover is free software, released under the [GNU General Public License v3.0](LICENSE).
