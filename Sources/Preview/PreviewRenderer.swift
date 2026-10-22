import AppKit
import EventKit

/// Renders the panel to PNGs so layout can be checked without a screen recording.
/// Liquid Glass is a live effect and cannot be captured offscreen, so the slab is
/// filled with a flat stand-in here — geometry and content are what this verifies.
enum PreviewRenderer {
    static func render(to directory: String) {
        GlassCardView.usesLiveGlass = false

        let notchWidth: CGFloat = 179
        let notchHeight: CGFloat = 32

        let track = TrackInfo(
            name: "Everything In Its Right Place",
            artist: "Radiohead",
            isPlaying: true,
            artworkURL: nil,
            sourceName: "Spotify",
            sourceBundleIdentifier: "com.spotify.client",
            position: 74,
            duration: 251,
            volume: 65,
            isShuffling: true
        )

        write(named: "expanded-media", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.present(.expanded, animated: false)
        }

        write(named: "expanded-permission", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.setPendingCount(2)
            view.showPermission(
                PermissionRequest(
                    toolName: "Bash",
                    detail: "rm -rf build && swift build -c release",
                    cwd: "/Users/you/Coding/Notch-Hover/NotchHover",
                    responder: { _ in }
                ),
                queued: 1
            )
            view.present(.expanded, animated: false)
        }

        write(named: "expanded-app", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            let shortcut = AppShortcutStore.shortcuts().first
            guard let shortcut else { return }
            view.showApp(AppDetails(
                shortcut: shortcut,
                statusText: "2 sessions active",
                lines: [
                    AppDetailLine(label: "Desktop", value: "Running"),
                    AppDetailLine(label: "Code sessions", value: "2 running"),
                    AppDetailLine(label: "Project", value: "NotchHover"),
                    AppDetailLine(label: "Approvals", value: "Ready")
                ]
            ))
            view.present(.expanded, animated: false)
        }

        for theme in Theme.all {
            ThemeStore.override = theme
            write(named: "theme-\(theme.id)", directory: directory) { view in
                view.renderNowPlaying(.track(track))
                view.selectTabForPreview(.home)
            }
        }
        ThemeStore.override = nil

        let now = Date()
        NotesStore.shared.loadSample([
            Note(id: UUID(), text: "Ask about the Q3 hardware budget", created: now, updated: now.addingTimeInterval(-120), isPinned: true),
            Note(id: UUID(), text: "Flight BA 117 — gate closes 18:40", created: now, updated: now.addingTimeInterval(-3600), isPinned: false),
            Note(id: UUID(), text: "brew install --cask iina", created: now, updated: now.addingTimeInterval(-86400), isPinned: false)
        ])
        func sample(_ kind: ClipboardItem.Kind, _ text: String?, _ app: String, _ ago: TimeInterval, pinned: Bool = false, files: [String]? = nil) -> ClipboardItem {
            ClipboardItem(id: UUID(), kind: kind, text: text, filePaths: files, imageFileName: nil, imageWidth: nil, imageHeight: nil,
                          sourceBundleIdentifier: nil, sourceName: app, copied: now.addingTimeInterval(-ago), isPinned: pinned, copyCount: 1)
        }
        let work = ClipboardBoard(id: UUID(), name: "Work", color: "orange")
        let code = ClipboardBoard(id: UUID(), name: "Code", color: "green")
        let links = ClipboardBoard(id: UUID(), name: "Links", color: "purple")
        var rebase = sample(.text, "git rebase -i HEAD~3", "Terminal", 30, pinned: true)
        rebase.sourceBundleIdentifier = "com.apple.Terminal"
        rebase.boardIDs = [code.id]
        var docs = sample(.link, "https://developer.apple.com/documentation/appkit/nspanel", "Safari", 240)
        docs.boardIDs = [links.id, work.id]
        ClipboardHistory.shared.loadSample([
            rebase,
            docs,
            sample(.text, "Thanks — that works for me, let's lock in Thursday.", "Mail", 900),
            sample(.file, nil, "Finder", 3000, files: ["/Users/you/Desktop/Invoice-0421.pdf"]),
            sample(.text, "#D9622F", "Figma", 7200)
        ], boards: [work, code, links])

        write(named: "expanded-clipboard", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.clipboard)
        }

