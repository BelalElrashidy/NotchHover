# NotchHover

A menu-bar-only macOS app (`LSUIElement`) that turns the MacBook notch into a hover
panel: media controls, a file tray, app launchers, system sliders, calendar, timer,
notifications — and approval prompts for Claude Code.

Roughly 7,400 lines of Swift across 53 files. AppKit, no SwiftUI, no dependencies.
Requires macOS 14; Liquid Glass and a few niceties are gated to macOS 26.

---

## Build and run

```bash
Scripts/dev.sh                                  # build, install to /Applications, launch, follow the log
Scripts/build-app.sh release --install --run    # same without the log
Scripts/build-app.sh release --run              # run from ./build instead of /Applications
Scripts/check.sh                                # compile, render previews, run the settings self-test
swift build                                     # fastest syntax check
```

There is no Xcode project. `Package.swift` builds a plain executable and
`Scripts/build-app.sh` wraps it in an `.app` bundle with `Resources/Info.plist`, then
ad-hoc signs it. The bundle is not optional: AppleScript automation, `LSUIElement`, and
every TCC permission key off bundle identity.

### Xcode

```bash
open Package.swift
```

Full indexing and refactoring. Do not run the package scheme directly — it produces a
bare executable with no bundle. Point the scheme at the installed app once:

1. Product › Scheme › Edit Scheme
2. **Run › Info › Executable › Other…** → `/Applications/NotchHover.app`
3. **Build › Pre-actions › + › New Run Script Action**, "Provide build settings from:
   NotchHover", then:

   ```sh
   /path/to/NotchHover/Scripts/build-app.sh release --install
   ```

⌘R then rebuilds, installs and launches with the debugger attached.

### Watching what it does

```bash
log stream --predicate 'subsystem == "com.notchhover.NotchHover"' --style compact
```

Categories: `media`, `ui`, `permissions`, `system`, `shortcuts`. Use `log stream`, not
`log show` — these messages do not reliably reach the persisted store.

### The icon

The mark is **the Capstone**: an arch held up by a keystone at top-centre — the notch.

| File | Used as |
|---|---|
| `Resources/AppIcon.icon` | App icon, with separate light, dark and tinted appearances |
| `Resources/MenuBarIcon.png` / `@2x` | The template mark, kept for when a status item returns; unused today |

`AppIcon.icon` is an Icon Composer bundle, not a single image. Its background and both
layers (arch, keystone) are specialised per appearance: a light tile with a dark arch,
and a dark tile with a light arch. `build-app.sh` compiles it with `actool` into
`Assets.car` plus a fallback `AppIcon.icns` for older macOS. This matters on macOS 26:
given only a plain `.icns`, the system fakes Dark mode by darkening the whole tile, which
put the dark arch on a dark background.

Both assets are generated, not drawn by hand. `Design/icon-enhanced/generate.py` builds
the vectors and the `.icon` bundle; `render.swift` rasterises previews and the menu-bar
template. To change the icon, edit the geometry there, re-run, and copy
`AppIcon.icon` into `Resources/`. Check the result with
`xcrun assetutil --info …/Assets.car` — it should list `NSAppearanceNameAqua`,
`NSAppearanceNameDarkAqua` and `ISAppearanceTintable` stacks.

---

## Folder map

Grouped by feature: each feature owns both its logic and the view it shows in the
notch, so adding one means adding a folder, not editing five.

```
Sources/
  App/                  main, AppDelegate            — entry point and wiring
  Core/                 Log, LiveActivity, LocalStore, HotKeys
                                                 — logging, activity bus, on-disk JSON, global shortcuts
  Theme/                Theme, Style, ArtworkColor   — the six themes and the palette
  Notch/                NotchController              — the panel's state machine
    Window/             NotchPanel, NotchGeometry    — the floating window, notch metrics
    Shape/              NotchShape, GlassCardView    — the slab path and its surface
    Layout/             NotchContentView, WidgetRowView, PanelWidget, PanelSizes
                                                 — bands, flex widget row, sizes, resting bar
  Features/
    Spotify/            player + now-playing and playlist views
    FileTray/           the shelf + its drop view
    Apps/               launcher list + tiles + per-app detail
    Shortcuts/          the shortcuts CLI + its view
    Timer/              countdown + its view
    Calendar/           next events
    Notifications/      the banner watcher + its view
    SystemControls/     volume/brightness/backlight + the HUD sliders
    ClaudeCode/         the approval bridge + the approve/deny view
    Mirror/             webcam preview
    Notes/              quick notes store + editor/list view
    Clipboard/          clipboard history + searchable list view
  Settings/             settings window, layout editor, sections, themed controls
  Preview/              offscreen renderer and the animation self-test
```

Every feature follows the same shape: a **service** that talks to the outside world and
a **view** the notch loads. `Features/Spotify` has `MediaHub` (service) and
`MediaDetailView` (view); `Features/FileTray` has `FileTray` and `TrayPaneView`. The
notch knows nothing about Spotify or AirDrop — `WidgetRowView` just asks each feature
for a view.

