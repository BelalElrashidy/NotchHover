# Changelog

Every release of NotchHover, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org): a new feature is a minor release (0.4.0), a fix
on its own is a patch (0.4.1).

Each release's notes on GitHub are built from its section here by `Scripts/release.sh`,
so this file is the one place to write them.

## [Unreleased]

## [0.8.0] — 2026-10-19

Clipboard boards.

### Added
- **Boards for the clipboard**, like Paste's pinboards: coloured, named collections of
  clips you keep reusing. Make one with **+**, drag a card onto it to keep the card there,
  or right-click a card and tick the boards it belongs on. Right-click a board to rename
  it, change its colour or delete it — deleting a board never deletes its clips.
- Anything on a board, like anything pinned, survives **Clear** and the 250-clip limit.

### Changed
- **The Clipboard tab is a strip of cards**: each clip shows what it is — text, link,
  file, picture or colour — with the app it came from, the boards it's on, and the clip
  itself: wrapped text, code in a monospaced font, a link's address, a picture, a colour
  swatch for a hex value. Click to copy, double-click to paste, drag it out into any app.
- ← and → move through the cards, as ↑ and ↓ do.

### Fixed
- The peek's Join button logged a layout conflict between its frame and its size.

## [0.7.0] — 2026-10-19

Drop to do: a new shelf, and things to do with files.

### Added
- **Drop zones.** Drag files to the notch and it opens straight away — no hover delay —
  on zones for what to do with them: **Shelf**, **AirDrop**, a conversion (**To JPEG**,
  **To PNG** or **To MP4**), **Zip**, and **Copy text** for pictures and PDFs. Let go on
  one and it's done.
- **File actions**, all on your Mac with what macOS already has:
  - convert pictures to JPEG or PNG, and videos to MP4
  - resize a picture to half, or compress it
  - copy the text out of a picture or a PDF
  - cut the subject out of a photo, onto a transparent background
  - make one PDF from pictures and PDFs
  - remove a picture's location and camera details
  - zip anything, keeping Finder's metadata
- New files go beside the originals, never over an existing file, and land on the shelf.
  The resting bar says when it's done.

### Changed
- **The shelf** shows each file as a thumbnail with its name. Click to select, drag one
  out, double-click to open. The actions that fit what's selected — or the whole shelf —
  sit underneath as chips, with AirDrop, Show in Finder and Remove.

## [0.6.0] — 2026-10-19

Meeting controls.

### Added
- **Mute, camera and leave from the notch.** On a call, the peek shows the app, the
  meeting, how long it has run, and three round buttons — mute, camera, and leave in red.
  A call outranks everything else in the peek.
- **Zoom**: pressed through its Meeting menu, which also tells NotchHover whether you're
  muted and whether your camera is on. Leaving still asks Zoom's own "Leave meeting?".
- **Microsoft Teams**: its call buttons, or its own shortcuts when they can't be found.
- **Webex**: its own shortcuts.
- **Google Meet in Chrome, Edge, Arc, Brave, Vivaldi or Safari**: a line of JavaScript in
  the Meet tab presses the buttons and reads whether you're muted. Browsers ship this off;
  turn on **Allow JavaScript from Apple Events** (Chrome: View → Developer; Safari:
  Settings → Advanced, then Develop) — the peek tells you when it's needed.
- **FaceTime, Slack huddles** and anything else: the Mac's microphone mute.
- **⌃⌥M** mutes the call you're on from anywhere, or the Mac's microphone when there is no
  call. ⌘⇧M in the panel does the same.

### Notes
- Everything happens on the Mac; no meeting service is contacted. Pressing a call app's
  buttons uses the Accessibility permission NotchHover already asks for.

## [0.5.0] — 2026-10-19

A new schedule.

### Changed
- **The calendar card is now a schedule**: a week strip on top, today in red and a dot
  under every day with something on, over a timeline of the chosen day. Events are blocks
  in their calendar's colour, side by side when they overlap, faded once they're over; a
  red line marks now, and the timeline opens just before it. Click another day in the
  strip to see it.
- **All-day events** sit as small capsules between the strip and the timeline.
- **Join** buttons sit on the call's own block, in the service's colour — Zoom blue,
  Meet green, Teams violet.
- Without calendar access the card explains what it's for and offers **Allow calendar
  access**, instead of asking the moment it appears.