        write(named: "expanded-notes", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.notes)
        }

        write(named: "expanded-shelf", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            FileTray.shared.add([
                URL(fileURLWithPath: "/System/Applications/Notes.app"),
                URL(fileURLWithPath: "/etc/hosts")
            ])
            view.selectTabForPreview(.shelf)
        }

        write(named: "expanded-board", directory: directory) { view in
            view.selectTabForPreview(.board)
        }

        write(named: "expanded-mirror", directory: directory) { view in
            view.selectTabForPreview(.mirror)
        }

        // The peek: what resting on the notch brings up before a click opens the panel.
        write(named: "peek-playing", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.present(.idle, animated: false)
            view.showPeekForPreview()
        }

        write(named: "peek-call", directory: directory) { view in
            view.showPeekForPreview(.call(CallState(provider: .zoom, appName: "Zoom", bundleIdentifier: "us.zoom.xos",
                                                    title: "Design review", isMuted: true, isCameraOff: false,
                                                    startedAt: Date().addingTimeInterval(-754))))
        }

        // A screenshot popping from the notch, and the Screenshots view.
        let shots = ["Mac Blue.heic", "Radial Sky Blue.heic", "Mac Pink.heic"]
            .map { URL(fileURLWithPath: "/System/Library/Desktop Pictures/\($0)") }
        write(named: "peek-screenshot", directory: directory) { view in
            view.showPeekForPreview(.screenshot(shots[0]))
        }
        ScreenshotStore.shared.loadForPreview(shots)
        write(named: "expanded-screenshots", directory: directory) { view in
            view.selectTabForPreview(.screenshots)
        }

        write(named: "peek-meeting", directory: directory) { view in
            view.renderNowPlaying(.message("Nothing playing"))
            view.showPeekForPreview(.meeting(title: "Design review", service: "Zoom", start: Date().addingTimeInterval(232)))
        }

        write(named: "peek-glance", directory: directory) { view in
            view.renderNowPlaying(.message("Nothing playing"))
            view.showPeekForPreview(.glance(next: PeekEvent(title: "Gym", start: Date().addingTimeInterval(3 * 3600),
                                                            color: NSColor(srgbRed: 1, green: 0.62, blue: 0.04, alpha: 1)), hasCalendar: true))
        }

        // Single cards, drawn on the panel colour the way they sit on Home.
        ClaudeSessionMonitor.shared.publishForPreview()
        writeCard(DevicesPaneView(), named: "card-batteries", directory: directory)
        writeCard(ClaudePaneView(), named: "card-claude", directory: directory)

        // The schedule, with a made-up day: a call starting soon, an afternoon 1:1, a
        // birthday, and something tomorrow for the strip's dot.
        let store = EKEventStore()
        func event(_ title: String, _ start: TimeInterval, _ minutes: Double, allDay: Bool = false, notes: String? = nil) -> EKEvent {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = Date().addingTimeInterval(start)
            event.endDate = event.startDate.addingTimeInterval(minutes * 60)
            event.isAllDay = allDay
            event.notes = notes
            return event
        }
        CalendarPaneView.previewEvents = [
            event("Design review", 4 * 60, 45, notes: "Join: https://us02web.zoom.us/j/81234567890"),
            event("1:1 with Sam", 2 * 3600, 30),
            event("Mum's birthday", -3600, 60 * 23, allDay: true),
            event("Dentist", 26 * 3600, 60)
        ]
        let calendarCard = CalendarPaneView()
        calendarCard.reload()
        writeCard(calendarCard, named: "card-calendar", directory: directory, size: NSSize(width: 250, height: 150))
        write(named: "expanded-calendar", directory: directory) { view in
            view.selectTabForPreview(.calendar)
        }
        CalendarPaneView.previewEvents = nil

        // The ⌘K list, with a few built-ins and two of "yours".
        func sample(_ id: String, _ title: String, _ group: String, _ symbol: String, _ key: KeyCombo?, panel: String? = nil) -> NotchAction {
            NotchAction(id: id, title: title, group: group, symbol: symbol, defaultHotkey: key, panelKeys: panel,
                        isCustom: false, argumentPrompt: nil, run: { _ in })
        }
        CustomActionStore.shared.loadSample([
            CustomAction(id: UUID(), name: "Search GitHub", symbol: "magnifyingglass", steps: [.openURL("https://github.com/search?q={query}")]),
            CustomAction(id: UUID(), name: "Start work", symbol: "briefcase.fill", steps: [.openApp("/Applications/Xcode.app"), .runShortcut("Work Focus")])
        ])
        ActionRegistry.shared.register([
            sample("open.home", "Open Home", "Panel", "house.fill", .controlOption(4, "H"), panel: "⌘1"),
            sample("open.clipboard", "Open Clipboard", "Panel", "doc.on.clipboard.fill", .controlOption(9, "V"), panel: "⌘4"),
            sample("media.playPause", "Play or pause", "Media", "playpause.fill", nil, panel: "Space"),
            sample("call.mute", "Mute the call, or the mic", "Calls", "mic.slash.fill", .controlOption(46, "M"), panel: "⌘⇧M"),
            sample("screenshot.area", "Screenshot an area", "Screenshots", "crop", .controlOption(21, "4"))
        ])
        write(named: "expanded-quicksettings", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.home)
            view.setQuickSettingsVisible(true)
        }
        write(named: "expanded-shortcuts", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.home)
            view.showShortcutsForPreview()
        }

        // The shelf with real pictures on it, and the drop zones a drag brings up.
        let pictures = ["Mac Blue.heic", "Mac Pink.heic", "Radial Sky Blue.heic"]
            .map { URL(fileURLWithPath: "/System/Library/Desktop Pictures/\($0)") }
        FileTray.shared.clear()
        FileTray.shared.add(pictures + [URL(fileURLWithPath: "/etc/hosts")])
        write(named: "expanded-tray", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.tray)
            // Quick Look makes thumbnails in the background.
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        }
        write(named: "expanded-dropzones", directory: directory) { view in
            view.showDropZonesForPreview(Array(pictures.prefix(2)), hot: .action(.toJPEG))
        }

        write(named: "expanded-timer", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.timer)
            view.updateTimer(remaining: 305)
        }

        write(named: "expanded-system", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.system)
        }

        write(named: "idle", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.present(.idle, animated: false)
        }

        // The resting bar holding a system event: it sizes itself to what it has to say.
        write(named: "idle-notification", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.present(.idle, animated: false)
            view.showActivity(.notification(app: "Messages", title: "Are we still on for six?"))
        }

        write(named: "idle-volume", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.present(.idle, animated: false)
            view.showActivity(.volume(level: 0.4, isMuted: false))
        }

        // Something playing that no player we can talk to owns — a video in a browser.
        // All we have is the app it is coming from, so that is what is shown.
        let external = AudioSource(name: "Safari", bundleIdentifier: "com.apple.Safari", processIdentifier: 0)

        // An app with the microphone that's also making sound: dictation, a voice note.
        let recorder = AudioSource(name: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop", processIdentifier: 0, isRecording: true)
        write(named: "peek-recording", directory: directory) { view in
            view.isAudioPlaying = true
            view.renderNowPlaying(.external(recorder))
            view.present(.idle, animated: false)
            view.showPeekForPreview()
        }
        write(named: "idle-recording", directory: directory) { view in
            view.isAudioPlaying = true
            view.renderNowPlaying(.external(recorder))
            view.present(.idle, animated: false)
        }

        write(named: "idle-audio", directory: directory) { view in
            view.isAudioPlaying = true
            view.renderNowPlaying(.external(external))
            view.present(.idle, animated: false)
        }

        // A page playing in a browser: shown as the site, with the favicon the browser
        // already had on disk. The icon here is drawn rather than borrowed, so the
        // preview looks the same on every machine.
        let page = BrowserPage(title: "Ambient mix — three hours", host: "www.youtube.com", iconData: swatch())
        let browser = AudioSource(name: "Safari", bundleIdentifier: "com.apple.Safari", processIdentifier: 0, page: page)

        write(named: "idle-page", directory: directory) { view in
            view.isAudioPlaying = true
            view.renderNowPlaying(.external(browser))
            view.present(.idle, animated: false)
        }

        // Synced lyrics: the line being sung, in the peek, the Now Playing tab and the
        // Home card, where it stands in for the artist.
        LyricsService.shared.showLineForPreview("Yesterday I woke up sucking a lemon")
        write(named: "peek-lyrics", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.present(.idle, animated: false)
            view.showPeekForPreview()
        }
        write(named: "expanded-lyrics", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.nowPlaying)
        }
        write(named: "expanded-lyrics-home", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.home)
        }
        LyricsService.shared.showLineForPreview(nil)

        writeLockScreen(track: track, directory: directory)

        // Apple Music's next tracks beside the player.
        MusicQueue.shared.publishForPreview([
            .init(index: 4, title: "Kid A", artist: "Radiohead"),
            .init(index: 5, title: "The National Anthem", artist: "Radiohead"),
            .init(index: 6, title: "How to Disappear Completely", artist: "Radiohead")
        ])
        write(named: "expanded-upnext", directory: directory) { view in
            view.renderNowPlaying(.track(track))
            view.selectTabForPreview(.nowPlaying)
        }
        MusicQueue.shared.publishForPreview([])

        write(named: "expanded-page", directory: directory) { view in
            view.isAudioPlaying = true
            view.renderNowPlaying(.external(browser))
            view.selectTabForPreview(.nowPlaying)
        }

        write(named: "expanded-external", directory: directory) { view in
            view.isAudioPlaying = true
            view.renderNowPlaying(.external(external))
            view.selectTabForPreview(.nowPlaying)
        }
    }

    /// Stand-in favicon bytes for the previews: a plain rounded square, so nothing
    /// depends on what happens to be open on the machine rendering them.
    private static func swatch() -> Data? {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.85, green: 0.16, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 14, yRadius: 14).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// The lock screen's music card over a stand-in lock screen.
    private static func writeLockScreen(track: TrackInfo, directory: String) {
        let (card, peek) = LockScreenMusic.makeCard(notchWidth: 179, bandHeight: 32)
        let size = card.frame.size
        peek.show(.playing(PeekTrack(track: track, icon: NSWorkspace.shared.icon(forFile: "/Applications/Spotify.app"),
                                     tint: NSColor(srgbRed: 0.3, green: 0.85, blue: 0.45, alpha: 1), asOf: Date())))
        card.layoutSubtreeIfNeeded()
        peek.layoutSubtreeIfNeeded()

        let margin: CGFloat = 40
        let canvas = NSSize(width: size.width + margin * 2, height: size.height + margin * 3)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.20, alpha: 1),
                            NSColor(calibratedRed: 0.30, green: 0.22, blue: 0.36, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: canvas), angle: 70)
        let origin = CGPoint(x: margin, y: canvas.height - size.height)
        if let fill = (card as? LockScreenCardView)?.shape.fillColor { NSColor(cgColor: fill)?.setFill() }
        NSBezierPath(cgPath: NotchShape.path(in: CGRect(origin: origin, size: size), bottomRadius: min(22, NotchShape.bottomRadius))).fill()
        if let context = NSGraphicsContext.current {
            NSGraphicsContext.saveGraphicsState()
            context.cgContext.translateBy(x: origin.x, y: origin.y)
            peek.displayIgnoringOpacity(peek.bounds, in: context)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: origin.x + (size.width - 179) / 2, y: canvas.height - 32, width: 179, height: 32)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("lockscreen-music.png"))
        print("wrote lockscreen-music")
    }

    private static func writeCard(_ card: NSView, named name: String, directory: String, size: NSSize = NSSize(width: 260, height: 120)) {
        card.frame = NSRect(origin: .zero, size: size)
        card.layoutSubtreeIfNeeded()
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 14, yRadius: 14).fill()
        if let context = NSGraphicsContext.current { card.displayIgnoringOpacity(card.bounds, in: context) }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        print("wrote \(name)")
    }

    /// A thumbnail of the panel in a given theme, for the settings window's live preview.
    static func snapshot(theme: Theme, width: CGFloat, presentation: NotchContentView.Presentation = .expanded, margin: CGFloat = 12) -> NSImage? {
        let previousOverride = ThemeStore.override
        let previousGlass = GlassCardView.usesLiveGlass
        ThemeStore.override = theme
        GlassCardView.usesLiveGlass = false
        defer {
            ThemeStore.override = previousOverride
            GlassCardView.usesLiveGlass = previousGlass
        }

        let view = NotchContentView(notchWidth: 179, notchHeight: 32)
        view.renderNowPlaying(.track(TrackInfo(
            name: "Everything In Its Right Place",
            artist: "Radiohead",
            isPlaying: true,
            artworkURL: nil,
            sourceName: "Spotify",
            sourceBundleIdentifier: "com.spotify.client",
            position: 74,
            duration: 251,
            volume: 65,
            isShuffling: true
        )))
        switch presentation {
        case .peek: view.present(.idle, animated: false); view.showPeekForPreview()
        case .idle: view.present(.idle, animated: false)
        default: view.selectTabForPreview(.home)
        }
        view.layoutSubtreeIfNeeded()

        var full = render(view: view, margin: margin)
        // The notch hangs from the top of the screen: a wide margin is desktop at the
        // sides and below, never above.
        if margin > 12 {
            let cropped = NSImage(size: NSSize(width: full.size.width, height: full.size.height - margin))
            cropped.lockFocus()
            full.draw(at: .zero, from: NSRect(x: 0, y: 0, width: full.size.width, height: full.size.height - margin), operation: .copy, fraction: 1)
            cropped.unlockFocus()
            full = cropped
        }
        let scale = width / full.size.width
        let target = NSSize(width: width, height: (full.size.height * scale).rounded())
        let scaled = NSImage(size: target)
        scaled.lockFocus()
        full.draw(in: NSRect(origin: .zero, size: target))
        scaled.unlockFocus()
        return scaled
    }

    private static func write(named name: String, directory: String, configure: (NotchContentView) -> Void) {
        let view = NotchContentView(notchWidth: 179, notchHeight: 32)
        configure(view)
        view.layoutSubtreeIfNeeded()

        let image = render(view: view, margin: 30)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }

        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url)
            print("wrote \(url.path)")
        } catch {
            // Silently claiming success sent me chasing a file that was never written.
            print("failed \(url.path): \(error.localizedDescription)")
        }
    }

    private static func render(view: NotchContentView, margin: CGFloat) -> NSImage {
        let canvas = NSSize(width: view.bounds.width + margin * 2, height: view.bounds.height + margin * 2)
        let image = NSImage(size: canvas)

        image.lockFocus()
        // Stand-in desktop so the slab's edges are visible.
        NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.42, alpha: 1)
        ])?.draw(in: NSRect(origin: .zero, size: canvas), angle: 70)

        let card = view.card
        let cardRect = CGRect(
            x: card.frame.minX + margin,
            y: card.frame.minY + margin,
            width: card.frame.width,
            height: card.frame.height
        )
        let shapeRect = card.shapeRect.offsetBy(dx: cardRect.minX, dy: cardRect.minY)
        let path = NSBezierPath(cgPath: NotchShape.path(in: shapeRect, bottomRadius: card.bottomRadius))
        // Glass cannot be captured offscreen, so it gets a flat stand-in.
        switch ThemeStore.active.surface {
        case .solid(let color): color.setFill()
        case .glass: NSColor.black.withAlphaComponent(0.32).setFill()
        }
        path.fill()

        // Draw the tree straight into the canvas: the cache rep comes back opaque,
        // which would paint a white block over the slab.
        let content = card.contentContainer
        if let context = NSGraphicsContext.current {
            NSGraphicsContext.saveGraphicsState()
            // Clip exactly as the live mask does, so clipped content shows up here.
            path.addClip()
            context.cgContext.translateBy(x: cardRect.minX + NotchShape.topFlare, y: cardRect.minY)
            content.displayIgnoringOpacity(content.bounds, in: context)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Mark where the physical notch sits, since it is invisible in a render.
        let notch = NSRect(
            x: margin + (view.bounds.width - view.notchSpan) / 2,
            y: margin + view.bounds.height - 32,
            width: view.notchSpan,
            height: 32
        )
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: notch).fill()

        image.unlockFocus()
        return image
    }
}
