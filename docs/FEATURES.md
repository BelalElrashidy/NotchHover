# NotchHover — feature catalogue

Everything that could live in the notch. Every entry is **local-only**: no accounts, no
servers, no webhooks, no analytics. Where an idea would normally need the internet, the
local alternative is named, or the idea is marked as skipped.

Effort: **S** an afternoon · **M** a few days · **L** a week or more.

Status: ✅ built · 🟡 partly built · ⬜ not started

---

## Capture and recall

| Feature | What it does | How, locally | Effort | Status |
|---|---|---|---|---|
| Quick notes | Type a note, save with ⌘↩, copy it later | JSON in Application Support | M | ✅ |
| Clipboard history | Raycast-style: search, pin, paste back | Polls `NSPasteboard.changeCount`; skips password managers | M | ✅ |
| Snippets | Saved text with a keyword, e.g. `;addr` | Stored like notes; paste via the clipboard's paste path | M | ⬜ |
| Note → clipboard pin | Turn a note into a pinned clipboard item | Glue between the two stores | S | ⬜ |
| Checklist notes | `[ ]` lines become tickable | Parse the note text | S | ⬜ |
| Markdown preview for notes | Bold, lists, code | `AttributedString(markdown:)` | S | ⬜ |
| Scratch calculator | `12*4.5` shows `54` as you type | `NSExpression` | S | ⬜ |
| Unit / time zone conversion | `5km in mi`, `3pm London` | `Measurement`, `TimeZone` | M | ⬜ |
| Colour picker | Pick a colour anywhere, copy hex | `NSColorSampler` | S | ⬜ |
| Screenshot to tray | Area screenshot drops into the file tray | `screencapture -i` to a temp file | S | ⬜ |
| Text from screen (OCR) | Select an area, copy its text | `screencapture` + Vision | M | ⬜ |
| Voice memo | Record a short clip into the tray | AVFoundation | M | ⬜ |
| Clipboard: rich text / colours | Keep formatting, show colour swatches | More pasteboard types | M | ⬜ |
| Clipboard: encrypted at rest | History unreadable to other apps | Keychain key — waits on proper signing | M | ⬜ |
| Clipboard: per-app exclusions UI | Choose apps never recorded | `ClipboardExcludedApps` already exists | S | 🟡 |

## Media

| Feature | What it does | How, locally | Effort | Status |
|---|---|---|---|---|
| Spotify + Music controls | Play, skip, seek, artwork | AppleScript | — | ✅ |
| Pinned playlists | Play a playlist by URI | AppleScript `play track` | — | ✅ |
| Audio visualiser in the resting bar | Bars that move with the music | Faked from play state; a real tap needs permission | M | 🟡 |
| Breathing resting bar | Two breaths when something happens — track change, audio starting, an activity settling | Finite bursts, shape and content on one beat (`NotchBreath`) | S | ✅ |
| Any-app playing detection | Bar wakes for a video, a call, a game | CoreAudio `DeviceIsRunningSomewhere`, debounced | S | ✅ |
| Output device switcher | AirPods / speakers / display | Core Audio | M | ⬜ |
| Per-app volume | | Needs an audio driver — probably skip | L | ⬜ |
| Any-app playing shows its app | A video in a browser shows the browser's icon and name | CoreAudio process objects, parent-walked to the app | S | ✅ |
| Playing page's own icon | A YouTube video shows YouTube's favicon and the video title | Firefox-family session file; favicon is inline, nothing fetched | M | ✅ |
| Same for Safari | Page title and site; Safari's own icon | AppleScript (Automation prompt); favicons need Full Disk Access | S | ✅ |
| Same for Chrome, Arc, Brave, Edge | | AppleScript for the URL, then Chrome's `Favicons` database | M | ⬜ |
| Any-app now playing (browser, Podcasts) | The *track* and transport, not just which app | MediaRemote is restricted on recent macOS | L | ⬜ |
| Synced lyrics | The line being sung, in the peek, Now Playing and the Home card | Opt-in: lrclib.net, once per song, cached on disk | M | ✅ |
| Music on the lock screen | Artwork, title, artist, play/pause and skip while locked — nothing else | Opt-in: a SkyLight space at the lock screen's level | M | ✅ |

## System at a glance

| Feature | What it does | How, locally | Effort | Status |
|---|---|---|---|---|
| Volume / brightness / backlight | Sliders and HUD | Existing monitors | — | ✅ |
| Microphone gain and mute | Slider in Controls; click the icon to mute | CoreAudio input device properties | S | ✅ |
| Battery | Percent, time left, charging activity | IOKit power sources | S | ⬜ |
| CPU / memory / network | Small live gauges | `host_statistics`, `getifaddrs` | M | ⬜ |
| Disk space | Free space, eject external drives | `FileManager`, `NSWorkspace` | S | ⬜ |
| Bluetooth devices | AirPods, headphones, speakers and Magic devices, with battery | `system_profiler` and the I/O registry | M | ✅ |
| Focus mode | Show and toggle Focus | Shortcuts app | S | ⬜ |
| Do-not-disturb while sharing screen | Hide the panel when sharing | `CGWindowList` | M | ⬜ |
| Caffeinate | Keep the Mac awake for N minutes | `IOPMAssertion` | S | ⬜ |
| Wi-Fi name / VPN state | | CoreWLAN (location permission) | S | ⬜ |
| Webcam / mic in use | Privacy dot in the resting bar | Core Media IO / Core Audio | M | ⬜ |

