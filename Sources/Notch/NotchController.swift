import AppKit

/// Owns the notch on every display: the resting bar, hover expansion, what the detail
/// pane is showing, and the queue of Claude Code permission requests waiting on an answer.
///
/// Each display has its own panel (`NotchDisplay`). What everyone should see — now
/// playing, activities, the timer, the approvals badge — is broadcast to all of them.
/// Anything interactive goes to the *active* display: the one that is open, or was
/// last opened.
final class NotchController {
    private enum Constants {
        /// Grace period so a pointer that clips the edge does not dismiss the panel.
        static let hideDelay: TimeInterval = 0.18
        static let openInterval: TimeInterval = 1
        static let restingInterval: TimeInterval = 2.5
        /// Slightly under the hook's own timeout, so the fallback is ours to control.
        static let requestTimeout: TimeInterval = 50
    }

    private let mediaController: MediaControlling
    private let poller: NowPlayingPoller
    /// Music on the lock screen, for anyone who switches it on.
    private let lockScreen = LockScreenMusic()
    private let permissionBridge: PermissionBridge
    private let activityCenter: ActivityCenter
    private let countdown: CountdownTimer
    private let audioActivity = AudioActivityMonitor()

    private var displays: [CGDirectDisplayID: NotchDisplay] = [:]
    /// The display that is open, or was last opened.
    private var active: NotchDisplay?

    /// The active display's parts. Interactive paths — hover, typing, approvals — only
    /// ever concern the display the pointer is on.
    private var panel: NotchPanel? { active?.panel }
    private var contentView: NotchContentView? { active?.content }
    private var geometry: NotchGeometry? { active?.geometry }

    /// The last thing shown, replayed into displays built later — one plugged in, or
    /// rebuilt for a new theme — so they start current instead of on "Loading…".
    private var lastState: NowPlayingState = .message("Nothing playing")
    private var mouseMonitors: [Any] = []
    /// Swipes over a notch that isn't open, and over the open panel. Two recognisers,
    /// because a gesture can start in one place and should never carry into the other.
    private let notchSwipes = SwipeRecognizer()
    private let panelSwipes = SwipeRecognizer()
    /// Set by a deliberate close — a swipe, Esc, a shortcut — so the pointer still
    /// resting on the notch doesn't open it again straight away. Cleared once the
    /// pointer leaves the notch.
    private var hoverSuppressedUntilExit = false

    /// The display showing a peek, if any. Like the open panel there is only ever one.
    private var peeking: NotchDisplay?
    /// Hovering has to rest on the notch for a moment before anything happens, so that
    /// passing it on the way to the menu bar doesn't open it.
    private var dwellWorkItem: DispatchWorkItem?
    private var meetingTimer: Timer?
    /// Calls already announced, so each one pops the notch once.
    private var announcedMeetings: Set<String> = []
    private var unpeekWorkItem: DispatchWorkItem?

    /// What resting on the notch does.
    /// defaults write com.notchhover.NotchHover HoverAction -string peek|open
    private enum HoverAction: String {
        case peek
        case open

        static var current: HoverAction {
            UserDefaults.standard.string(forKey: "HoverAction").flatMap(HoverAction.init(rawValue:)) ?? .peek
        }
    }

    /// defaults write com.notchhover.NotchHover HoverDelay -float 0.3
    private var hoverDelay: TimeInterval {
        let stored = UserDefaults.standard.object(forKey: "HoverDelay") as? Double ?? 0.3
        return min(1.5, max(0, stored))
    }
    private var hideWorkItem: DispatchWorkItem?
    private var isExpanded = false
    private var isPlaying = false
    private var hasTrack = false
    /// Something is playing that the poller cannot name — a video in a browser, a call.
    private var isAudioPlaying = false
    /// What the poller last reported, so a new track can be told from another tick and
    /// so an audio change can re-decide what to show without waiting for the next one.
    private var lastTrack: TrackInfo?
    private var lastTrackKey: String?
    private var lastShownSummary: String?
    /// Who is making the sound when no player we can talk to owns it.
    private var audioSource: AudioSource?
    private var currentSourceBundleIdentifier: String?
    private var selectedShortcut: AppShortcut?

    private var activityWorkItem: DispatchWorkItem?
    private var pendingRequests: [PermissionRequest] = []
    private var timeouts: [UUID: DispatchWorkItem] = [:]

    /// When the resting bar hugging the notch is shown.
    /// defaults write com.notchhover.NotchHover RestingBar -string always|playing|never
    private enum RestingBarMode: String {
        case playing
        case always
        case never

        static var current: RestingBarMode {
            UserDefaults.standard.string(forKey: "RestingBar")
                .flatMap(RestingBarMode.init(rawValue:)) ?? .playing
        }
    }

    private var wantsRestingBar: Bool {
        switch RestingBarMode.current {
        // Audio the poller cannot name still counts: a video playing is exactly when
        // the bar should be alive.
        case .playing: return isPlaying || isAudioPlaying
        case .always: return hasTrack || isAudioPlaying
        case .never: return false
        }
    }