---

## How it starts

`main.swift` checks for two dev flags before anything else, then hands off to
`AppDelegate`:

```
AppDelegate.applicationDidFinishLaunching
  ├── NSApp.mainMenu = …                    Edit menu, or ⌘V never reaches a text field
  ├── MediaHub ───── AppleScriptMediaProvider (Spotify, Music)
  │     └── NowPlayingPoller ───── NotchController      (panel contents)
  ├── ActivityCenter ◄── VolumeMonitor / BrightnessMonitor / BatteryMonitor
  │                  ◄── NotificationWatcher / CountdownTimer
  │                       └── NotchController → resting bar
  ├── AudioActivityMonitor ─── NotchController  (is anything playing at all?)
  ├── PermissionBridge ──────── NotchController → approval pane
  └── SettingsWindowController (lazy: the notch's gear, ⌘, or reopening the app)
```

Two rules worth preserving:

- **One poller.** `NowPlayingPoller` owns the only timer that reads the player; the menu
  bar and the notch subscribe. Nothing else should poll it.
- **One bus.** Anything momentary — volume, brightness, battery, a notification, a timer
  finishing — is posted to `ActivityCenter` and surfaces in the resting bar.
- **Two answers to "is something playing".** `NowPlayingPoller` knows what Spotify and
  Music are doing. `AudioActivityMonitor` covers everything else — a video in a browser,
  a call, a game — and is stricter than "the output device is running", because that
  alone lies: macOS's own `corespeechd` holds the output open in silence, and Safari's
  audio helper went on holding it for two minutes after its last window closed. So it
  counts only an **app** running output, and not a browser last seen with no tabs open.
  It still can't hear silence: an app that keeps its stream open while idle, like a
  paused video in an open tab or a chat app, reads as playing. Telling those apart needs
  either the system audio-recording permission or macOS's private Now Playing state, and
  neither is used.
- **Whoever is playing gets shown as itself.** When no player we can talk to owns the
  sound, `AudioSourceProbe` asks CoreAudio which processes are running output and turns
  the first real one into an app: its icon on the resting bar, its name in the panel,
  and no transport, because there is nothing to send a command to.
- **And for a browser, the page rather than the browser.** `BrowserPageReader` reads the
  browser's own session file — `sessionstore-backups/recovery.jsonlz4`, Mozilla's LZ4
  container, which the system's Compression framework unpacks as a raw LZ4 block — and
  takes the tab's title, host and favicon from it. The favicon is already in there as a
  `data:` URI, so a site's icon never means fetching anything, and nothing in the path
  needs a permission: Application Support is not TCC-protected. The file is rewritten
  every few seconds, which is soon enough for something that plays for minutes, and it
  is only re-read when its modification date changes. The parse is a few megabytes of
  JSON, so it runs on a utility queue; the cache behind it has its own lock rather than
  using that queue, or reading the last answer from the main thread would wait behind a
  parse in flight. The process that
  holds the audio is rarely the app you would name — browsers play through a content or
  GPU helper with its own bundle id and no icon — so each candidate is walked up its
  parent chain until it reaches something the Dock would show. Daemons never get there
  and are dropped. Needs macOS 14.4 for `kAudioHardwarePropertyProcessObjectList`;
  below that the bar falls back to a plain waveform glyph.

---

## The panel

### States

`NotchController` is the state machine. `NotchContentView.Presentation` has three cases:

| State | What it looks like | Entered when |
|---|---|---|
| `hidden` | Slab shrunk to exactly the notch's size, invisible behind the hardware | Nothing playing and no activity |
| `idle` | Slim bar hugging the notch: artwork one side, level meter the other, still until something happens | Anything playing — a track, or audio we can only hear — per the `RestingBar` setting |
| `expanded` | The full panel | Pointer enters the notch, or a Claude approval arrives |

**Every display has its own notch.** `NotchController` keeps a `NotchDisplay` — panel,
content view, geometry — per screen, re-synced on `didChangeScreenParametersNotification`.
What everyone should see (now playing, activities, the timer, the approvals badge) is
broadcast to all of them; anything interactive goes to the *active* display, the one open
or last opened. Only one is open at a time. Panels sit at `.mainMenu + 3` and join every
Space, full-screen ones included — the level and flags Boring Notch and Atoll use.

**There is no Dock icon and no menu bar icon.** The gear in the panel carries Settings and
Quit; reopening the app from Finder or Spotlight opens Settings; and the very first launch
opens the notch for three seconds, since nothing else says the app is running.

Hover comes from global and local mouse-move monitors comparing `NSEvent.mouseLocation`
against each display's `NotchGeometry.hoverRect`. Mouse monitors need no permissions — keyboard ones
would. While resting, the window sets `ignoresMouseEvents` so it never blocks the menu
bar; it takes clicks only when expanded.

The panel stays pinned while a Claude Code approval is waiting, and refuses to rebuild
itself for a settings change until that is answered.

