# NotchHover — plan for a public release

Read this, cross out what you don't want, and we build the rest. Nothing here is
started yet. Effort is rough: **S** = an afternoon, **M** = a day or two, **L** = a week.

---

## 1. Where we actually are

Working and verified: media (Spotify + Music), three-zone panel, six themes, file tray,
timer, shortcuts, calendar, HUD sliders, Claude Code approvals, themed auto-saving
settings, install to /Applications.

Unproven: file drag-and-drop (never tested with a real drag), notifications (blocked on
your Accessibility grant).

Known weak points: settings still feels wrong to you, zones are rigid, nothing about
size is adjustable, no app icon, no way for anyone else to install it.

---

## 2. Flexible widgets, not three zones

### The idea

Drop `ZonePosition` entirely. The panel holds an **ordered list of widgets**, and lays
them out exactly like a CSS flex row.

Each widget declares a small profile:

| Property | Meaning | Example |
|---|---|---|
| `minWidth` | Below this it should not be shown at all | Media 150, Tray 120, Apps 110 |
| `idealWidth` | What it wants if space allows | Media 240, Tray 200, Apps 180 |
| `grow` | Share of leftover space it absorbs | Media 1, Tray 1, Apps 0 |
| `priority` | What gets dropped first when space runs out | lower = dropped first |

Layout is then the flexbox algorithm: give everyone `minWidth`, distribute what's left
by `grow`, and if even the minimums don't fit, drop the lowest-priority widget and
retry. One widget fills the panel; five share it; six squeeze or the last one is
dropped with a "+1" chip.

### Responsive widgets

Flex alone isn't enough — a 150pt media widget can't show what a 300pt one does. Each
widget gets **size classes** and renders differently per class:

| Class | Width | Media shows |
|---|---|---|
| mini | < 170 | Artwork + play/pause |
| compact | 170–240 | Artwork, title, transport |
| regular | 240+ | …plus scrubber and volume |

This is what makes "add one and the rest squish" feel deliberate rather than broken.

**Effort: L.** A small layout engine (~150 lines), plus size-class variants for each of
the ten widgets. The widgets already have compact variants, which is half of it.

### Also worth having

- **Drag to reorder** widgets in settings, not just pick per slot — **M**
- **Per-widget options** (tray: how many files; apps: which apps; media: show scrubber) — **M**
- **Multiple layouts** you can switch between, e.g. Work and Music — **M**

---

## 3. Sizes you can change

Everything is currently hardcoded in `NotchContentView.Metrics`.

| Setting | Range | Notes |
|---|---|---|
| Expanded width | auto, or 400–1200 | Auto = sum of widget ideal widths |
| Expanded height | 120–320 | Detail area grows; band stays notch height |
| Resting bar width | auto, or notch + 0–200 | Auto = fits its content |
| Resting bar height | notch height + 0–40 | Can hang below the notch or match it exactly |
| Corner radius | 12–48 | Bottom corners |
| Flare | 0–60 | The inverted top corners |
| Type scale | 0.85–1.3 | Independent of theme |

Two hard floors the UI must enforce: the resting bar can't be narrower than the notch,
and the expanded panel can't be narrower than the widgets' minimums plus the flare.

Sliders belong next to the live preview so you see it as you drag.

**Effort: M** for sizes, **S** for radius/flare/type scale once `Metrics` reads settings
instead of constants.

---

## 4. Settings, third attempt

You've disliked two versions. Rather than guess again, here are three shapes — pick one:

**A. One page, live panel on top.** The real panel sits at the top of the window,
full size, always visible. Everything below is one scrollable column of grouped rows.
No sidebar, no categories. Simplest thing that could work; best when there are ~20
settings.

**B. Layout editor first.** The window is mostly a canvas: your panel, with widgets you
drag to reorder, drag out to remove, and a "+" to add. Sliders for size run along the
edge. Everything else (playlists, shortcuts, apps, advanced) hides behind a small
"More settings" link. Best if layout is the thing you change most.

**C. NotchNook-style panels.** A toolbar of icon tabs, one panel each, dense rows,
live preview docked at the bottom. Closest to what people expect from a paid Mac app.

My recommendation: **B**, because everything you've disliked so far has been about
layout, and B makes layout the whole window instead of a dropdown buried in a category.

**Effort: M** for any of them — the controls already exist and are themed.

---

## 5. Local-only, and where that's currently untrue

You want nothing leaving the machine. Today, almost nothing does:

| Part | Network? |
|---|---|
| Media control | No — AppleScript to a local app |
| Claude Code approvals | Loopback only, token-protected, 0600 config |
| Shortcuts, timer, tray, calendar, system controls | No |
| Notifications | No — read locally over Accessibility |
| Telemetry, analytics, crash reporting | None. There is no networking code for it |
| **Album artwork** | **Yes** — fetched from Spotify's CDN over HTTPS |

Artwork is the single exception. Spotify's AppleScript returns an image URL, not the
image, so showing the cover means fetching `i.scdn.co`. No account data is sent — it's
an unauthenticated image request — but it is an outbound connection.

Three options:

1. **Keep it, disclose it.** One line in settings: "Album art is fetched from Spotify's
   image server." — **S**