- The schedule keeps itself current: it updates when your calendar changes and every
  minute while it's on screen.

## [0.4.0] — 2026-10-19

A new peek.

### Changed
- **The peek is redesigned after the Dynamic Island's expanded view**, the layout Crest
  and Droppy borrow. Playing: the artwork beside the title and artist, the level meter in
  the artwork's own colour, a scrubber with elapsed and remaining time that runs smoothly
  between updates, and previous, play and next underneath. A browser video shows the page
  and its icon without the controls it doesn't have.
- **A call about to start** shows the service's coloured tile, a live countdown to the
  start, and a green **Join**.
- **With nothing on**, the peek shows the time, the date and your next event, with its
  calendar's colour.
- The peek is as tall as what it shows, and resizes smoothly when that changes.
- The lock screen music card uses the new layout too.

## [0.3.0] — 2026-10-16

A peek before the panel, and the notch knows a bit more about your day.

### Added
- **Peek.** Resting the pointer on the notch brings up a small card first: what's playing
  with its controls, a call about to start with Join, or the date and what's next. Click
  it or swipe down for the full panel. Settings → Appearance → On hover switches back to
  opening the panel straight away.
- **One-click meeting join.** Zoom, Google Meet, Teams, FaceTime and Webex links are found
  in calendar events; Join in the peek, the calendar card or ⌘J opens the call, Zoom and
  Teams in their apps. The notch pops two minutes before a call with a link.
- **AirPods and accessory batteries.** Both buds and the case, headphones, speakers, Magic
  Keyboard, Mouse and Trackpad. They pop on connect and again at 20% and 10%. A
  **Batteries** card can be added in Settings → Layout.
- **Claude Code sessions.** A **Claude Code** card shows each active session's project,
  branch and state, with today's token use, and the notch pops when a session hands the
  turn back. Read from Claude Code's local transcripts, metadata only.
- **Synced lyrics, opt-in.** The line being sung, in the peek and the Now Playing card.
  The one feature that goes online: each song's title, artist, album and length are sent
  once to lrclib.net and the answer is cached on the Mac. Off by default.
- **Music on the lock screen, opt-in.** Artwork, title, play, pause and skip while the
  Mac is locked, and nothing else. Off by default.

## [0.2.0] — 2026-10-16

NotchHover without the mouse.

### Added
- **Everything from the keyboard.** ⌃⌥H, ⌃⌥S, ⌃⌥N and ⌃⌥V open Home, Shelf, Notes and
  Clipboard from anywhere, and close it again. In the panel, ⌘1–⌘5 switch views, Space
  plays and pauses, ⌘←/⌘→ skip, ⌘↑/⌘↓ change the volume, ⌘⇧M mutes the microphone, the
  clipboard list follows the arrow keys, and ⌘↩/⌘⌫ answer Claude Code. ⌘/ lists them all.
- **Trackpad gestures.** Two fingers down on the notch to open it, up to close, sideways
  to change tab — or, on the resting bar, the track.
- **Haptics** when the panel opens, a tab changes, a swipe lands or an approval is
  answered. Gestures and haptics can both be switched off.

### Fixed
- The clipboard, mirror and settings buttons to the right of the notch couldn't be clicked.
- The resting bar lit up with nothing playing: macOS's dictation service, and Safari after
  its window closed, hold the audio output open in silence. Only an app making sound
  counts now.
- A panel opened from the keyboard no longer closes at the first nudge of the mouse, and
  Esc no longer closes it over an unanswered Claude Code approval.

## [0.1.0] — 2026-10-16

The first public release.

### Added
- Home, Shelf and Notes beside the notch; clipboard, mirror and settings to its right.
- Now playing for Spotify and Apple Music with artwork and controls, plus anything else
  that makes sound — a browser video shows the page and the site's icon.
- Live activities: volume, brightness, keyboard backlight, battery, timer and mirrored
  notification banners.
- Shelf for files, clipboard history (⌃⌥V), quick notes (⌃⌥N), controls with microphone
  gain and mute, Claude Code approvals.
- A notch on every display, shown over full-screen apps.

[Unreleased]: https://github.com/BelalElrashidy/NotchHover/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/BelalElrashidy/NotchHover/releases/tag/v0.1.0