### Geometry and shape

`NotchGeometry` reads `safeAreaInsets.top` and the gap between `auxiliaryTopLeftArea`
and `auxiliaryTopRightArea` to find the notch — 179 × 32 pt on a 13" M2 Air. Notchless
displays get a fallback strip so the app still works on an external monitor.

`NotchShape` draws the slab: flush with the top of the screen, concave circular flare
corners that curve outward into the menu bar, continuous ("squircle") bottom corners.
The flare is clamped by both width and height, because the resting bar is shorter than
the flare is deep.

`GlassCardView` paints the surface — a solid colour or `NSGlassEffectView` — and masks
the whole card to that path. The material is only ever a backdrop: content lives in a
sibling container with identical layout whichever material is chosen.

### Layout

`NotchContentView` holds two regions:

- the **header band** beside the notch, which is the navigation. Left: `HeaderTabsView`,
  a capsule with Home, Shelf and Notes, where only the selected tab is named — three
  names need ~180pt and the wing has ~140 at the default width. Right:
  `HeaderActionsView`, with circles for the clipboard and the mirror, the gear, and the
  battery, which an approvals badge replaces when Claude Code is waiting.
- the **detail area**, the full height of the rest of the panel: Home's widget row, the
  Shelf (the same row fixed to files beside recent clips), Notes, or a view reached from
  the header — the full clipboard, the mirror, an approval.

The band used to repeat what was playing, ~40pt above the pane that already showed it,
and thirteen unlabelled tabs ran along the bottom edge clipping whatever sat above them.
The layout follows Boring Notch and Atoll instead: navigation in the wings, no bottom bar,
and few tabs — everything else is a Home card, a header button or a shortcut.

### Rest, peek, open

Resting on the notch waits `HoverDelay` (0.3s) — passing it on the way to the menu bar
does nothing — then brings up the **peek**: the resting bar grown into a card about
470pt wide against the panel's 738, laid out like the Dynamic Island's expanded view.
Playing: artwork, title and artist, the level meter in the artwork's colour
(`ArtworkColor.meterColor`), a scrubber that runs on between poller ticks, and the
transport. A call about to start: the service's tile, a countdown and a green Join. With
nothing on: the time, the date and the next event. The card is as tall as what it shows
(`PeekView.preferredHeight`) and refits when that changes. A click on it, a swipe down
or a shortcut opens the full panel; leaving it puts it back at once. It is one more rect
in the same morph, and `PeekView` only hit-tests while it is on screen. `HoverAction` set
to `open` skips it.

### Calendar, accessories, Claude Code

- `CalendarPaneView` is the schedule: `DayStripView` (seven days, today red, a dot on
  busy days, click to pick), all-day capsules, and `TimelineView` — a whole day at 36pt
  an hour in a scroll view, opened just before now, events side by side when they
  overlap, Join chips in each service's colour, a red now line. It reloads itself on
  `EKEventStoreChanged` and every minute while on screen.
- `CalendarService` is the one EventKit store; `MeetingLink` finds Zoom, Meet, Teams,
  FaceTime and Webex links in an event's URL, location or notes and opens Zoom and
  Teams in their apps. Two minutes before a call with a link, the notch pops.
- `DeviceBatteryMonitor` reads accessory levels from `system_profiler` and the I/O
  registry — when an audio device comes or goes, and every ten minutes while anything
  is connected — and pops on connect and at 20% and 10%.
- `ClaudeSessionMonitor` reads `~/.claude/projects` transcripts for metadata only, each
  from where the last read stopped, every three seconds: active sessions and their
  state, token use today and over the last five hours, and "Claude is done" when a
  session hands the turn back.

### Lyrics and the lock screen

Both are off until switched on in Settings → Advanced.

- `LyricsService` takes every poller reading. For a Spotify or Music track with a length
  it looks for the song in its disk cache (Application Support/NotchHover/Lyrics, one
  file per song, empty for "none") and otherwise asks lrclib.net once — `/api/get` with
  title, artist, album and length, or `/api/search` when there is no album. 404 and
  instrumental answers are cached as "none"; a busy server or no network is not, and is
  tried again next launch. The current line is worked out every quarter second from
  where the track was at the last tick, shown a third of a second early. The peek, the
  Now Playing tab and the Home card (instead of the artist) listen for it.
- `LockScreenMusic` listens for `com.apple.screenIsLocked` / `screenIsUnlocked`. While
  locked, with a track, it opens a window of its own — a `PeekView` on a notch-shaped
  card — and `LockScreenSpace` moves it into a SkyLight space raised to level 400, where
  the lock screen's notifications live. On unlock the window is removed and thrown away.
  The notch's own panels never go to the lock screen.

### Meeting controls