2. **Make it a toggle**, defaulting on, falling back to the app icon when off — **S**
3. **Read artwork locally.** Music.app can return raw image data over AppleScript, so
   Music becomes fully offline. Spotify cannot — its cache format is undocumented — so
   Spotify would show its app icon instead. — **M**

I'd do 2, and 3 for Music only.

Also worth stating plainly in the README, because people will ask: **no webhooks, no
telemetry, no accounts, no cloud sync, no auto-update phoning home.** Settings live in
your own `defaults` domain.

### The one unavoidable connection

If you want people to install it without right-clicking past Gatekeeper, the app must be
**notarized** — which means uploading the build to Apple once per release. That is a
build-time connection from your machine, not a runtime one from theirs. There is no way
around it short of telling users to bypass Gatekeeper manually.

---

## 6. Ideas for a public release

The full, local-only catalogue of feature ideas is in [FEATURES.md](FEATURES.md).

### Must have before anyone else installs it

| Item | Why | Effort |
|---|---|---|
| App icon ✅ | It has none; the Dock and About box look broken | S |
| Launch at login | Every menu-bar app has it (`SMAppService`) | S |
| First-run onboarding | Permissions must be explained or the app looks dead | M |
| Permission status screen | One place showing what's granted and what isn't | S |
| Graceful no-Spotify state | Right now it says "Open Spotify" forever | S |
| Multi-display handling | Panel currently follows the pointer's screen; needs testing | M |
| Notchless Mac support | Fallback strip exists but is untested | M |
| Crash-free release build | No fatalErrors on paths a user can reach | M |
| Signing + notarization | Otherwise Gatekeeper blocks it | M + $99/yr |
| DMG with a drag-to-Applications window | Standard Mac install | S |
| README with screenshots | People decide in 10 seconds | S |
| Privacy statement | Given the permissions it asks for, this matters | S |

### High value, clearly worth doing

| Item | Effort |
|---|---|
| Flexible widget layout (§2) ✅ | L |
| Customizable sizes (§3) ✅ | M |
| Settings redesign (§4) ✅ | M |
| Keyboard shortcut to open the panel (no hover) ✅ | S |
| Pin panel open (click to keep it) | S |
| Battery widget with time remaining | S |
| Weather widget (needs network — or read Apple's local cache) | M |
| Now-playing for any app via MediaRemote, not just Spotify/Music | L, and restricted on recent macOS |
| Clipboard history widget ✅ | M |
| Screen recording / screenshot shortcuts | S |
| Focus mode toggle | S |
| Per-app volume | L |
| Custom widget order per display | M |

### Nice to have

| Item | Effort |
|---|---|
| Themes you can edit and save yourself | M |
| Import/export settings as a file | S |
| Sound effects on expand/collapse | S |
| ~~Haptic feedback on trackpad~~ — done | S |
| Animated album art background | M |
| ~~Lyrics~~ — done, opt-in (lrclib.net) | L |
| Menu-bar hiding, like Bartender | L |
| Multiple resting-bar styles | M |
| Widget marketplace / plugin API | XL |

### Claude Code specific — this is the differentiator

Nothing else on the market does this. Worth leaning into:

| Item | Effort |
|---|---|
| Show which project each approval came from, with an icon | S |
| Approve with a keyboard shortcut while the panel is open | S |
| Session list: what Claude is doing right now, per project | M |
| Approval history: what you allowed today | M |
| Per-tool rules: "always allow Read in this project" | M |
| Live token/cost counter per session | M |

---

## 7. Release engineering

| Step | Notes |
|---|---|
| Apple Developer account | $99/yr. Required for notarization |
| Developer ID signing | Replaces ad-hoc; also stops permissions resetting each build |
| Notarization + stapling | `notarytool submit --wait`, then `stapler staple` |
| Hardened runtime | Required for notarization. Needs entitlements for Apple Events, camera, calendar |
| Sparkle or manual updates | Sparkle phones home for a feed — conflicts with "no network". Manual downloads are the honest alternative |
| Versioning | `CFBundleShortVersionString` is still 0.1.0 |
| Homebrew cask | The usual way Mac utilities are distributed |
| Licence | MIT if open source; otherwise a plain EULA |
| Open source or not | Changes everything about trust and support. Decide early |

**Note on hardened runtime:** it will likely break the two private-API features (display
brightness, keyboard backlight) and possibly the Accessibility read. Those need testing
under a hardened build *before* you promise them in a feature list.

---

## 8. Suggested order

1. **Foundations** — icon, launch at login, permission screen, no-Spotify state, version
2. **The layout work** — flex widgets, sizes, settings rebuild (the three things you asked for)
3. **Hardening** — multi-display, notchless, hardened runtime, no crashes
4. **Distribution** — Developer ID, notarize, DMG, README, privacy statement
5. **Then differentiate** — the Claude Code features nobody else has

---

## 9. Decisions I need from you

1. Which settings shape — A, B or C?
2. Artwork: keep, toggle, or local-only?
3. Open source, or closed?
4. Are you buying an Apple Developer account? It decides whether this is shareable
5. Auto-update: none, or Sparkle with its feed check?
6. Widget wishlist — which from §6 actually matter to you?
7. Minimum macOS: 14 (current) or 26-only (simpler, Liquid Glass everywhere)?
