import AppKit

/// Owns the notch panel: the resting bar, hover expansion, what the detail pane is
/// showing, and the queue of Claude Code permission requests waiting on an answer.
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
    private let permissionBridge: PermissionBridge
    private let activityCenter: ActivityCenter
    private let countdown: CountdownTimer
    private let audioActivity = AudioActivityMonitor()

    private var panel: NotchPanel?
    private var contentView: NotchContentView?
    private var builtGeometryKey: String?

    private var geometry: NotchGeometry?
    private var mouseMonitors: [Any] = []
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
        // The global monitor goes quiet while the pointer is over our own panel.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in
            handler(event)
            return event
        }) {
            mouseMonitors.append(local)
        }

        poller.addObserver { [weak self] result in
            self?.apply(result)
        }

        activityCenter.addObserver { [weak self] activity in
            self?.present(activity)
        }

        NotificationWatcher.shared.onCapture = { [weak self] _ in
            self?.contentView?.refreshNotifications()
        }

        countdown.onTick = { [weak self] remaining in
            self?.contentView?.updateTimer(remaining: remaining)
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

        // Clicking into another app takes keyboard focus away; that is the cue to close.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, (notification.object as? NSWindow) === self.panel, self.isExpanded else { return }
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
        if contentView == nil, wantsRestingBar { buildForResting() }
        contentView?.isAudioPlaying = active
        // The bar is showing whatever is making the sound, so it has to be told what
        // that is now rather than at the next poller tick — the poller only knows
        // about Spotify and Music.
        if isPlaying == false { contentView?.renderNowPlaying(nowPlayingState(for: lastTrack)) }
        if isExpanded == false { settleToRestingState() }
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
            self.contentView?.renderNowPlaying(self.nowPlayingState(for: self.lastTrack))
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
        guard isExpanded == false else { return }
        contentView?.breathe(cycles: cycles)
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
        panel?.orderOut(nil)
    }

    // MARK: - Hover handling

    private func handlePointerMoved() {
        let location = NSEvent.mouseLocation

        if isExpanded {
            guard let panel else { return }
            let liveArea = panel.frame.union(geometry?.hoverRect ?? .zero)
            if liveArea.containsPointer(location) {
                cancelScheduledHide()
            } else {
                scheduleHide()
            }
            return
        }

        guard let screen = NotchGeometry.activeScreen else { return }
        let geometry = NotchGeometry(screen: screen)
        if geometry.isPointerInHoverArea(location) {
            expand(using: geometry)
        }
    }

    private func scheduleHide() {
        guard hideWorkItem == nil, isPinned == false, isEditingText == false else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWorkItem = nil

            // Re-check: the pointer may have come back during the grace period.
            let location = NSEvent.mouseLocation
            let liveArea = (self.panel?.frame ?? .zero).union(self.geometry?.hoverRect ?? .zero)
            guard liveArea.containsPointer(location) == false,
                  self.isPinned == false,
                  self.isEditingText == false else { return }

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

    private func expand(using geometry: NotchGeometry) {
        self.geometry = geometry
        let panel = makePanel(for: geometry)

        isExpanded = true
        cancelScheduledHide()

        panel.setFrame(geometry.expandedFrame(size: panelSize(for: geometry)), display: true)
        // Only take clicks while open; the resting bar must not block the menu bar.
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        contentView?.present(.expanded)

        poller.interval = Constants.openInterval
        poller.refresh()
    }

    /// Brings the panel up without a hover — used when a permission request lands.
    private func ensureExpanded() {
        guard isExpanded == false else { return }
        guard let screen = NotchGeometry.activeScreen ?? NSScreen.main else { return }
        expand(using: NotchGeometry(screen: screen))
    }

    /// Opens straight to a pane from a keyboard shortcut, ready to type.
    func open(_ tab: TabStripView.Tab) {
        Log.ui.info("Opening \(String(describing: tab), privacy: .public) from shortcut")
        ensureExpanded()
        guard let panel, let contentView else { return }
        cancelScheduledHide()
        panel.makeKeyAndOrderFront(nil)
        contentView.openForTyping(tab)
    }

    private func dismiss() {
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
        selectedShortcut = nil
        releaseKeyFocus(after: 0.36)
        contentView?.stopCamera()
        contentView?.showMedia()
        poller.interval = Constants.restingInterval

        settleToRestingState()
    }

    /// Playing music leaves a slim bar hugging the notch; otherwise the panel goes away.
    private func settleToRestingState() {
        guard isExpanded == false, let panel, let contentView else { return }
        // An activity is mid-flight; it will settle the bar when it finishes.
        guard activityWorkItem == nil else { return }

        panel.ignoresMouseEvents = true

        if wantsRestingBar {
            contentView.present(.idle)
            panel.orderFrontRegardless()
        } else {
            contentView.present(.hidden)
            // Let the collapse animation finish before pulling the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
                guard self?.isExpanded == false, self?.wantsRestingBar == false else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func panelSize(for geometry: NotchGeometry) -> CGSize {
        NotchContentView.Metrics.panelSize(
            notchWidth: geometry.hasNotch ? geometry.notchRect.width : 0,
            notchHeight: geometry.hasNotch ? geometry.notchRect.height : 0
        )
    }

    private func makePanel(for geometry: NotchGeometry) -> NotchPanel {
        let notchWidth = geometry.hasNotch ? geometry.notchRect.width : 0
        let notchHeight = geometry.hasNotch ? geometry.notchRect.height : 0
        let key = "\(notchWidth)x\(notchHeight)"

        if let panel, builtGeometryKey == key {
            return panel
        }

        let contentView = NotchContentView(notchWidth: notchWidth, notchHeight: notchHeight)
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
            self?.countdown.start(minutes: minutes)
            self?.contentView?.updateTimer(remaining: self?.countdown.remaining ?? 0)
        }
        contentView.onCancelTimer = { [weak self] in
            self?.countdown.cancel()
            self?.contentView?.updateTimer(remaining: 0)
        }
        contentView.onFilesDropped = { [weak self] in self?.ensureExpanded() }
        contentView.onPasteClipboard = { [weak self] item in self?.pasteFromClipboard(item) }
        contentView.onDismiss = { [weak self] in self?.dismiss() }
        contentView.onOpenSettings = { [weak self] in
            NotificationCenter.default.post(name: .notchHoverOpenSettings, object: nil)
            // The settings window takes over from here; the panel should get out of the way.
            self?.collapse()
        }
        contentView.onApprove = { [weak self] in self?.resolveFrontRequest(.allow) }
        contentView.onDeny = { [weak self] in self?.resolveFrontRequest(.deny) }
        contentView.renderNowPlaying(.message("Loading…"))

        let panel = NotchPanel(contentView: contentView)
        panel.setFrame(geometry.expandedFrame(size: panelSize(for: geometry)), display: false)
        self.panel = panel
        self.contentView = contentView
        builtGeometryKey = key
        return panel
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
        contentView.setPendingCount(pendingRequests.count)
        contentView.showPermission(request, queued: pendingRequests.count - 1)
    }

    private func resolveFrontRequest(_ decision: PermissionDecision) {
        guard let request = pendingRequests.first else { return }
        resolve(request.id, with: decision)
    }

    private func resolve(_ id: UUID, with decision: PermissionDecision) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else { return }

        let request = pendingRequests.remove(at: index)
        request.respond(decision)
        timeouts[id]?.cancel()
        timeouts[id] = nil
        Log.permissions.notice("\(request.toolName, privacy: .public) resolved: \(decision.rawValue, privacy: .public)")

        contentView?.setPendingCount(pendingRequests.count)

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

        let themeChanged = contentView?.themeID != ThemeStore.selected.id

        Log.ui.notice("Settings applied; rebuild needed: \(themeChanged, privacy: .public)")

        if themeChanged {
            panel?.orderOut(nil)
            panel = nil
            contentView = nil
            builtGeometryKey = nil
            isExpanded = false
        } else {
            contentView?.reloadLists()
        }

        poller.refresh()
        if isExpanded == false {
            settleToRestingState()
        }
    }

    // MARK: - Live activities

    /// Shows a system event on the resting bar, then hands the bar back.
    private func present(_ activity: LiveActivity) {
        if contentView == nil {
            buildForResting()
        }
        guard let contentView, let panel, isExpanded == false else { return }

        Log.system.notice("Activity: \(String(describing: activity), privacy: .public)")
        activityWorkItem?.cancel()
        // showActivity sizes the bar to the event and pops it out of the notch; it
        // brings the bar up itself if it was away, so nothing else may present here.
        contentView.showActivity(activity)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activityWorkItem = nil
            self.contentView?.clearActivity()
            self.settleToRestingState()
            // One breath as the bar shrinks back, so the hand-off is not a dead stop.
            if self.wantsRestingBar { self.breathe(cycles: 1) }
        }
        activityWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + activity.duration, execute: work)
    }

    // MARK: - Data

    private func apply(_ result: Result<TrackInfo?, MediaError>) {
        guard let contentView else {
            // Nothing built yet: only something playing is worth building a panel for,
            // whether that is a track we can name or audio we can only hear.
            if case .success(let track) = result {
                isPlaying = track?.isPlaying == true
                hasTrack = track != nil
                guard wantsRestingBar else { return }
                lastTrackKey = track.map { "\($0.name)|\($0.artist)" }
                lastTrack = track
                buildForResting()
                self.contentView?.isAudioPlaying = isAudioPlaying
                self.contentView?.renderNowPlaying(nowPlayingState(for: track))
                settleToRestingState()
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
        contentView.renderNowPlaying(nowPlayingState(for: lastTrack, fallback: fallback))

        if isExpanded == false {
            settleToRestingState()
        }

        // After settling, so the bar is out and resting before it takes the breath.
        if startedSomething { breathe() }

        // Keep an open app pane current, so "what's going on" stays true while watched.
        if isExpanded, contentView.mode == .app, let shortcut = selectedShortcut {
            showDetails(for: shortcut)
        }
    }

    private func buildForResting() {
        guard let screen = NotchGeometry.activeScreen ?? NSScreen.main else { return }
        let geometry = NotchGeometry(screen: screen)
        self.geometry = geometry
        _ = makePanel(for: geometry)
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