`MeetingControls` looks every two seconds for a call: Zoom's **Meeting** menu (it exists
only in a meeting, and its items read "Mute Audio"/"Unmute Audio"), or a known call app
using the microphone (`AudioSourceProbe.recordingApplications`, CoreAudio process
objects). Zoom is pressed through that menu; Teams through its call-bar buttons found by
Accessibility label, falling back to ⇧⌘M/⇧⌘O/⇧⌘H posted to its process; Webex by its
shortcuts; Google Meet by AppleScript running a line of JavaScript in the Meet tab, which
clicks the `data-is-muted` buttons and reads their state — browsers ship that switched
off ("Allow JavaScript from Apple Events"), and the peek says so. FaceTime, Slack and
anything else get the Mac's own microphone mute. A call outranks everything in the peek;
⌃⌥M and ⌘⇧M mute it.

### Keyboard and gestures

Everything in the panel has a key. `NotchPanel` passes keys to
`NotchContentView.handleKey`: ⌘ combinations first, before the main menu or a text view
sees them, and plain keys last, only when nothing focused wanted them. Shortcuts a text
field also uses — ⌘← moves the cursor, ⌘⌫ deletes a line — are left alone while one is
focused. Global ⌃⌥H/S/N/V open a view or, pressed again, close the panel; a panel opened
from the keyboard stays open until the keyboard closes it. `KeyboardShortcutList` is the
one list of them all, and ⌘/ shows it over the panel.

Two-finger swipes go through `SwipeRecognizer`, which reads the direction the *fingers*
moved — macOS reports scroll deltas in content terms, so natural scrolling flips them —
fires at most once per gesture, and ignores mouse wheels and momentum. Over a notch that
isn't open the panel ignores the mouse, so swipes there come from a global monitor (it
can watch, not swallow); over the open panel a local monitor keeps a swipe from also
scrolling something, except vertical movement over a list, which is the list's. A
deliberate close — a swipe, Esc, a shortcut — suppresses hover until the pointer leaves
the notch, or the pointer resting there would open it again at once. `Haptics` taps on
open, tab changes, swipes and approvals.

### The widget row

There are no fixed zones. The panel holds an **ordered list of widgets**
(`PanelLayoutStore`, stored as `PanelWidgets`), and `WidgetRowView` lays them out like
a CSS flex row.

Each `PanelWidget` declares a profile:

| Property | Meaning |
|---|---|
| `minWidth` | Never drawn narrower than this — dropped instead |
| `idealWidth` | What it would like if there is room |
| `grow` | Its share of leftover space, exactly like `flex-grow` |
| `dropPriority` | Lower goes first when the row runs out of room |

Layout runs in three passes: give every widget its minimum; grow each toward its ideal
in proportion to how far it is off; share anything still left by `grow`. If even the
minimums overflow, the lowest-priority widget is dropped and the row is measured again.
One widget fills the panel, five share it.

A widget's final width also picks a `WidgetSizeClass` — **mini** under 170pt,
**compact** under 240pt, **regular** above — and the row rebuilds a widget's view when
it crosses a boundary. So a narrow Now playing shows artwork and transport, and a wide
one adds the scrubber and volume, rather than one layout being squeezed.

Adding a widget: add a `PanelWidget` case with its profile, and a branch in
`WidgetRowView.makeView(for:sizeClass:)`.

### Sizes

`PanelSizes` replaces what used to be hardcoded constants. Every value is clamped on
read, so a bad stored number can never produce an unusable panel.

| Setting | Range | Default |
|---|---|---|
| Panel width | `auto`, or 420–1400pt fixed | auto — the widgets' ideal widths plus flare |
| Panel height | 110–320pt | 152 |
| Resting bar sides | 0–200pt | 30 |
| Resting bar drop below the notch | 0–40pt | 0 |
| Corner radius | 12–48pt | 34 |
| Flare | 0–60pt | 36 |
| Text size | 85–130% | 100%, on top of the theme's own scale |

The top-band wings are derived from the final width rather than fixed, so the band
always matches the panel.

### Animation

Every transition between hidden, resting bar and panel is **a morph of one shape**,
centred on the notch.

The card view always spans the whole panel and never moves. What animates is the slab's
`CGPath`: `GlassCardView.animateShape(to:)` runs a `CABasicAnimation` on the `path` of
both the painted surface and the clipping mask, so content is revealed outward from the
middle as the shape grows and swallowed back toward it as it shrinks.

The three shapes:

| State | Rect |
|---|---|
| hidden | exactly the notch — the slab's body is inset by its flare, so the whole thing sits behind the hardware |
| resting bar | the notch plus flare plus the resting-bar sides, optionally dropped below |
| resting bar, holding an activity | as above, at one fixed width shared by every kind of activity |
| panel | the full panel size |

Rules that make it feel right:

- **Direction is decided by area.** Hidden → resting bar and resting bar → panel both
  count as opening.
- **Opening** is a cubic ease-out over 0.38s. **Closing** is an ease-in-out over 0.28s,
  so the shrink is actually seen.