## Time and focus

| Feature | What it does | How, locally | Effort | Status |
|---|---|---|---|---|
| Countdown timer | Mirrors into the resting bar | — | — | ✅ |
| Calendar | Next events | EventKit | — | ✅ |
| Pomodoro | Work/break cycles with a counter | Extends the timer | S | ⬜ |
| Stopwatch | | Extends the timer | S | ⬜ |
| Reminders | Today's reminders, tick them off | EventKit | M | ⬜ |
| Meeting countdown | "Standup in 4 min" in the resting bar | EventKit | S | ✅ |
| Meeting join | Join button for Zoom, Meet, Teams, FaceTime, Webex links | `MeetingLink` from the event's URL, location, notes | S | ✅ |
| World clocks | | `TimeZone` | S | ⬜ |
| Weather | | Needs the internet — skipped, or read a local cache | — | — |

## Files and apps

| Feature | What it does | How, locally | Effort | Status |
|---|---|---|---|---|
| File tray | Drop files, drag out, AirDrop | — | — | ✅ |
| App launcher | | — | — | ✅ |
| Shortcuts | Run macOS Shortcuts | `/usr/bin/shortcuts` | — | ✅ |
| Recent files | Last downloads and screenshots | `FileManager` on known folders | S | ⬜ |
| Quick convert in tray | Image → PNG/JPEG, resize, zip | ImageIO, `ditto` | M | ⬜ |
| Run a script | Pin shell scripts as buttons | `Process` | S | ⬜ |
| Window switcher | Windows of the frontmost app | Accessibility | M | ⬜ |

## Claude Code — the differentiator

| Feature | What it does | How, locally | Effort | Status |
|---|---|---|---|---|
| Approve / deny tool calls | | Local socket bridge | — | ✅ |
| Keyboard approve | ⌘↩ approve, ⎋ deny while open | Panel key handling | S | ⬜ |
| Project badge on approvals | Which repo is asking | Hook payload `cwd` | S | ⬜ |
| Session list | What each session is doing | Read the local transcript folder | M | ✅ |
| "Claude is done" activity | The notch pops when a session hands the turn back | Transcript state, no hook needed | S | ✅ |
| Approval history | What you allowed today | Local log | M | ⬜ |
| Always-allow rules | Per project, per tool | Write the project's settings file | M | ⬜ |
| Token counter | Today and the last five hours, from transcript usage | Transcript usage fields | M | ✅ |
| Plan limits | % of the 5-hour and weekly allowance | Only Anthropic's servers know — not done, no network | — | — |

## The panel itself

| Feature | What it does | How, locally | Effort | Status |
|---|---|---|---|---|
| Flexible widget row, sizes, themes | | — | — | ✅ |
| Tabs beside the notch | Home, Shelf, Notes left; clipboard, mirror, gear right; no bottom bar | — | M | ✅ |
| Three states | Rest → hover peek → click for the full panel | One more rect in the existing morph | M | ✅ |
| Hover dwell | Wait ~0.3s before opening, so passing the notch doesn't open it | `HoverDelay` | S | ✅ |
| Trackpad gestures | Two-finger swipe down to open, up to close, sideways for tabs or tracks | `SwipeRecognizer` over scroll events | M | ✅ |
| Everything by keyboard | Global ⌃⌥ keys, ⌘1–5, media, clipboard arrows, approvals; ⌘/ lists them | Panel key handler | M | ✅ |
| Command bar | Raycast-style: search clips, notes, files, apps; run actions | Builds on the full panel | L | ⬜ |
| Global shortcuts | ⌃⌥V clipboard, ⌃⌥N notes | Carbon hot keys | S | ✅ |
| Shortcut editor | Change those combinations | Key recorder view | M | ⬜ |
| Pin open | Click to keep the panel open | | S | ⬜ |
| Launch at login | | `SMAppService` | S | ⬜ |
| Onboarding + permission status | | | M | ⬜ |
| Drag-reorder widgets in settings | | | M | ⬜ |
| Export / import settings | A file you keep | JSON | S | ⬜ |
| Custom themes | Pick your own colours | | M | ⬜ |
| Haptics | Taps on open, tab change, swipe, approval | `NSHapticFeedbackManager` | S | ✅ |
| Multiple displays | A notch on every display, one open at a time | `NotchDisplay` per screen | M | ✅ |
| Notchless Macs | Fallback strip | | M | 🟡 |

---

## Suggested next picks

1. **Snippets** and **note → pinned clip** — they build straight on what's just been added.
2. **Battery**, **caffeinate**, **meeting countdown** — small, useful every day.
3. **Keyboard approve** and **"Claude is done"** — the Claude Code features nobody else has.
4. **Launch at login** and **onboarding** — needed before release anyway.
