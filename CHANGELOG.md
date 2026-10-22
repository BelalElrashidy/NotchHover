# Changelog

Every release of NotchHover, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org): a new feature is a minor release (0.4.0), a fix
on its own is a patch (0.4.1).

Each release's notes on GitHub are built from its section here by `Scripts/release.sh`,
so this file is the one place to write them.

## [Unreleased]

## [0.14.18] — 2026-10-23

Swipe between views.

### Fixed
- **Swiping between views now follows your fingers.** Two fingers sideways pull the
  view along with them; let go short and it springs back. When the swipe lands, the view
  slides across to the next one, with a tap from the trackpad.

### Added
- `--swipe-demo`, with `--open-tab`, plays a swipe in the panel, to see the transition
  without a trackpad. The gesture self-test checks the drag and the spring-back.

## [0.14.17] — 2026-10-23

A second board, and Screenshots on the right.

### Fixed
- **A second board beside Home.** A new tab after Home with widgets of its own —
  Playlists, Apps and Timer to begin with. Settings → Layout has a Home / Board switch to
  lay either out, and a name for the second one. ⌘7 opens it.
- **Screenshots moves to the right**, beside Clipboard and Mirror.
- **The Timer's buttons piled on top of each other** in a narrow column. The presets
  now share the width equally, and Cancel only shows while a timer runs.

## [0.14.16] — 2026-10-23

A camera that fills the panel.

### Fixed
- **The camera was a small tile on the left with nothing beside it.** The preview now
  fills the panel, mirrored like a mirror. Start camera sits in the middle while it's off,
  and a small Stop in the corner while it's on. The camera still only starts when you
  press Start.

## [0.14.15] — 2026-10-23

Back where you left it.

### Fixed
- **The panel always reopened on Home.** It now opens on the view you left it on —
  Notes, Clipboard, the camera, anything — including after NotchHover restarts. Coming
  back to Notes on a hover doesn't put the cursor in it; a click does.

## [0.14.14] — 2026-10-23

Permissions that stay given.

### Fixed
- **Calendars, Camera and Automation were asked for again after every update.** macOS
  remembered them against the exact build, so each new version looked like a new app.
  NotchHover is now signed so that macOS recognises it by name: allow them once more
  after this update, and later updates keep them.

## [0.14.13] — 2026-10-23

Glass all the way up.

### Fixed
- **The top of a Clear glass panel was solid black.** The strip over the menu bar was
  painted black to stop menu titles showing through. Now that the glass stays blurred
  while you type, it isn't needed: the whole panel, header included, is one glass, and
  the menu bar behind it is a soft wash.

## [0.14.12] — 2026-10-23

The notch on every desktop.

### Fixed
- **Over a full-screen app's desktop the notch could be missing.** A window set to
  appear on every desktop still isn't always brought into a full-screen app's own one —
  over full-screen Safari the resting bar and the panel simply weren't there. Each time
  the desktop changes, the notch is now brought to the front again, the way Boring Notch
  and Atoll do it.

## [0.14.11] — 2026-10-23

Published by mistake, with no changes — only the version number moved. Its notes
described the desktops fix, which is in 0.14.12.

## [0.14.10] — 2026-10-21

Clear glass stays the same while you type.

### Fixed
- **Typing turned Clear glass see-through.** Liquid Glass draws one way in a window
  with keyboard focus — almost perfectly clear — and another, blurred and dimmed,
  without. Any text box (a note, the clipboard search, ⌘K) gives the panel focus, so
  the glass went nearly invisible as soon as you typed, and stayed that way through
  every tab until the panel closed. The glass now lives in a window of its own under the
  panel, one that never takes focus, so it always draws the same. It follows the panel's
  shape exactly — opening, closing, the pop and the breath.

### Added
- `--close-after <seconds>`, with `--open-tab`, closes the panel again — to check the
  resting bar after a pane without touching the Mac.

## [0.14.9] — 2026-10-21

The tab bar stays clean on see-through themes.

### Fixed
- **Typing scrambled the notch's tab bar.** Typing — a note, a clipboard search —
  makes an app active, and the menu bar fills with its menus. On Clear glass, or any
  theme below 100% opacity, those menu titles showed straight through the strip behind
  the tabs, and stayed until the panel was closed. That strip, the part over the menu
  bar, is now painted solid — black on glass, like the notch itself — so nothing behind
  it shows through.

## [0.14.8] — 2026-10-21

Notes you can read on glass.

### Fixed
- **Notes nearly vanished in Clear glass.** Clear glass had no darkening at all, so
  white text over anything bright behind the notch — a video, a white page — washed
  out, and the note's light text box made it worse. Clear glass now starts with a 40%
  tint (Settings → Appearance → Adjust Clear glass changes it, down to none), and on
  glass the places you type — the note, the clipboard search, the ⌘K list — sit on a
  dark field instead of a light one.