    /// While requests are waiting the panel stays put — an approval prompt that
    /// vanishes when the pointer drifts would be worse than useless.
    private var isPinned: Bool { pendingRequests.isEmpty == false }

    /// Typing into a note or the clipboard search keeps the panel open even if the
    /// pointer wanders off it. Escape, or clicking another app, closes it.
    private var isEditingText: Bool {
        guard let panel, panel.isKeyWindow else { return false }
        return panel.firstResponder is NSTextView
    }

    /// Opened from the keyboard: it stays open until the keyboard closes it, or the
    /// pointer comes to it and the usual hover rules take over. Otherwise the slightest
    /// nudge of the mouse, wherever it was, closed a panel you were typing at.
    private var openedByKeyboard = false

    /// Reasons the open panel stays open whatever the pointer does.
    private var isHeldOpen: Bool {
        isPinned || isEditingText || openedByKeyboard || contentView?.isShowingMenu == true
    }

    init(
        mediaController: MediaControlling,
        poller: NowPlayingPoller,
        permissionBridge: PermissionBridge,
        activityCenter: ActivityCenter,
        countdown: CountdownTimer
    ) {
        self.mediaController = mediaController
        self.poller = poller
        self.permissionBridge = permissionBridge
        self.activityCenter = activityCenter
        self.countdown = countdown
    }

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.handlePointerMoved()
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            mouseMonitors.append(global)
        }
        // A file drag is told apart from any other by the drag pasteboard changing after
        // the button went down — the way Boring Notch and NotchDrop do it.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp], handler: { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDown {
                self.dragPasteboardCount = NSPasteboard(name: .drag).changeCount
            } else {
                self.dragPasteboardCount = nil
                // A drag let go somewhere else leaves no zones behind.
                self.broadcast { $0.setDropZonesVisible(false, for: []) }
            }
        }) {
            mouseMonitors.append(global)
        }
        // The global monitor goes quiet while the pointer is over our own panel.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in
            handler(event)
            return event
        }) {
            mouseMonitors.append(local)
        }

        // Two-finger swipes. Over a notch that isn't open, the panel ignores the mouse —
        // the resting bar must never block the menu bar — so those arrive through a
        // global monitor, which can watch but not swallow. Over the open panel they
        // arrive locally, and a swipe that was ours is kept from scrolling anything.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.handleNotchScroll(event)
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self, self.handlePanelScroll(event) else { return event }
            return nil
        }) {
            mouseMonitors.append(local)
        }

        poller.addObserver { [weak self] result in
            self?.apply(result)
        }

        lockScreen.onPlayPause = { [weak self] in self?.perform(.playPause) }
        lockScreen.onNext = { [weak self] in self?.perform(.nextTrack) }
        lockScreen.onPrevious = { [weak self] in self?.perform(.previousTrack) }
        lockScreen.start()

        activityCenter.addObserver { [weak self] activity in
            self?.present(activity)
        }

        NotificationWatcher.shared.onCapture = { [weak self] _ in
            self?.broadcast { $0.refreshNotifications() }
        }

        countdown.onTick = { [weak self] remaining in
            self?.broadcast { $0.updateTimer(remaining: remaining) }
        }
        countdown.onFinish = { [weak self] in
            self?.activityCenter.post(.timer(remaining: 0))
        }

        NotificationCenter.default.addObserver(
            forName: .notchHoverSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyChangedSettings()
        }

        // A display plugged in or out, or a resolution change, moves the notches.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncDisplays()
        }

        // Clicking into another app takes keyboard focus away; that is the cue to close.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, (notification.object as? NSWindow) === self.panel, self.isExpanded else { return }
            self.openedByKeyboard = false
            self.scheduleHide()
        }

        permissionBridge.onRequest = { [weak self] request in
            self?.enqueue(request)
        }
        permissionBridge.start()

        audioActivity.onChange = { [weak self] active in
            self?.applyAudioActivity(active)
        }
        audioActivity.start()

        // Calls with a link, two minutes out: the notch pops once to say so, and resting
        // on it then brings up the peek with its Join button. Only when the calendar has
        // already been allowed — this never asks.
        meetingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.announceUpcomingMeeting()
        }
    }

    private func announceUpcomingMeeting() {
        guard CalendarService.shared.isAuthorized,
              let (event, _) = CalendarService.shared.joinableMeeting(lead: 2 * 60),
              event.startDate.timeIntervalSinceNow > -60 else { return }
        let key = (event.calendarItemIdentifier) + "\(event.startDate.timeIntervalSince1970)"
        guard announcedMeetings.insert(key).inserted else { return }
        let title = "\(event.title ?? "Meeting") · \(NotchContentView.relative(event.startDate))"
        activityCenter.post(.meeting(title: title))
    }

    /// Anything playing through the speakers wakes the bar, whether or not a player
    /// we can talk to owns it.
    private func applyAudioActivity(_ active: Bool) {
        guard isAudioPlaying != active else { return }
        isAudioPlaying = active
        // A video starting is worth a panel of its own; waiting for the next poller
        // tick would leave the bar a couple of seconds behind the sound.
        audioSource = active ? AudioSourceProbe.current() : nil
        if let audioSource {
            Log.system.notice("Audio source: \(audioSource.name, privacy: .public)")
        }
        refreshBrowserPage()
        if displays.isEmpty, wantsRestingBar { syncDisplays() }
        broadcast { $0.isAudioPlaying = active }
        // The bar is showing whatever is making the sound, so it has to be told what
        // that is now rather than at the next poller tick — the poller only knows
        // about Spotify and Music.
        if isPlaying == false { render(nowPlayingState(for: lastTrack)) }
        settleToRestingState()
        // Sound starting is the event; sound stopping takes the bar away by itself.
        if active, isPlaying == false { breathe() }
    }

    /// Asks which page a browser is playing. The read is file work and a few megabytes
    /// of JSON, so it happens off the main thread and only lands here when the answer
    /// changes — at which point the bar is told again what it is showing.
    private func refreshBrowserPage() {
        guard let source = audioSource, BrowserPageReader.handles(source.bundleIdentifier) else { return }

        BrowserPageReader.shared.refresh(for: source.bundleIdentifier, current: source.page) { [weak self] page in
            guard let self, self.audioSource?.bundleIdentifier == source.bundleIdentifier else { return }
            self.audioSource?.page = page
            if let page {
                Log.system.notice("Playing page: \(page.shortHost, privacy: .public) — icon: \(page.iconData != nil, privacy: .public)")
            }
            guard self.isPlaying == false else { return }
            self.render(self.nowPlayingState(for: self.lastTrack))
        }
    }

    /// What the panel shows, in the order that matters: a track that is actually
    /// playing, then whatever else is making sound, then a track sitting paused, then
    /// nothing. Ranking any track above live audio was wrong — Spotify left paused in
    /// the background kept its artwork on the bar while a video played in a browser.
    private func nowPlayingState(for track: TrackInfo?, fallback: String = "Nothing playing") -> NowPlayingState {
        let state: NowPlayingState
        if let track, track.isPlaying {
            state = .track(track)
        } else if isAudioPlaying, let audioSource {
            state = .external(audioSource)
        } else if let track {
            state = .track(track)
        } else {
            state = .message(fallback)
        }

        // Logged on change only: which of the three the bar settled on is the first
        // thing worth knowing when it shows the wrong thing.
        let summary: String
        switch state {
        case .track(let track): summary = "track \(track.name)\(track.isPlaying ? "" : " (paused)")"
        case .external(let source): summary = "external \(source.displayName) [\(source.detail)]"
        case .message(let message): summary = "message \(message)"
        }
        if summary != lastShownSummary {
            lastShownSummary = summary
            Log.ui.notice("Bar showing: \(summary, privacy: .public)")
        }

        return state
    }

    /// A breath is a reaction, not a state: the bar takes a couple and is still again.
    /// Only worth it while the bar is the thing on screen.
    private func breathe(cycles: Int = NotchBreath.cycles) {
        // Each display only breathes while it is resting, so the open one sits it out.
        broadcast { $0.breathe(cycles: cycles) }
    }

    /// Shows the same thing on every display, and remembers it for displays to come.
    private func render(_ state: NowPlayingState) {
        lastState = state
        broadcast { $0.renderNowPlaying(state) }

        if case .track(let track) = state { MusicQueue.shared.refresh(for: track) } else { MusicQueue.shared.refresh(for: nil) }

        // The meter follows whichever app is making the sound.
        switch state {
        case .track(let track) where track.isPlaying: AudioLevels.shared.follow(track.sourceBundleIdentifier)
        case .external(let source): AudioLevels.shared.follow(source.bundleIdentifier)
        default: AudioLevels.shared.follow(nil)
        }
    }

    private func broadcast(_ body: (NotchContentView) -> Void) {
        displays.values.forEach { body($0.content) }
    }

    func stop() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        hideWorkItem?.cancel()
        // Anything still waiting goes back to Claude Code's own prompt.
        pendingRequests.forEach { $0.respond(.ask) }
        pendingRequests.removeAll()
        permissionBridge.stop()
        audioActivity.stop()
        meetingTimer?.invalidate()
        displays.values.forEach { $0.panel.orderOut(nil) }
    }

    // MARK: - Hover handling

    /// The drag pasteboard's count when the button went down; nil with the button up.
    private var dragPasteboardCount: Int?

    /// Files are being dragged right now, from somewhere else.
    private var isDraggingFiles: Bool {
        guard let count = dragPasteboardCount, NSEvent.pressedMouseButtons & 1 != 0 else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.changeCount != count
            && pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func handlePointerMoved() {
        let location = NSEvent.mouseLocation

        // Files dragged to a closed notch open it at once, on the drop zones: waiting out
        // the hover delay with a file in hand feels broken.
        if isExpanded == false, isDraggingFiles,
           let display = displays.values.first(where: { $0.geometry.hoverRect.insetBy(dx: -20, dy: -24).containsPointer(location) }) {
            let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            expand(display)
            display.content.setDropZonesVisible(true, for: urls)
            Haptics.tick()
            return
        }

        if isExpanded {
            guard let panel else { return }
            let liveArea = panel.frame.union(geometry?.hoverRect ?? .zero)
            if liveArea.containsPointer(location) {
                openedByKeyboard = false
                cancelScheduledHide()
            } else {
                scheduleHide()
            }
            return
        }

        // Every display has its own notch to hover. Displays are built lazily, so the
        // first hover on a new one builds it.
        if displays.isEmpty { syncDisplays() }
        let hovered = displays.values.first { $0.geometry.isPointerInHoverArea(location) }

        if hoverSuppressedUntilExit {
            if hovered == nil { hoverSuppressedUntilExit = false }
            return
        }

        // A peek stays while the pointer is on it or on the notch, and goes the moment it
        // leaves — after a breath of grace, so clipping its edge doesn't close it.
        if let peeking {
            if peekArea(of: peeking).containsPointer(location) {
                unpeekWorkItem?.cancel()
                unpeekWorkItem = nil
                // Once the pointer has been on a pop, it behaves like any peek.
                transientUntil = nil
            } else if let until = transientUntil, Date() < until {
                // A pop that came by itself stays its time, wherever the pointer is.
            } else {
                scheduleUnpeek()
            }
            return
        }

        guard let hovered else {
            dwellWorkItem?.cancel()
            dwellWorkItem = nil
            return
        }
        guard dwellWorkItem == nil else { return }

        let work = DispatchWorkItem { [weak self, weak hovered] in
            guard let self, let hovered else { return }
            self.dwellWorkItem = nil
            // Still there once the dwell is up? Passing through doesn't count.
            guard hovered.geometry.isPointerInHoverArea(NSEvent.mouseLocation), self.isExpanded == false else { return }
            switch HoverAction.current {
            case .peek: self.peek(hovered)
            case .open: self.expand(hovered)
            }
            Haptics.tick()
        }
        dwellWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: work)
    }

    // MARK: - Peek

    /// The small card that comes up while the pointer rests on the notch. It takes
    /// clicks — a click on it opens the full panel — so the window stops ignoring the
    /// mouse; outside the card the window is transparent and clicks pass through.
    private func peek(_ display: NotchDisplay) {
        if let current = peeking, current !== display { unpeek() }
        peeking = display
        display.panel.ignoresMouseEvents = false
        display.panel.orderFrontRegardless()
        display.content.present(.peek)
    }

    private func unpeek() {
        unpeekWorkItem?.cancel()
        unpeekWorkItem = nil
        transientUntil = nil
        guard peeking != nil else { return }
        peeking = nil
        settleToRestingState()
    }

    private func scheduleUnpeek() {
        guard unpeekWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let peeking = self.peeking else { return }
            self.unpeekWorkItem = nil
            guard self.peekArea(of: peeking).containsPointer(NSEvent.mouseLocation) == false else { return }
            self.unpeek()
        }
        unpeekWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// The peek card on screen, plus the notch it came out of.
    private func peekArea(of display: NotchDisplay) -> CGRect {
        let card = display.content.peekFrame.offsetBy(dx: display.panel.frame.minX, dy: display.panel.frame.minY)
        return card.union(display.geometry.hoverRect)
    }

    // MARK: - Gestures

    /// Swipes over a notch that isn't open: down opens it, and sideways over the resting
    /// bar skips the track that is playing.
    private func handleNotchScroll(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        // The notch, plus the resting bar's sides either side of it.
        guard let display = displays.values.first(where: {
            $0.geometry.hoverRect.insetBy(dx: -90, dy: 0).containsPointer(location)
        }), (isExpanded && display === active) == false else { return }

        switch notchSwipes.feed(event) {
        case .down?:
            hoverSuppressedUntilExit = false
            expand(display)
            Haptics.step()
        case .left? where isPlaying:
            perform(.nextTrack)
            Haptics.step()
        case .right? where isPlaying:
            perform(.previousTrack)
            Haptics.step()
        default:
            break
        }
    }

    /// Swipes over the open panel: up closes it, sideways moves between tabs. Returns
    /// whether the event was the gesture's, so it doesn't also scroll something.
    private func handlePanelScroll(_ event: NSEvent) -> Bool {
        // The peek takes the mouse, so swipes on it arrive here: down opens the panel,
        // up puts it away, sideways skips the track.
        if let peeking, event.window === peeking.panel {
            switch notchSwipes.feed(event) {
            case .down?:
                expand(peeking)
                Haptics.step()
            case .up?:
                hoverSuppressedUntilExit = true
                unpeek()
                Haptics.step()
            case .left? where isPlaying:
                perform(.nextTrack)
                Haptics.step()
            case .right? where isPlaying:
                perform(.previousTrack)
                Haptics.step()
            default:
                break
            }
            return true
        }

        guard isExpanded, let panel, event.window === panel else { return false }

        // Over a list that can scroll, an up-and-down movement is scrolling the list.
        let overList = isOverScrollableList(event, in: panel)
        let direction = panelSwipes.feed(event)

        switch direction {
        case .up? where overList == false:
            hoverSuppressedUntilExit = true
            dismiss()
            Haptics.step()
        case .left?:
            contentView?.selectAdjacentTab(by: 1)
            Haptics.tick()
        case .right?:
            contentView?.selectAdjacentTab(by: -1)
            Haptics.tick()
        default:
            break
        }

        // Nothing here scrolls sideways, and away from a list nothing scrolls at all, so
        // those events can be kept; over a list, vertical ones belong to the list.
        return overList == false || panelSwipes.hasFired
    }

    private func isOverScrollableList(_ event: NSEvent, in panel: NSPanel) -> Bool {
        guard let root = panel.contentView else { return false }
        let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        guard let scroll = root.hitTest(point)?.enclosingScrollView, let document = scroll.documentView else { return false }
        return document.frame.height > scroll.contentView.bounds.height + 1
    }

    private func scheduleHide() {
        guard hideWorkItem == nil, isHeldOpen == false else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWorkItem = nil

            // Re-check: the pointer may have come back during the grace period.
            let location = NSEvent.mouseLocation
            let liveArea = (self.panel?.frame ?? .zero).union(self.geometry?.hoverRect ?? .zero)
            guard liveArea.containsPointer(location) == false, self.isHeldOpen == false else { return }

            self.collapse()
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.hideDelay, execute: workItem)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    // MARK: - Presentation

    private func expand(_ display: NotchDisplay) {
        // Only one display is ever open: moving to another closes the first.
        if isExpanded, let current = active, current !== display {
            collapse()
        }

        active = display
        isExpanded = true
        cancelScheduledHide()
        dwellWorkItem?.cancel()
        dwellWorkItem = nil
        if peeking != nil {
            unpeekWorkItem?.cancel()
            unpeekWorkItem = nil
            peeking = nil
        }

        let panel = display.panel
        panel.setFrame(display.geometry.expandedFrame(size: display.panelSize), display: true)
        // Only take clicks while open; the resting bar must not block the menu bar.
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        display.content.present(.expanded)

        poller.interval = Constants.openInterval
        poller.refresh()
    }

    /// Brings a panel up without a hover — a permission request, a shortcut. It opens
    /// on the display the pointer is on, since that is where the user is looking.
    private func ensureExpanded() {
        guard isExpanded == false else { return }
        if displays.isEmpty { syncDisplays() }
        let screen = NotchGeometry.activeScreen ?? NSScreen.main
        guard let display = screen.flatMap(display(for:)) ?? displays.values.first else { return }
        expand(display)
    }

    // MARK: - Screenshots

    private var screenshotDismiss: DispatchWorkItem?
    /// A peek that arrived by itself, not by hovering, holds until this time.
    private var transientUntil: Date?

    /// A screenshot just landed: it pops out of the notch, as macOS's floating
    /// thumbnail does from the corner, for six seconds — longer while the pointer is on
    /// it. An open panel is left alone; the Screenshots view has it already.
    func showScreenshot(_ url: URL) {
        guard isExpanded == false else { return }
        if displays.isEmpty { syncDisplays() }
        let screen = NotchGeometry.activeScreen ?? NSScreen.main
        guard let display = screen.flatMap(display(for:)) ?? displays.values.first else { return }
        display.content.setTransient(.screenshot(url))
        peek(display)
        transientUntil = Date().addingTimeInterval(6)
        Haptics.tick()

        screenshotDismiss?.cancel()
        let work = DispatchWorkItem { [weak self, weak display] in
            guard let self, let display, self.peeking === display else { return }
            self.transientUntil = nil
            if self.peekArea(of: display).containsPointer(NSEvent.mouseLocation) == false { self.unpeek() }
        }
        screenshotDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Takes a screenshot with the panel out of the picture.
    func capture(_ kind: ScreenshotStore.Capture) {
        if isExpanded { collapse() }
        if peeking != nil { unpeek() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            ScreenshotStore.shared.capture(kind)
        }
    }

    /// Opens the notch for a moment on the main display, then lets it settle — the
    /// first launch's only sign of life, since there is no Dock or menu bar icon.
    func introduce() {
        if displays.isEmpty { syncDisplays() }
        guard let screen = NSScreen.main, let display = display(for: screen) else { return }
        expand(display)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.active === display, self.isHeldOpen == false else { return }
            let pointer = NSEvent.mouseLocation
            guard display.panel.frame.union(display.geometry.hoverRect).containsPointer(pointer) == false else { return }
            self.collapse()
        }
    }

    /// Opens straight to a pane from a keyboard shortcut, ready to type.
    func open(_ tab: PanelTab) {
        Log.ui.info("Opening \(String(describing: tab), privacy: .public) from shortcut")
        ensureExpanded()
        guard let panel, let contentView else { return }
        cancelScheduledHide()
        openedByKeyboard = true
        panel.makeKeyAndOrderFront(nil)
        contentView.openForTyping(tab)
    }

    /// A global shortcut: opens its view, or closes the panel if that view is already
    /// what you are looking at — so the same keys open and close it.
    func toggle(_ tab: PanelTab) {
        if isExpanded, contentView?.selectedTab == tab, contentView?.mode == .media {
            dismiss()
        } else {
            open(tab)
        }
    }

    private func dismiss() {
        // An unanswered approval keeps the panel up: closing would hide the question
        // while Claude Code waits on it. ⌘↩ and ⌘⌫ answer it.
        guard isPinned == false else { return }
        // Closed on purpose: don't let a pointer resting on the notch reopen it.
        if let geometry, geometry.isPointerInHoverArea(NSEvent.mouseLocation) {
            hoverSuppressedUntilExit = true
        }
        cancelScheduledHide()
        panel?.makeFirstResponder(nil)
        collapse()
    }

    /// A non-activating panel keeps keyboard focus even while another app is in front.
    /// Left alone, the next keystrokes after closing would land in a hidden text field,
    /// so once the close animation has run, focus is handed back by re-ordering the
    /// window — which drops key status without activating anything.
    private func releaseKeyFocus(after delay: TimeInterval) {
        guard let panel, panel.isKeyWindow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let panel = self.panel, self.isExpanded == false, panel.isKeyWindow else { return }
            let wasVisible = panel.isVisible
            panel.orderOut(nil)
            if wasVisible, self.wantsRestingBar {
                panel.orderFrontRegardless()
            }
        }
    }

    /// Paste needs ⌘V to reach the app in front, so the panel gets out of the way first.
    private func pasteFromClipboard(_ item: ClipboardItem) {
        guard let panel, let contentView else { return }
        cancelScheduledHide()
        panel.makeFirstResponder(nil)
        isExpanded = false
        selectedShortcut = nil
        contentView.stopCamera()
        contentView.showMedia()
        contentView.present(wantsRestingBar ? .idle : .hidden, animated: false)
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        poller.interval = Constants.restingInterval

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            ClipboardHistory.shared.paste(item)
            guard let self, self.wantsRestingBar, self.isExpanded == false else { return }
            panel.orderFrontRegardless()
        }
    }

    private func collapse() {
        guard isExpanded else { return }

        isExpanded = false
        openedByKeyboard = false
        selectedShortcut = nil
        releaseKeyFocus(after: 0.36)
        contentView?.stopCamera()
        contentView?.showMedia()
        poller.interval = Constants.restingInterval

        settleToRestingState()
    }

    /// Playing music leaves a slim bar hugging every notch; otherwise the panels go
    /// away. The display that is open is left alone.
    private func settleToRestingState() {
        // An activity is mid-flight; it will settle the bars when it finishes.
        guard activityWorkItem == nil else { return }

        for display in displays.values where (isExpanded && display === active) == false && display !== peeking {
            let panel = display.panel
            panel.ignoresMouseEvents = true

            if wantsRestingBar {
                display.content.present(.idle)
                panel.orderFrontRegardless()
            } else {
                display.content.present(.hidden)
                // Let the collapse animation finish before pulling the window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self, weak display] in
                    guard let self, let display, self.wantsRestingBar == false,
                          (self.isExpanded && display === self.active) == false else { return }
                    display.panel.orderOut(nil)
                }
            }
        }
    }

    // MARK: - Displays

    /// The display built for this screen, building it if there is none yet.
    private func display(for screen: NSScreen) -> NotchDisplay? {
        guard let id = NotchDisplay.identifier(of: screen) else { return nil }
        if let display = displays[id], display.matches(screen) { return display }
        syncDisplays()
        return displays[id]
    }

    /// Makes the set of displays match the screens attached right now: new screens get
    /// a notch, unplugged ones lose theirs, and a screen whose notch moved — a new
    /// resolution — is rebuilt. Everything built is brought up to date immediately.
    private func syncDisplays() {
        var current: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let id = NotchDisplay.identifier(of: screen) { current[id] = screen }
        }

        for (id, display) in displays where current[id].map(display.matches) != true {
            if display === active {
                collapse()
                active = nil
            }
            display.panel.orderOut(nil)
            displays[id] = nil
        }

        var built = false
        for (id, screen) in current where displays[id] == nil {
            displays[id] = makeDisplay(id: id, screen: screen)
            built = true
        }

        guard built else { return }
        Log.ui.notice("Notch on \(self.displays.count, privacy: .public) display(s)")
        settleToRestingState()
    }

    private func makeDisplay(id: CGDirectDisplayID, screen: NSScreen) -> NotchDisplay {
        let display = NotchDisplay(id: id, screen: screen)
        let contentView = display.content
        contentView.onPlayPause = { [weak self] in self?.perform(.playPause) }
        contentView.onNextTrack = { [weak self] in self?.perform(.nextTrack) }
        contentView.onPreviousTrack = { [weak self] in self?.perform(.previousTrack) }
        contentView.onOpenSource = { [weak self] in self?.openCurrentSource() }
        contentView.onMouseExited = { [weak self] in self?.scheduleHide() }
        contentView.onSelectShortcut = { [weak self] shortcut in self?.showDetails(for: shortcut) }
        contentView.onOpenSelectedApp = { [weak self] in
            guard let shortcut = self?.selectedShortcut else { return }
            AppShortcutStore.activate(shortcut)
        }
        contentView.onBack = { [weak self] in
            self?.selectedShortcut = nil
            self?.contentView?.showMedia()
        }
        contentView.onShuffle = { [weak self] in self?.perform(.toggleShuffle) }
        contentView.onVolume = { [weak self] volume in self?.perform(.setVolume(volume)) }
        contentView.onSeek = { [weak self] seconds in self?.perform(.seek(seconds)) }
        contentView.onPlayURI = { [weak self] uri in self?.perform(.play(uri: uri)) }
        contentView.onStartTimer = { [weak self] minutes in
            guard let self else { return }
            self.countdown.start(minutes: minutes)
            let remaining = self.countdown.remaining
            self.broadcast { $0.updateTimer(remaining: remaining) }
        }
        contentView.onCancelTimer = { [weak self] in
            self?.countdown.cancel()
            self?.broadcast { $0.updateTimer(remaining: 0) }
        }
        contentView.onPeekOpen = { [weak self, weak display] in
            guard let self, let display else { return }
            self.expand(display)
            Haptics.tick()
        }
        // Files dropped on a notch open that notch, not whichever was open last.
        contentView.onFilesDropped = { [weak self, weak display] in
            guard let self, let display else { return }
            self.expand(display)
        }
        contentView.onPasteClipboard = { [weak self] item in self?.pasteFromClipboard(item) }
        contentView.onCapture = { [weak self] kind in self?.capture(kind) }
        contentView.onDismiss = { [weak self] in self?.dismiss() }
        contentView.onOpenSettings = { [weak self] in
            NotificationCenter.default.post(name: .notchHoverOpenSettings, object: nil)
            // The settings window takes over from here; the panel should get out of the way.
            self?.collapse()
        }
        contentView.onApprove = { [weak self] in self?.resolveFrontRequest(.allow) }
        contentView.onDeny = { [weak self] in self?.resolveFrontRequest(.deny) }

        // Start current: whatever every other display is already showing.
        contentView.isAudioPlaying = isAudioPlaying
        contentView.renderNowPlaying(lastState)
        contentView.setPendingCount(pendingRequests.count)
        contentView.updateTimer(remaining: countdown.remaining)
        return display
    }

    private func openCurrentSource() {
        guard let bundleIdentifier = currentSourceBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    // MARK: - App details

    private func showDetails(for shortcut: AppShortcut) {
        // Only Claude has anything worth a pane; for everything else a tile click
        // should just take you there rather than reporting version numbers.
        guard shortcut.bundleIdentifier == AppDetailProvider.claudeBundleIdentifier else {
            AppShortcutStore.activate(shortcut)
            return
        }

        selectedShortcut = shortcut
        AppDetailProvider.fetch(for: shortcut, pendingRequests: pendingRequests.count) { [weak self] details in
            guard let self, self.contentView?.mode != .permission else { return }
            self.contentView?.showApp(details)
        }
    }

    // MARK: - Permission requests

    private func enqueue(_ request: PermissionRequest) {
        pendingRequests.append(request)

        let timeout = DispatchWorkItem { [weak self] in
            // Never approve on its own: hand the decision back to Claude Code.
            self?.resolve(request.id, with: .ask)
        }
        timeouts[request.id] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.requestTimeout, execute: timeout)

        ensureExpanded()
        presentFrontRequest()
    }

    private func presentFrontRequest() {
        guard let request = pendingRequests.first, let contentView else { return }
        let count = pendingRequests.count
        broadcast { $0.setPendingCount(count) }
        contentView.showPermission(request, queued: count - 1)
    }

    private func resolveFrontRequest(_ decision: PermissionDecision) {
        guard let request = pendingRequests.first else { return }
        Haptics.step()
        resolve(request.id, with: decision)
    }

    private func resolve(_ id: UUID, with decision: PermissionDecision) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else { return }

        let request = pendingRequests.remove(at: index)
        request.respond(decision)
        timeouts[id]?.cancel()
        timeouts[id] = nil
        Log.permissions.notice("\(request.toolName, privacy: .public) resolved: \(decision.rawValue, privacy: .public)")

        let count = pendingRequests.count
        broadcast { $0.setPendingCount(count) }

        if pendingRequests.isEmpty {
            contentView?.showMedia()
            scheduleHide()
        } else {
            presentFrontRequest()
        }
    }

    /// Applies new settings with the lightest touch that will do.
    ///
    /// Only the theme is baked into the panel at build time; the resting-bar mode,
    /// playlists, shortcuts and app list are all read live, so changing those must not
    /// tear the panel down.
    private func applyChangedSettings() {
        // Never yank the panel out from under a pending approval.
        guard pendingRequests.isEmpty else { return }

        let themeChanged = displays.values.contains { $0.content.themeID != ThemeStore.signature }
        // A theme picked in quick settings rebuilds the panel; it comes back on them.
        let reopenQuickSettings = isExpanded && active?.content.isShowingQuickSettings == true

        Log.ui.notice("Settings applied; rebuild needed: \(themeChanged, privacy: .public)")

        if themeChanged {
            // The material is baked in at build time, so every display is rebuilt; each
            // new one replays the current state as it is made.
            displays.values.forEach { $0.panel.orderOut(nil) }
            displays.removeAll()
            active = nil
            isExpanded = false
            syncDisplays()
            if reopenQuickSettings {
                ensureExpanded()
                active?.content.setQuickSettingsVisible(true)
                poller.refresh()
                return
            }
        } else {
            broadcast { $0.reloadLists() }
            broadcast { $0.applyThemeTweaks() }
        }

        poller.refresh()
        settleToRestingState()
    }

    // MARK: - Live activities

    /// Shows a system event on the resting bar, then hands the bar back.
    private func present(_ activity: LiveActivity) {
        if displays.isEmpty { syncDisplays() }
        // The open panel already shows everything; the event goes to the resting ones.
        let resting = displays.values.filter { (isExpanded && $0 === active) == false && $0 !== peeking }
        guard resting.isEmpty == false else { return }

        Log.system.notice("Activity: \(String(describing: activity), privacy: .public)")
        activityWorkItem?.cancel()
        // showActivity sizes the bar to the event and pops it out of the notch; it
        // brings the bar up itself if it was away, so nothing else may present here.
        for display in resting {
            display.content.showActivity(activity)
            display.panel.ignoresMouseEvents = true
            display.panel.orderFrontRegardless()
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activityWorkItem = nil
            self.broadcast { $0.clearActivity() }
            self.settleToRestingState()
            // One breath as the bar shrinks back, so the hand-off is not a dead stop.
            if self.wantsRestingBar { self.breathe(cycles: 1) }
        }
        activityWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + activity.duration, execute: work)
    }

    // MARK: - Data

    private func apply(_ result: Result<TrackInfo?, MediaError>) {
        LyricsService.shared.update(try? result.get())
        lockScreen.update(try? result.get())
        if displays.isEmpty {
            // Nothing built yet: only something playing is worth building panels for,
            // whether that is a track we can name or audio we can only hear.
            if case .success(let track) = result {
                isPlaying = track?.isPlaying == true
                hasTrack = track != nil
                guard wantsRestingBar else { return }
                lastTrackKey = track.map { "\($0.name)|\($0.artist)" }
                lastTrack = track
                lastState = nowPlayingState(for: track)
                syncDisplays()
                breathe()
            }
            return
        }

        var startedSomething = false
        // Shown only when nothing at all is playing: "Spotify is not running" is not
        // news while a video is. Both paths end at the same decision, so a player that
        // is closed or broken can never outrank sound that is actually coming out.
        var fallback = "Nothing playing"

        switch result {
        case .success(let track):
            currentSourceBundleIdentifier = track?.sourceBundleIdentifier
            let wasPlaying = isPlaying
            isPlaying = track?.isPlaying == true
            hasTrack = track != nil
            // Music starting, and each new track after it, is worth a breath. A tick
            // that says the same thing as the last one is not.
            let key = track.map { "\($0.name)|\($0.artist)" }
            startedSomething = isPlaying && (wasPlaying == false || key != lastTrackKey)
            lastTrackKey = key
            lastTrack = track
        case .failure(let error):
            isPlaying = false
            hasTrack = false
            lastTrackKey = nil
            lastTrack = nil
            fallback = error.shortDisplayText
            Log.media.error("Notch fetch failed: \(error.localizedDescription, privacy: .public)")
        }

        // Whoever holds the audio can change without the device ever going quiet — one
        // video ends, another app starts — so it is re-read whenever it is what the bar
        // would be showing, and so is the page inside it.
        if isPlaying == false, isAudioPlaying {
            audioSource = AudioSourceProbe.current()
            refreshBrowserPage()
        }
        render(nowPlayingState(for: lastTrack, fallback: fallback))
        settleToRestingState()

        // After settling, so the bar is out and resting before it takes the breath.
        if startedSomething { breathe() }

        // Keep an open app pane current, so "what's going on" stays true while watched.
        if isExpanded, contentView?.mode == .app, let shortcut = selectedShortcut {
            showDetails(for: shortcut)
        }
    }

    /// Play, pause and skip from a shortcut, without the panel.
    func performMedia(_ action: MediaAction) {
        perform(action)
    }

    private func perform(_ action: MediaAction) {
        mediaController.control(action) { [weak self] result in
            if case .failure(let error) = result {
                Log.media.error("Control \(String(describing: action), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.poller.refreshSoon()
        }
    }
}