- **Every animation starts from what is on screen** (the presentation layer's path), so
  hovering back mid-animation reverses smoothly instead of jumping.
- **Content leaves first and arrives late** — outgoing fades in 40% of the duration,
  incoming waits until the shape has made room — so it is never squeezed.
- **The surface is never faded in**; it starts behind the notch. It is only faded out
  once a close has finished shrinking into it.
- The window stays ordered in for 0.34s after closing so the animation is not cut off.

### Breathing and popping

The resting bar is not a still image. Two things move it, both of them still just the
one shape:

- **Breathing.** A breath is a *reaction*, not a state. Something happens — music
  starts, the track changes, a video begins, an activity settles back — and the bar
  takes two breaths and is still again. It ran continuously at first, tied to playback,
  and a notch that never sits still is just something moving at the top of the screen;
  motion that is always there says nothing when it matters.

  One breath swells the slab 12pt on each side and 1pt deeper, and scales the artwork
  and meter riding on it to 1.05, over a 1.5s half-cycle. It is mostly sideways on
  purpose: the bar hangs off the menu bar, so height that comes and goes reads as the
  notch growing rather than as breathing. The numbers live in one place, `NotchBreath`.

  Two rules keep it out of the way of everything else, both because breath and morph
  animate the same `path` and the later animation is what gets drawn:
  `animateShape` stops a running breath before it starts, and re-arms it if breaths are
  still owed; and `breathe(cycles:)` asked for mid-morph waits for `transitionEndsAt`
  rather than starting on top of it — which would snap the shape to its final size and
  breathe from there. The card starts the shape's breath and the content's in the same
  turn of the run loop, so the two share a phase without one being pinned to a clock.
- **Popping.** An activity — a notification, volume, battery, the timer — arrives by
  `popShape`, a three-value keyframe that overshoots the target by 12pt and settles
  back. A bar that is already out pops in place; a bar that is away grows out of the
  notch and pops at the end of it. The pop is that event's whole motion — any breath
  owed is dropped while an activity is showing — and the bar takes a single breath as it
  shrinks back, so the hand-off is not a dead stop.

**Every activity is the same size.** `IdleActivityView.requiredBarWidth` is one
constant — the notch, plus the icon on one side and a slot of the same width on the
other — so a banner and a volume change produce an identical bar, and a long title is
truncated rather than allowed to throw the notch open. Sizing the bar per event was
tried first and abandoned: a notification stretched it to nearly the width of the whole
panel, and no two events looked alike.

Content is laid out inside the slab's *straight body* — the shape minus its flare, which
is clamped by the bar's height, not by `topFlare` — because anything wider is cut away
by the mask. Each side centres its own content, since the shape has to stay centred on
the notch.

Two mistakes this design replaced, worth not repeating: animating the view's *frame*
while `layout()` snapped the path to its final size — which made the panel slide in from
the right — and a hidden shape wider than the notch, which forced a fade instead of a
grow.

---

## Features

| Feature | Service | View | Notes |
|---|---|---|---|
| Spotify / Music | `MediaHub`, `AppleScriptMediaProvider` | `MediaDetailView`, `PlaylistsPaneView` | Auto-switches to whichever player is playing |
| Anything else playing | `AudioActivityMonitor`, `AudioSourceProbe`, `BrowserPageReader` | Same views, `NowPlayingState.external` | The app, or the page it is playing, with no transport to offer |
| File tray | `FileTray` | `TrayPaneView` | Drop, drag out, AirDrop via the share sheet |
| Apps | `AppShortcutStore`, `AppDetailProvider` | `AppsPaneView`, `AppDetailView` | Claude gets a real status pane; others just launch |
| Shortcuts | `ShortcutsRunner` | `ShortcutsPaneView` | Shells out to `/usr/bin/shortcuts` |
| Timer | `CountdownTimer` | `TimerPaneView` | Countdown mirrors into the resting bar |
| Calendar | EventKit, inline | `CalendarPaneView` | Next 24 hours |
| Notifications | `NotificationWatcher` | `NotificationsPaneView` | Reads banners over the Accessibility API |
| System controls | `SystemControls`, monitors | `SystemPaneView` | Volume, microphone gain and mute, display brightness, keyboard backlight |
| Claude Code | `PermissionBridge` | `PermissionDetailView` | Approve/deny tool calls from the notch |
| Mirror | — | `MirrorPaneView` | Camera preview, stops itself when hidden |
| Quick notes | `NotesStore` | `NotesPaneView` | ⌃⌥N; ⌘↩ saves; draft survives closing |
| Clipboard | `ClipboardHistory` | `ClipboardPaneView` | ⌃⌥V; search, pin, copy, paste back |

### Media

Spotify and Music share the same AppleScript vocabulary, so one parameterised provider
covers both. One script per poll returns name, artist, artwork URL, play state,
position, duration, volume and shuffle. Spotify reports duration in milliseconds, Music
in seconds — the provider normalises.

**What the bar shows is a ranking**, decided in one place, `NotchController.nowPlayingState(for:fallback:)`:

1. a track that is actually playing — artwork, title, working transport;
2. otherwise whatever else is making sound, as its app;
3. otherwise a track sitting paused;
4. otherwise a message.

Both poll outcomes end at that one decision, and the ordering is the whole point.
Ranking any track above live audio left Spotify's artwork on the bar, paused, while a
video played in a browser — and rendering the failure branch's message straight to the
panel put "Spotify is not running" there every 2.5s while that same video played. A
player that is closed, or broken, is not news while something else is playing.

What AppleScript **cannot** do: list your playlists. Spotify's dictionary has no
playlist collection. Playlists are therefore pinned by URI; `play track` accepts any
Spotify URI, and `SpotifyURI.normalize` turns a pasted share link into one. Browsing
your library would need the Spotify Web API and OAuth.

### Quick notes and clipboard

Both keep their data in `~/Library/Application Support/NotchHover` through `LocalStore`:
the folder is created `0700`, every file is written atomically and set to `0600`.
Nothing leaves the Mac.

- `notes.json` — up to 500 notes. Editing an existing note saves as you type (debounced
  0.6s). The unsaved draft lives in the `NoteDraft` default.
- `Clipboard/history.json` plus `Clipboard/*.png` — up to 250 unpinned items; pinned
  items never expire and survive *Clear*. Images are downscaled to 1600px.

**Recording.** `ClipboardHistory` polls `NSPasteboard.changeCount` every 0.5s — there is
no change notification on macOS. A copy is skipped when:
- it carries a [nspasteboard.org](http://nspasteboard.org) marker —
  `ConcealedType`, `TransientType` or `AutoGeneratedType` (password managers set these);
- the frontmost app is in `ClipboardExcludedApps` (Keychain Access, Passwords,
  1Password, Bitwarden, LastPass, Dashlane by default);
- recording is paused (`ClipboardPaused`);
- the app itself just wrote it (`ignoreNextChange`, used by *Copy* in both panes).

Copying the same text again moves the existing item to the top and bumps `copyCount`.

**Pasting back** hides the panel instantly, writes the item, waits 0.12s for focus to
return to the previous app, then posts ⌘V with `CGEvent`. That needs Accessibility;
without it the item is only copied.

**Shortcuts.** `HotKeys` registers ⌃⌥V and ⌃⌥N with Carbon's `RegisterEventHotKey`,
which sees only its own combinations and needs no permission. Both call
`NotchController.open(_:)`, which expands the panel, makes it key and focuses the text
field.

**Keyboard focus.** A non-activating panel keeps key status after it closes, which would
steal typing from the app underneath. `releaseKeyFocus` orders the panel out and back in
once the collapse finishes. While a text view in the panel is first responder
(`isEditingText`), moving the pointer away does not close the panel; resigning key does.

### Claude Code approvals

`PermissionBridge` listens on loopback and writes its port and a random token to
`~/Library/Application Support/NotchHover/bridge.json` (0600).
`Scripts/claude-permission-hook.py` runs as a `PreToolUse` hook, sends the pending tool
call as one JSON line, and blocks until you click Approve or Deny in the notch.

Every failure path — timeout, bad token, app not running, unparseable payload — returns
`ask`, which falls back to Claude Code's own prompt. It never approves on its own.
Requests queue FIFO with a "+N more waiting" counter, and each has a 50-second timeout
just under the hook's own.

```bash
Scripts/install-claude-hook.sh              # register the hook (backs up settings.json)
Scripts/install-claude-hook.sh --uninstall  # remove it
```

The matcher defaults to `Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch` rather than
`*`, so reads your settings would auto-allow do not start asking for clicks.

---

## Theming

`Theme` carries every visual decision: surface, three text levels, accent, control fill,
corner radius, type scale, whether text needs a shadow, whether it follows artwork.
`Style` reads the active theme, so **no view hardcodes a colour** — that is what makes a
light theme possible at all.

Six themes: Midnight, Graphite, Frost (light), Clear glass (Liquid Glass), Artwork tint,
High contrast (1.15× type scale).

Artwork tint averages the cover with `CIAreaAverage`, then clamps saturation to
0.28–0.62 and brightness to 0.14–0.26 so white text stays readable on any cover. It
recolours live as tracks change, without rebuilding the panel.

The theme is the **only** thing baked in at panel-build time. Changing it rebuilds the
panel; zones, playlists, resting-bar mode and the app list are read live.

---

## Settings

A sidebar window: Appearance, Layout, Playlists, Shortcuts, Apps, Advanced, with a live
preview of the real panel underneath, rendered by `PreviewRenderer`.

**Layout** is the layout editor (`LayoutEditorView`): one chip per widget in panel order,
with ◀ ▶ to reorder and ✕ to remove, an "Add widget…" menu of what is not in use, a
readout of how much width the set wants, and sliders for every `PanelSizes` value. The
preview redraws as you drag. The detail area scrolls, so a long pane never collides
with the preview.

There is no Save button — every control writes as you change it. Text fields commit on
Enter or focus loss; Done commits anything still being typed, then closes.

Controls are drawn from the theme, not stock AppKit: `SettingsStyle` provides themed
fields, capsules and cards, plus `SegmentedRow`, `ToggleRow` and `MenuButton`. Stock
controls only follow light/dark and stayed grey whatever the theme.

### Stored settings

All under `com.notchhover.NotchHover`.

| Key | Values | Meaning |
|---|---|---|
| `Theme` | `midnight` `graphite` `frost` `glass` `artwork` `contrast` | Active theme |
| `RestingBar` | `always` `playing` `never` | When the resting bar shows |
| `PanelWidgets` | `["media","notes","clipboard","tray", …]` | Widgets in panel order |
| `PanelWidthMode` | `auto` `fixed` | Whether width follows the widgets |
| `PanelWidth` / `PanelHeight` | points | Panel size |
| `RestingWing` / `RestingExtraHeight` | points | Resting bar sides and drop |
| `PanelCornerRadius` / `PanelFlare` | points | Slab shape |
| `PanelTypeScale` | 0.85–1.3 | Text size multiplier |
| `Playlists` | `["Name\|spotify:playlist:id", …]` | Pinned playlists |
| `PinnedShortcuts` | `["Shortcut name", …]` | Shortcuts row |
| `ShortcutBundleIdentifiers` | `["com.apple.Safari", …]` | Launcher apps |
| `SpeakNotifications` | bool | Read notifications aloud |
| `ClipboardPaused` | bool | Stop recording clipboard history |
| `ClipboardExcludedApps` | `["com.agilebits.onepassword7", …]` | Apps never recorded |
| `NoteDraft` | string | Unsaved text in the notes editor |
| `HoverAction` | `peek` `open` | What resting on the notch does |
| `HoverDelay` | 0–1.5 s | How long the pointer rests before the peek |
| `TrackpadGestures` / `Haptics` | bool | Swipes on the notch; haptic taps |
| `SyncedLyrics` | bool | Look up lyrics on lrclib.net (off by default) |
| `LockScreenMusic` | bool | Music card on the lock screen (off by default) |
| `Material` | legacy | Migrated to `Theme` on read |
| `ZoneLeft` / `ZoneMiddle` / `ZoneRight` | legacy | Migrated to `PanelWidgets`; an unset position keeps its old default |

---

## Private API, deliberately

Four things have no public API. Each resolves at runtime and degrades to a no-op — a
greyed-out row, or a feature that never fires — rather than crashing:

| What | How |
|---|---|
| Display brightness | `DisplayServicesGetBrightness` / `SetBrightness` via `dlopen` |
| Keyboard backlight | `KeyboardBrightnessClient` via the Objective-C runtime |
| Notification banners | Accessibility API against `com.apple.notificationcenterui` |
| Meeting controls | Accessibility on the call app's menus and buttons; AppleScript + JavaScript in a Meet tab |
| Music on the lock screen | `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`, `SLSRemoveWindowsFromSpaces` from SkyLight via `dlopen` — the technique Boring Notch uses through the MIT-licensed SkyLightWindow package |

The Notification Center database (`group.com.apple.usernoted`) was the alternative for
notifications; it needs Full Disk Access, which is far broader than this feature
deserves.

---

## Permissions

| Permission | For | Granted |
|---|---|---|
| Automation → Spotify / Music | Reading and controlling playback | Prompt on first use |
| Accessibility | Reading notification banners | System Settings › Privacy › Accessibility |
| Calendar | The calendar widget | Prompt on first open |
| Camera | The mirror widget | Prompt on first use |
| Accessibility | Pasting a clipboard item back (⌘V) | Same grant as notifications |

Permissions attach to a specific copy of the app, so the build-folder copy and the
installed copy are granted separately — prefer `--install` so you always exercise the
same one.

---

## Testing without a screen

The app cannot screenshot itself, so it renders itself instead:

```bash
./build/NotchHover.app/Contents/MacOS/NotchHover --render-preview <dir>   # PNG per theme and pane
./build/NotchHover.app/Contents/MacOS/NotchHover --settings-selftest      # drives settings, snapshots it
./build/NotchHover.app/Contents/MacOS/NotchHover --settings               # open straight to settings
./build/NotchHover.app/Contents/MacOS/NotchHover --animation-selftest     # measures every transition
./build/NotchHover.app/Contents/MacOS/NotchHover --typing-selftest        # clickable buttons, keyboard, typing
./build/NotchHover.app/Contents/MacOS/NotchHover --gesture-selftest       # synthetic trackpad swipes
./build/NotchHover.app/Contents/MacOS/NotchHover --calendar-selftest      # meeting links in invitations
./build/NotchHover.app/Contents/MacOS/NotchHover --devices-selftest       # accessory batteries
./build/NotchHover.app/Contents/MacOS/NotchHover --claude-selftest        # this Mac's Claude Code sessions
./build/NotchHover.app/Contents/MacOS/NotchHover --lyrics-selftest [live] # LRC timing; `live` asks lrclib.net once
./build/NotchHover.app/Contents/MacOS/NotchHover --lockscreen-selftest    # an invisible window onto the lock screen space
```

`--animation-selftest` puts a real panel on screen, runs hidden → resting bar → panel →
resting bar → hidden, samples the drawn shape every 40ms, and reports the widths and how
far the centre drifted. A healthy run shows smooth easing and **0.0pt** drift in every
direction:

```
hidden → resting bar:  217 → 249 → 272 → 287 → 297 → 306 → 311 → 312
resting bar → hidden:  305 → 271 → 226 → 200 → 187 → 181 → 180
```

`PreviewRenderer` builds a real `NotchContentView`, draws the slab path, clips to it
exactly as the live mask does, and composites the view tree on top. Glass cannot be
captured offscreen, so glass themes render with a flat stand-in.

These caught six bugs that would otherwise have shipped: a crash on the Clear glass
accent, the settings window freezing on add/remove, white-on-white labels in Frost, controls
clipped by the corner curves, a settings migration that silently shrank the panel to one
widget, and the panel sliding in from the side instead of growing from the notch.

---

## Gotchas

- **Rebuilding changes the code signature.** Ad-hoc signing means macOS may re-ask for
  Automation and an Accessibility grant can go stale. Reset with
  `tccutil reset AppleEvents com.notchhover.NotchHover`.
- **Cocoa vs Core Graphics coordinates.** `NSEvent.mouseLocation` is bottom-left origin,
  `CGEvent` is top-left. A pointer at the top of the screen reports `y == frame.maxY`,
  which `CGRect.contains` treats as *outside* — hence `containsPointer`.
- **Non-activating panels swallow the first click.** Controls need
  `acceptsFirstMouse`, which is why `ClickThroughButton` exists.
- **An accessory app has no menu bar,** so ⌘V never reaches a text field until you build
  an Edit menu yourself.
- **Layer-hosted views do not appear in `cacheDisplay`.** The preview renderer uses
  `displayIgnoringOpacity`.
- **`NSColor.getWhite` throws on an sRGB colour.** Read the components and compute
  luminance.
- **Never mutate a model from a control's action if that mutation rebuilds the control.**
  Removing a view fires its action, which mutates, which rebuilds — an infinite loop
  that freezes the window. Settings rows read their fields in one pass instead.
- **Never animate a masked view's frame and set its mask path in `layout()`.** The path
  snaps to the final size while the frame travels, so the shape appears to slide in
  from one side. Animate the path itself.
- **A scroll view's document needs a bottom constraint and a flipped view,** or it
  collapses to zero height and draws from the bottom.
- **The mask clips content.** Anything flush to the slab's edge gets cut by the corner
  curves; that is what `Metrics.detailInset` is for.
- **`play track` on a paused player is not the same as `playpause`.** Players report the
  outgoing track for a moment after a skip, so transport commands wait ~0.35s before
  re-reading.

---

## Known gaps

- **Clipboard history is not encrypted at rest.** It's owner-only on disk; a Keychain key
  would prompt on every ad-hoc rebuild, so it waits for real signing.
- **The global shortcuts are fixed** at ⌃⌥V / ⌃⌥N; there is no recorder yet.

- **Drag-and-drop onto the notch is untested.** The code path is there; synthesising a
  real file drag was not possible during development.
- **Notifications need the Accessibility grant** before the watcher does anything — and
  so, therefore, does the resting bar's pop for them. Volume, brightness, battery and
  the timer need nothing.
- **"Something is playing" is device-wide, not per app.** CoreAudio reports only that
  the output device is running, so a long enough alert sound would light the bar up. A
  0.6s lead-in and a 2.5s tail keep that from flickering.
- **Which tab is playing is a guess.** Nothing in the session file says which tab owns
  the audio, so a known media host wins if one is open, and otherwise the most recently
  touched page does — provided it was touched in the last half hour. Two YouTube tabs
  open and the wrong one can win.
- **Only Firefox-family browsers are read.** Firefox, Zen, LibreWolf, Waterfox and
  Floorp share the profile format. Chrome would need AppleScript for the tab's URL plus
  its own `Favicons` database, and Safari keeps its favicon cache inside a container
  that needs Full Disk Access — so both fall back to the browser's app icon.
- **Some inputs have no gain control.** Most USB interfaces and some Bluetooth headsets
  expose no input volume; the microphone row dims its bar and still offers mute.
- **macOS still draws its own volume and brightness HUD** alongside ours. Suppressing it
  means unloading `OSDUIHelper`, a system-level change left undone deliberately.
- **No Bluetooth live activity** — it needs the deprecated IOBluetooth framework.
- **No launch at login.** Would be `SMAppService`.
- **Playlists and Shortcuts editors are plain row lists,** the least polished part of
  settings.
- **Widget reordering uses ◀ ▶ buttons,** not drag-and-drop.
- **Size classes are only fully used by Now playing, Apps and File tray;** the other
  widgets render the same at every width.