### Added
- `--open-tab <view>` opens the panel on a view at launch, to check how it looks
  without hovering.

## [0.14.7] — 2026-10-20

Screenshots where you want them.

### Fixed
- **Choose where screenshots are saved.** Settings → Shelf and screenshots → Save
  screenshots to: the same folder as macOS, Pictures › Screenshots, Documents ›
  Screenshots, or any folder you pick. It's created if it isn't there.
- **Optionally for macOS's keys too.** "Use it for ⇧⌘3, ⇧⌘4 and ⇧⌘5 too" sets the
  Screenshot app's own Save to; turning it off puts back what was there before.
- The Screenshots view watches both your folder and macOS's, so a screenshot shows up
  whichever way it was taken.
- A menu button with a long title — a folder's path, say — no longer squeezes its row's
  label into a narrow column: it stops at 300pt and cuts the title in the middle.

## [0.14.6] — 2026-10-20

Playlists from Apple Music too, and from the Share menu.

### Fixed
- **Playlists aren't Spotify-only any more.** The Playlists card plays Spotify links
  and playlists from your Music library — Settings → Music → Playlists → Add from Music…
  lists them. Apple Music links can be pinned too, and open in Music: Music can't be told
  to play a catalogue link, only shown it.
- **Share a link to NotchHover.** NotchHover is in the Share menu. Share a Spotify or
  Apple Music playlist, album or song — from a browser, Music, Messages, anywhere — and
  it's pinned with its name, and the notch opens on Playlists to show it. The extension
  only sees what you share with it, runs sandboxed, and hands the link to NotchHover on
  your Mac. If it isn't in the menu, turn it on under the Share menu's Edit Extensions… or
  System Settings → General → Login Items & Extensions → Sharing.
- Each pinned item in Settings says where it plays, and the link fields line up.

## [0.14.5] — 2026-10-20

Browsers, checked one by one.

### Fixed
- **Arc was never read.** Arc can have no tab in front, and the scan started by asking
  for that tab, so it failed every time. Arc's tabs are now listed first and asked one
  by one.
- **A sleeping tab could freeze playback detection.** Arc doesn't refuse a script sent
  to a tab it has put to sleep — it waits. The scan now asks media sites first, then each
  window's front tab, gives each one a second, skips tabs that didn't answer for five
  minutes, stops at the first one playing, and never takes more than about four seconds.
  Arc's background tabs are left alone.
- **Microsoft Edge showed up in Settings without being installed** — Microsoft's
  updater keeps its own copy in Application Support. Copies there no longer count.
- **Zen, LibreWolf, Waterfox and Floorp** are listed in Settings → Music → Browsers
  beside Firefox, as title only: none of them can be scripted, so the playing tab is
  read from the file they keep on disk.
- `--media-selftest` scans each running browser and reports how long it took and what it
  found, and checks Firefox-family session files.

## [0.14.4] — 2026-10-20

Adjust each theme.

### Fixed
- **Clear glass can be toned down.** Settings → Appearance → Adjust Clear glass has a
  Tint slider (0–85%) that darkens the glass until the panel reads over a bright or
  busy desktop, and Blur: Clear keeps what's behind sharp, Frosted softens it.
- **Every other theme has an Opacity slider** (30–100%), kept separately for each
  theme, so the desktop can show through Midnight, Graphite, Frost, Artwork tint or
  High contrast as much as you like. Artwork tint keeps it while it recolours.
- **Accent colour** can be the theme's own or any of macOS's — blue, purple, pink, red,
  orange, yellow, green or graphite — for buttons, the selected tab and progress bars.
- Opacity, tint and blur change the panel as you drag; the accent rebuilds it.

## [0.14.3] — 2026-10-20

Your header, your way.

### Fixed
- **Choose what sits beside the notch.** Settings → Layout → Beside the notch lists
  Shelf, Notes, Screenshots, Clipboard, Mirror, Calendar, Timer, Now Playing, Playlists,
  Apps, Shortcuts, Controls and Notifications. Each can be a tab on the left after Home,
  a circle on the right before the gear, or off. The arrows set the order, and Reset puts
  it back. Home is always first. A view you turn off is still on Home's cards and its
  keyboard shortcut.
- The panel changes as soon as you do — no restart.
- ⌃⇥ and a sideways swipe step through Home, your left tabs, then your right circles.

## [0.14.2] — 2026-10-20

A Settings window you can read.

### Fixed
- **Settings opens much bigger** — about three quarters of the screen, up to
  1240 × 900 — instead of a fixed 880 × 620, so most panes fit without scrolling.
- **It remembers its size and place.** Resize or move it and it opens that way next time.
- On a very wide window, the settings stay a readable width, centred, instead of
  stretching each switch a whole screen away from its name.

## [0.14.1] — 2026-10-20

A meter worth looking at.

### Fixed
- **The bars beside the notch** are four thin rounded bars centred on the band, each
  easing to a new height several times a second and rising and falling together like
  music does — the way Boring Notch and the Dynamic Island draw it. They used to sit on
  the band's bottom edge, jump up by half their height when they started, and bounce on
  a fixed loop. Paused, they ease down to dots.
- **An app holding the microphone** (dictation, a voice note) shows as recording: the
  peek says "Recording" under the app's name, and the bars turn into a red, speech-like
  flicker in place of the music meter.

### Added
- `--meter-filmstrip <file.png>` draws the meter's motion frame by frame, to judge it by
  eye.

## [0.14.0] — 2026-10-20

What's playing, from far more places.

### Added
- **Browser tabs as real tracks.** Safari, Chrome, Arc, Brave, Edge and Vivaldi show what
  a tab is playing — the title, artist or channel, artwork and position — with play,
  pause, seek and volume, and next and previous on YouTube, YouTube Music, Spotify's web
  player and SoundCloud. The browser runs a few lines of script in the tab and answers
  NotchHover; nothing is sent anywhere. Each browser has to allow JavaScript from Apple
  Events once, and Settings → Music → Browsers says where that switch is and whether it's
  on.
- **TV, QuickTime Player and VLC** are read and controlled too.
- **Apple Music artwork.** Music's tracks show their own cover instead of the Music icon,
  and a radio station shows the song that's on rather than the station's name.
- `--media-selftest` checks that every installed player's and browser's scripts compile
  and prints what each running one reports.

### Fixed
- **Safari pages weren't recognised at all.** Inside a script that talks to Safari, `tab`
  means Safari's tab, not the tab character, so every line came back unsplit. Safari's
  playing page is named again, even with JavaScript off.
- Chrome-family browsers that haven't allowed JavaScript now show the playing tab's name
  instead of only the browser.
- The shuffle button is dimmed for things that can't shuffle.

### Privacy
- A playing tab's artwork is a link, like Spotify's, so it's fetched from the image
  server the page already uses. No account information or cookie goes with it.

## [0.13.2] — 2026-10-20

Roomier theme cards and menus.

### Fixed
- **Theme cards** are drawn as small desktops with the panel hanging from the top, its
  tabs and three widgets in the theme's own colours, so the cards no longer look packed.
  The selection ring sits outside the card, and the name has room beneath it.
- **Menu buttons** (Resting bar, On hover, Panel width and the rest) have padding around
  their label and an up-down chevron, and size to their text.
- **The notch stage's** Resting · Peek · Open switch is centred under the panel.

## [0.13.1] — 2026-10-19

Settings, spaced properly.

### Fixed
- **One set of margins everywhere.** Every pane now keeps a 28pt page margin, 18pt
  between blocks, 6pt from a heading to its card, and 14pt inside each row; the search
  field and the sidebar rows share the same edges.
- **Theme cards** fit three to a row across the page instead of running off its edge,
  and each preview fills its card without black bands.
- **The notch stage** fills its width with no seams, and its Resting · Peek · Open switch
  is smaller and sits on the desktop instead of on the panel.
- **Layout** draws the panel hanging from a desktop the width of the page, and the
  widget gallery fills the width in even columns.
- **Playlists, launcher apps and pinned Shortcuts** are rows like every other setting
  rather than old-style boxes with their own headings; Shortcuts are picked from the ones
  you have instead of typed by name.
- **The Shortcuts table** is a card per group, its columns aligned with the rows.
- **The shortcut editor** uses the same cards and rows, labels each step's kind, lines
  every field up, and sizes itself to its steps.
- Text in Settings fields is centred with room at the sides.

## [0.13.0] — 2026-10-19

Quick settings in the notch.

### Added
- **The gear opens quick settings inside the notch**, so you see each change happen:
  - Look: theme, what hovering does, the resting bar, the hover delay
  - Playing: the live visualizer, synced lyrics, music on the lock screen
  - Privacy: clipboard history and clearing it, spoken notifications
  - Keys: trackpad gestures and haptics, plus ⌘K and your hotkeys

  **All settings →** opens the full window, and each **Edit…** opens it on the right
  pane. Picking a theme rebuilds the panel and brings you straight back to quick
  settings. Esc closes them; right-clicking the gear still offers Settings… and Quit.

## [0.12.0] — 2026-10-19

New Settings, and shortcuts you can change and make.

### Added
- **⌘K in the panel**: every action NotchHover has, with its keys. Type to find one, ↵ to
  run it, ⌘E to change its hotkey. It replaces the old list of keys, and ⌘/ opens it too.
- **Settings → Shortcuts**: every action in one table, Raycast-style — search, filter by
  built-in, yours, has a hotkey, or clashes; click a hotkey to record a new one, ⌫ to
  clear it, right-click to reset; switch any action off. Two actions on the same keys are
  flagged in red.
- **Your own shortcuts**: a name, an icon, and steps run in order — open a link (with
  `{query}` for a word you type, or `{clipboard}`), open an app, run a macOS Shortcut, a
  shell command or AppleScript, type text, or wait. Give one a hotkey, or run it from ⌘K.
- **Privacy and permissions** in Settings: what goes beyond your Mac, and every
  permission NotchHover may ask for, whether it has it, and a button to grant it.
- **About** in Settings, with links to the changelog, releases and issues.

### Changed
- **Settings is redesigned** after System Settings: a sidebar of coloured icons with
  search, grouped into what the notch looks like, what it shows, your Mac, and privacy.
  Every setting says what it does in a line underneath, and the ones that reach beyond
  your Mac or ask for a permission say so.
- **A live picture of the notch** sits at the top of Appearance and Layout, and switches
  between resting, peek and open.
- **Layout is drag and drop**: Home's widgets drawn as they sit in the panel — drag one
  to move it, × to remove it, drag one in from the widgets below.
- Hover delay can be set in Appearance.

## [0.11.0] — 2026-10-19

Next in playlist.

### Added
- **Next in playlist for Apple Music.** The Now Playing view lists the next three tracks
  of the playlist or album Music is playing, beside the player; click one to play it now.
  It's hidden while shuffle is on, when the order is Music's own. Spotify keeps its queue
  on its servers, so it can't be read without the internet, and isn't shown.

### Fixed
- **Shuffle for Apple Music** never showed its real state, and the shuffle button did
  nothing: Music names it differently from Spotify.

## [0.10.0] — 2026-10-19

A visualizer that listens.

### Added
- **Live visualizer, opt-in.** Switch it on in Settings → Advanced and the bars beside
  the notch, and in the peek, move with the music itself — bass, middle and treble —
  instead of a loop. It listens only to the app that's playing, turns each moment into
  three numbers and keeps nothing. macOS asks for **System Audio Recording** the first
  time. On Bluetooth headphones, or if the permission is refused, the bars go back to
  their animation.

### Changed
- The bars beside the notch take the colour of the artwork, as the peek's already did.

## [0.9.0] — 2026-10-19

Screenshots.

### Added
- **Screenshots pop out of the notch.** Take one however you like — ⇧⌘3, ⇧⌘4, the
  Screenshot app — and it comes out of the notch, as macOS's own thumbnail does from the
  corner: drag it straight into any app, or **Copy**, mark it up in Preview, put it on the
  shelf, copy the text in it, or move it to the Trash. It stays six seconds, longer while
  the pointer is on it.
- **A Screenshots view** (⌘6, or its tab beside Notes) with the recent ones as a strip.
  Hover one for copy, markup, copy-text and delete; click to copy; drag it out;
  double-click to open it.
- **Take screenshots from the notch** — an area, a window, the whole screen, or in five
  seconds — with **⌃⌥4** for an area from anywhere. The panel gets out of the picture
  first. This uses macOS's own `screencapture`, which asks for Screen Recording the first
  time.

### Notes
- NotchHover doesn't replace macOS's screenshot keys; it watches the folder macOS saves
  to and recognises screenshots by the marker macOS puts on them. If that folder is your
  Desktop or Documents, macOS asks once for NotchHover to see it.

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

[Unreleased]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.18...HEAD
[0.14.18]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.17...v0.14.18
[0.14.17]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.16...v0.14.17
[0.14.16]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.15...v0.14.16
[0.14.15]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.14...v0.14.15
[0.14.14]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.13...v0.14.14
[0.14.13]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.12...v0.14.13
[0.14.12]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.11...v0.14.12
[0.14.11]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.10...v0.14.11
[0.14.10]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.9...v0.14.10
[0.14.9]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.8...v0.14.9
[0.14.8]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.7...v0.14.8
[0.14.7]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.6...v0.14.7
[0.14.6]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.5...v0.14.6
[0.14.5]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.4...v0.14.5
[0.14.4]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.3...v0.14.4
[0.14.3]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.2...v0.14.3
[0.14.2]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.1...v0.14.2
[0.14.1]: https://github.com/BelalElrashidy/NotchHover/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.13.2...v0.14.0
[0.13.2]: https://github.com/BelalElrashidy/NotchHover/compare/v0.13.1...v0.13.2
[0.13.1]: https://github.com/BelalElrashidy/NotchHover/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/BelalElrashidy/NotchHover/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/BelalElrashidy/NotchHover/releases/tag/v0.1.0
