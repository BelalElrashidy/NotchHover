import AppKit

/// The panel body. A glass slab wraps around the notch and grows out of it: the tabs
/// sit in the wing left of the notch, the actions in the wing to its right, and the
/// rest of the panel is the view you chose — no bar along the bottom. While something
/// is playing it rests as a slim bar hugging the notch.
final class NotchContentView: NSView {
    enum DetailMode {
        case media
        case app
        case permission
    }

    enum Presentation {
        case hidden
        case idle
        case expanded
    }

    enum Metrics {
        /// Clearance between the detail pane and the slab's curved edges.
        static let detailInset: CGFloat = 12
        static let fallbackNotchWidth: CGFloat = 180
        static let fallbackNotchHeight: CGFloat = 28

        static var detailHeight: CGFloat { PanelSizes.height }
        static var idleWing: CGFloat { PanelSizes.restingWing }

        static func bandHeight(notchHeight: CGFloat) -> CGFloat {
            max(notchHeight, fallbackNotchHeight)
        }

        /// The wings are whatever is left either side of the notch once the flare is
        /// taken off, so the band always matches the panel's actual width.
        static func wingWidth(notchWidth: CGFloat) -> CGFloat {
            let notch = max(notchWidth, fallbackNotchWidth)
            let width = panelSize(notchWidth: notchWidth, notchHeight: 0).width
            return max(60, (width - notch - NotchShape.topFlare * 2) / 2)
        }

        static func panelSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
            let notch = max(notchWidth, fallbackNotchWidth)
            let width = PanelSizes.usesAutomaticWidth
                ? PanelSizes.automaticWidth(for: PanelLayoutStore.widgets, notchWidth: notch)
                : PanelSizes.width
            return CGSize(
                // The visible slab is inset by the flare on each side; the widgets and
                // the notch have to fit inside what is left.
                width: max(width, notch + NotchShape.topFlare * 2 + 240),
                height: bandHeight(notchHeight: notchHeight) + detailHeight
            )
        }
    }

    // Media
    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    var onOpenSource: (() -> Void)?
    // Navigation
    var onSelectShortcut: ((AppShortcut) -> Void)?
    var onOpenSelectedApp: (() -> Void)?
    var onBack: (() -> Void)?
    // Permissions
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?
    var onMouseExited: (() -> Void)?
    // Panes
    var onShuffle: (() -> Void)?
    var onVolume: ((Int) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onPlayURI: ((String) -> Void)?
    var onStartTimer: ((Int) -> Void)?
    var onCancelTimer: (() -> Void)?
    var onFilesDropped: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Clipboard paste needs the panel out of the way before ⌘V is sent.
    var onPasteClipboard: ((ClipboardItem) -> Void)?
    /// Escape, from a text field or anywhere in the panel.
    var onDismiss: (() -> Void)?

    private(set) var mode: DetailMode = .media
    private(set) var presentation: Presentation = .hidden

    let card: GlassCardView
    private let expandedContent = NSView()
    private let topBand = NSView()
    private let leftWing = NSView()
    private let rightWing = NSView()
    private let detailContainer = NSView()
    private let idleContent: IdleActivityView

    private let headerTabs = HeaderTabsView()
    private let headerActions = HeaderActionsView()
    /// The artwork for what is playing, kept for the resting bar and the artwork theme.
    private var artwork: NSImage?

    private let mediaDetail = MediaDetailView()
    private lazy var playlistsPane = PlaylistsPaneView()
    private lazy var trayPane = TrayPaneView()
    private lazy var shortcutsPane = ShortcutsPaneView()
    private lazy var timerPane = TimerPaneView()
    private lazy var appsPane = AppsPaneView()
    private lazy var systemPane = SystemPaneView()
    private lazy var calendarPane = CalendarPaneView()
    private lazy var notificationsPane = NotificationsPaneView()
    private lazy var mirrorPane = MirrorPaneView()
    private lazy var appDetail = AppDetailView()
    private lazy var permissionDetail = PermissionDetailView()
    private lazy var notesPane: NotesPaneView = {
        let pane = NotesPaneView()
        pane.onDismiss = { [weak self] in self?.onDismiss?() }
        return pane
    }()
    private lazy var clipboardPane: ClipboardPaneView = {
        let pane = ClipboardPaneView()
        pane.onPaste = { [weak self] item in self?.onPasteClipboard?(item) }
        pane.onDismiss = { [weak self] in self?.onDismiss?() }
        return pane
    }()
    private lazy var widgetRow = WidgetRowView(callbacks: WidgetRowView.Callbacks(
        onPlayPause: { [weak self] in self?.onPlayPause?() },
        onNextTrack: { [weak self] in self?.onNextTrack?() },
        onPreviousTrack: { [weak self] in self?.onPreviousTrack?() },
        onOpenSource: { [weak self] in self?.onOpenSource?() },
        onShuffle: { [weak self] in self?.onShuffle?() },
        onVolume: { [weak self] volume in self?.onVolume?(volume) },
        onSeek: { [weak self] seconds in self?.onSeek?(seconds) },
        onPlayURI: { [weak self] uri in self?.onPlayURI?(uri) },
        onSelectShortcut: { [weak self] shortcut in self?.onSelectShortcut?(shortcut) },
        onStartTimer: { [weak self] minutes in self?.onStartTimer?(minutes) },
        onCancelTimer: { [weak self] in self?.onCancelTimer?() },
        onPasteClipboard: { [weak self] item in self?.onPasteClipboard?(item) },
        onDismiss: { [weak self] in self?.onDismiss?() }
    ))
    /// Files beside recent clips: two things you put down to pick up later.
    private lazy var shelfRow = WidgetRowView(
        callbacks: WidgetRowView.Callbacks(
            onPlayPause: {}, onNextTrack: {}, onPreviousTrack: {}, onOpenSource: {},
            onShuffle: {}, onVolume: { _ in }, onSeek: { _ in }, onPlayURI: { _ in },
            onSelectShortcut: { _ in }, onStartTimer: { _ in }, onCancelTimer: {},
            onPasteClipboard: { [weak self] item in self?.onPasteClipboard?(item) },
            onDismiss: { [weak self] in self?.onDismiss?() }
        ),
        widgets: { [.tray, .clipboard] }
    )
    private let paneContainer = NSView()
    /// ⌘/ — every shortcut, over the pane.
    private lazy var shortcutSheet = ShortcutSheetView()
    /// Which view the panel is showing.
    private(set) var selectedTab: PanelTab = .home

    private let notchWidth: CGFloat
    private let bandHeight: CGFloat
    private var artworkKey: String?

    /// Width the resting bar is holding for the activity currently on it. Nil means
    /// the bar is back to its own size.
    private var activityBarWidth: CGFloat?


    /// Something is coming out of the speakers that no player we can talk to owns — a
    /// video in a browser, say. The resting bar still has something to say about it.
    var isAudioPlaying = false {
        didSet {
            guard isAudioPlaying != oldValue, hasTrack == false else { return }
            idleContent.update(artwork: nil, isPlaying: isAudioPlaying)
        }
    }

    private var hasTrack = false

    init(notchWidth: CGFloat, notchHeight: CGFloat) {
        self.notchWidth = max(notchWidth, Metrics.fallbackNotchWidth)
        self.bandHeight = Metrics.bandHeight(notchHeight: notchHeight)
        self.idleContent = IdleActivityView(notchWidth: self.notchWidth, bandHeight: self.bandHeight)

        let panelSize = Metrics.panelSize(notchWidth: notchWidth, notchHeight: notchHeight)
        card = GlassCardView(frame: CGRect(origin: .zero, size: panelSize))

        super.init(frame: CGRect(origin: .zero, size: panelSize))
        addSubview(card)
        configureBands(panelSize: panelSize)
        configureWings()
        configureDetail()

        // Whatever the bar is showing rises and falls with the slab around it.
        card.onBreath = { [weak self] cycles in
            self?.idleContent.breathe(cycles: cycles)
        }

        // The card always spans the panel; its shape is what animates.
        card.frame = bounds
        card.autoresizingMask = [.width, .height]
        card.animateShape(
            to: collapsedCardFrame,
            bottomRadius: NotchShape.idleBottomRadius,
            duration: 0,
            timing: CAMediaTimingFunction(name: .linear)
        )
        card.alphaValue = 0
        expandedContent.alphaValue = 0
        idleContent.alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Structure

    private func configureBands(panelSize: CGSize) {
        let content = card.contentContainer

        expandedContent.frame = content.bounds
        expandedContent.autoresizingMask = [.width, .height]
        content.addSubview(expandedContent)

        idleContent.frame = content.bounds
        idleContent.autoresizingMask = [.width, .height]
        content.addSubview(idleContent)

        let width = expandedContent.bounds.width
        topBand.frame = CGRect(x: 0, y: expandedContent.bounds.height - bandHeight, width: width, height: bandHeight)
        topBand.autoresizingMask = [.width, .minYMargin]
        expandedContent.addSubview(topBand)

        // Inset from the slab edge: the bottom corners curve inward, and content
        // laid out flush would be clipped by the mask.
        detailContainer.frame = CGRect(
            x: Metrics.detailInset,
            y: Metrics.detailInset,
            width: width - Metrics.detailInset * 2,
            height: Metrics.detailHeight - Metrics.detailInset
        )
        detailContainer.autoresizingMask = [.width, .maxYMargin]
        expandedContent.addSubview(detailContainer)

        // The middle of the band is left empty: that is where the notch sits.
        let wing = Metrics.wingWidth(notchWidth: notchWidth)
        leftWing.frame = CGRect(x: 0, y: 0, width: wing, height: bandHeight)
        leftWing.autoresizingMask = [.maxXMargin, .height]
        topBand.addSubview(leftWing)

        rightWing.frame = CGRect(x: width - wing, y: 0, width: wing, height: bandHeight)
        rightWing.autoresizingMask = [.minXMargin, .height]
        topBand.addSubview(rightWing)
    }

    /// The band beside the notch is the navigation: tabs on the left, actions on the
    /// right. It used to repeat what was playing — the same title and transport the
    /// pane underneath already showed.
    private func configureWings() {
        headerTabs.translatesAutoresizingMaskIntoConstraints = false
        headerTabs.onSelect = { [weak self] tab in self?.show(tab) }
        leftWing.addSubview(headerTabs)

        headerActions.translatesAutoresizingMaskIntoConstraints = false
        headerActions.onClipboard = { [weak self] in self?.toggle(.clipboard) }
        headerActions.onMirror = { [weak self] in self?.toggle(.mirror) }
        headerActions.onSettings = { [weak self] in self?.onOpenSettings?() }
        rightWing.addSubview(headerActions)

        NSLayoutConstraint.activate([
            // Against the slab's outer edges, the way a window's toolbar sits: the
            // notch is the gap in the middle, not something to crowd.
            headerTabs.leadingAnchor.constraint(equalTo: leftWing.leadingAnchor, constant: 14),
            headerTabs.trailingAnchor.constraint(lessThanOrEqualTo: leftWing.trailingAnchor, constant: -8),
            headerTabs.centerYAnchor.constraint(equalTo: leftWing.centerYAnchor),
            headerActions.trailingAnchor.constraint(equalTo: rightWing.trailingAnchor, constant: -14),
            headerActions.leadingAnchor.constraint(greaterThanOrEqualTo: rightWing.leadingAnchor, constant: 8),
            headerActions.centerYAnchor.constraint(equalTo: rightWing.centerYAnchor)
        ])
    }

    /// True while the gear's menu is open, so the controller leaves the panel up.
    var isShowingMenu: Bool { headerActions.isShowingMenu }

    private func configureDetail() {
        // The whole detail area is the pane: navigation lives beside the notch.
        paneContainer.frame = detailContainer.bounds
        paneContainer.autoresizingMask = [.width, .height]
        detailContainer.addSubview(paneContainer)

        mediaDetail.onShuffle = { [weak self] in self?.onShuffle?() }
        mediaDetail.onVolume = { [weak self] volume in self?.onVolume?(volume) }
        mediaDetail.onSeek = { [weak self] seconds in self?.onSeek?(seconds) }
        playlistsPane.onPlay = { [weak self] uri in self?.onPlayURI?(uri) }
        timerPane.onStart = { [weak self] minutes in self?.onStartTimer?(minutes) }
        timerPane.onCancel = { [weak self] in self?.onCancelTimer?() }
        appsPane.onSelect = { [weak self] shortcut in self?.onSelectShortcut?(shortcut) }
        // Every display's panel shows the same shelf, so it listens rather than being
        // the tray's one callback.
        NotificationCenter.default.addObserver(forName: .fileTrayDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.trayPane.reload()
            self?.widgetRow.reloadTray()
            self?.shelfRow.reloadTray()
        }
        registerForDraggedTypes([.fileURL])

        mediaDetail.onPlayPause = { [weak self] in self?.onPlayPause?() }
        mediaDetail.onNextTrack = { [weak self] in self?.onNextTrack?() }
        mediaDetail.onPreviousTrack = { [weak self] in self?.onPreviousTrack?() }
        mediaDetail.onOpenSource = { [weak self] in self?.onOpenSource?() }

        appDetail.onOpen = { [weak self] in self?.onOpenSelectedApp?() }
        appDetail.onBack = { [weak self] in self?.onBack?() }

        permissionDetail.onApprove = { [weak self] in self?.onApprove?() }
        permissionDetail.onDeny = { [weak self] in self?.onDeny?() }

        show(.home)
    }

    private func install(_ view: NSView) {
        paneContainer.subviews.forEach { $0.removeFromSuperview() }
        // Leaving the camera or a polling timer running behind a hidden pane is rude.
        if view !== mirrorPane { mirrorPane.stopIfNeeded() }
        if view !== systemPane { systemPane.stopTracking() }
        if view !== widgetRow { widgetRow.stopTracking() }
        if view !== shelfRow { shelfRow.stopTracking() }
        view.frame = paneContainer.bounds
        view.autoresizingMask = [.width, .height]
        paneContainer.addSubview(view)
    }

    private func show(_ tab: PanelTab) {
        mode = .media
        selectedTab = tab
        setShortcutSheetVisible(false)
        // Views that aren't tabs leave no tab highlighted; picking one goes back.
        headerTabs.select(tab, notify: false)
        headerActions.setOpen(tab)
        switch tab {
        case .home: widgetRow.startTracking(); widgetRow.reloadTray(); install(widgetRow)
        case .shelf: shelfRow.startTracking(); shelfRow.reloadTray(); install(shelfRow)
        case .clipboard: install(clipboardPane)
        case .notes:
            install(notesPane)
            // Choosing Notes means you are about to write one.
            DispatchQueue.main.async { [weak self] in self?.notesPane.focus() }
        case .nowPlaying: install(mediaDetail)
        case .playlists: playlistsPane.reload(); install(playlistsPane)
        case .tray: trayPane.reload(); install(trayPane)
        case .shortcuts: shortcutsPane.reload(); install(shortcutsPane)
        case .timer: install(timerPane)
        case .system: systemPane.startTracking(); install(systemPane)
        case .calendar: calendarPane.reload(); install(calendarPane)
        case .notifications: notificationsPane.reload(); install(notificationsPane)
        case .apps: appsPane.reload(); install(appsPane)
        case .mirror: install(mirrorPane)
        }
    }

    // MARK: - Keyboard

    /// Everything in the panel can be reached without the pointer. Shortcuts that a
    /// text field also uses — ⌘← moves the cursor, ⌘⌫ deletes a line — are left alone
    /// while one is focused, so typing always behaves like typing.
    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isTyping = window?.firstResponder is NSTextView

        enum Key: UInt16 {
            case tab = 48, space = 49, delete = 51, escape = 53, enter = 36
            case left = 123, right = 124, down = 125, up = 126
        }
        let code = Key(rawValue: event.keyCode)

        // The sheet is the one thing Esc closes before the panel.
        if code == .escape, shortcutSheet.superview != nil {
            setShortcutSheetVisible(false)
            return true
        }

        switch modifiers {
        case [.command]:
            switch key {
            case "1", "2", "3", "4", "5":
                let tabs: [PanelTab] = [.home, .shelf, .notes, .clipboard, .mirror]
                let tab = tabs[Int(key)! - 1]
                show(tab)
                if tab == .clipboard { DispatchQueue.main.async { [weak self] in self?.clipboardPane.focus() } }
                return true
            case "/":
                setShortcutSheetVisible(shortcutSheet.superview == nil)
                return true
            case "w":
                onDismiss?()
                return true
            default: break
            }

            if mode == .permission {
                if code == .enter { onApprove?(); return true }
                if code == .delete { onDeny?(); return true }
                return false
            }

            switch (selectedTab, key, code) {
            case (.clipboard, _, .enter): clipboardPane.pasteSelected(); return true
            case (.clipboard, "p", _): clipboardPane.togglePinSelected(); return true
            // Only with the search box empty: with text in it, ⌘⌫ edits the search.
            case (.clipboard, _, .delete) where clipboardPane.searchText.isEmpty:
                clipboardPane.deleteSelected(); return true
            case (.notes, "n", _): notesPane.newNote(); return true
            case (.notes, "[", _): notesPane.openAdjacent(by: -1); return true
            case (.notes, "]", _): notesPane.openAdjacent(by: 1); return true
            case (.shelf, "s", _): shelfRow.trayPane?.share(); return true
            case (.shelf, "r", _): FileTray.shared.revealInFinder(); return true
            default: break
            }

            // Playback and volume, unless the arrows are moving a text cursor.
            guard isTyping == false else { return false }
            switch code {
            case .left: onPreviousTrack?(); return true
            case .right: onNextTrack?(); return true
            case .up: nudgeVolume(by: 1); return true
            case .down: nudgeVolume(by: -1); return true
            default: return false
            }

        case [.command, .shift] where key == "m":
            SystemControls.setInputMuted(SystemControls.isInputMuted() == false)
            refreshPanes()
            return true

        case [.control] where code == .tab, [.control, .shift] where code == .tab:
            let tabs = PanelTab.headerTabs
            let current = tabs.firstIndex(of: selectedTab) ?? -1
            let step = modifiers.contains(.shift) ? -1 : 1
            show(tabs[(current + step + tabs.count) % tabs.count])
            return true

        case []:
            // Plain keys only arrive here when nothing focused wanted them.
            switch code {
            case .escape: onDismiss?(); return true
            case .space where isTyping == false && mode == .media: onPlayPause?(); return true
            case .up where selectedTab == .clipboard: clipboardPane.moveSelection(by: -1); return true
            case .down where selectedTab == .clipboard: clipboardPane.moveSelection(by: 1); return true
            case .enter where selectedTab == .clipboard: clipboardPane.copySelected(); return true
            default: return false
            }

        default:
            return false
        }
    }

    var isShowingShortcuts: Bool { shortcutSheet.superview != nil }

    /// Preview hook.
    func showShortcutsForPreview() {
        present(.expanded, animated: false)
        setShortcutSheetVisible(true)
    }

    /// For the self-test.
    var clipboardSelectionIndex: Int { clipboardPane.selectionIndex }

    /// ⌘↑ and ⌘↓ step the output volume by a sixteenth, the size of a volume-key press.
    private func nudgeVolume(by direction: Int) {
        let current = SystemControls.isMuted() ? 0 : (SystemControls.volume() ?? 0)
        SystemControls.setVolume(min(1, max(0, current + Double(direction) / 16)))
        if direction > 0, SystemControls.isMuted() { SystemControls.setMuted(false) }
    }

    private func setShortcutSheetVisible(_ visible: Bool) {
        guard visible != (shortcutSheet.superview != nil) else { return }
        // The pane underneath is hidden rather than covered: nothing reads through.
        paneContainer.isHidden = visible
        if visible {
            shortcutSheet.frame = detailContainer.frame
            shortcutSheet.autoresizingMask = [.width, .height]
            expandedContent.addSubview(shortcutSheet)
        } else {
            shortcutSheet.removeFromSuperview()
        }
    }

    /// The header's clipboard and mirror buttons: open the view, or, pressed again,
    /// go back to Home.
    private func toggle(_ tab: PanelTab) {
        show(selectedTab == tab ? .home : tab)
        if tab == .clipboard, selectedTab == .clipboard {
            DispatchQueue.main.async { [weak self] in self?.clipboardPane.focus() }
        }
    }

    func updateTimer(remaining: TimeInterval) {
        timerPane.update(remaining: remaining)
        widgetRow.updateTimer(remaining: remaining)
    }

    /// Puts a system event on the resting bar and makes the bar react to it: a bar
    /// that is already out pops and settles, one that is away grows out of the notch.
    func showActivity(_ activity: LiveActivity) {
        activityBarWidth = idleContent.showActivity(activity)
        idleContent.barWidth = idleBodyWidth
        idleContent.needsLayout = true

        if presentation == .idle {
            // The pop is this event's motion; a breath underneath it would be noise.
            card.cancelBreathing()
            popIdleShape()
        } else {
            present(.idle)
        }
    }

    /// Hands the bar back to now playing, shrinking it to its own width again.
    func clearActivity() {
        guard activityBarWidth != nil else { return }
        activityBarWidth = nil
        idleContent.clearActivity()
        idleContent.barWidth = idleBodyWidth

        guard presentation == .idle else { return }
        card.animateShape(
            to: idleCardFrame,
            bottomRadius: NotchShape.idleBottomRadius,
            duration: 0.26,
            timing: CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        )
    }

    /// Something happened worth noticing — a track started, a video began, an activity
    /// settled — so the bar takes a couple of breaths and is still again. It is never a
    /// standing animation: the bar moving all the time would say nothing.
    func breathe(cycles: Int = NotchBreath.cycles) {
        guard presentation == .idle, activityBarWidth == nil else { return }
        Log.ui.notice("Resting bar breath: \(cycles, privacy: .public) cycle(s)")
        card.breathe(cycles: cycles)
    }

    private func popIdleShape() {
        card.popShape(
            to: idleCardFrame,
            bottomRadius: NotchShape.idleBottomRadius,
            overshoot: 12,
            duration: 0.5
        )
    }

    /// Opens a pane from a keyboard shortcut and puts the cursor where typing starts.
    func openForTyping(_ tab: PanelTab) {
        show(tab)
        DispatchQueue.main.async { [weak self] in
            switch tab {
            case .clipboard: self?.clipboardPane.focus()
            case .notes: self?.notesPane.focus()
            default: break
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    func stopCamera() {
        mirrorPane.stopIfNeeded()
        systemPane.stopTracking()
    }

    /// Preview hook: pick a pane without going through a click.
    func selectTabForPreview(_ tab: PanelTab) {
        show(tab)
        present(.expanded, animated: false)
    }

    /// The resting bar's meter, for the self-test.
    var idleMeter: LevelMeterView { idleContent.levelMeter }

    /// The material the surface was built with, so the controller can tell whether a
    /// settings change actually needs a rebuild.
    var themeID: String { card.themeID }

    func applySurfaceTint(_ color: NSColor) {
        card.applySurfaceTint(color)
    }

    /// Picks up edited playlists, shortcuts and apps without rebuilding anything.
    /// New banner arrived while the pane is open.
    func refreshNotifications() {
        if selectedTab == .home { widgetRow.refreshNotifications() }
        guard selectedTab == .notifications else { return }
        notificationsPane.reload()
    }

    func reloadLists() {
        playlistsPane.reload()
        shortcutsPane.reload()
        appsPane.reload()
        rebuildZones()
    }

    func refreshPanes() {
        appsPane.refreshRunningStates()
    }

    // MARK: - Dropping files on the notch

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              urls.isEmpty == false else { return false }

        FileTray.shared.add(urls)
        // Dropped files land on the Shelf, so that is where the panel opens.
        show(.shelf)
        onFilesDropped?()
        return true
    }

    // MARK: - Frames

    /// Exactly the notch, where the hardware hides the slab completely.
    /// Exactly the notch. The slab's body is inset by its flare, so at this size the
    /// whole shape sits behind the hardware — which is what lets the resting bar and
    /// the panel grow *out of* the notch instead of fading in beside it.
    private var collapsedCardFrame: CGRect {
        CGRect(
            x: (bounds.width - notchWidth) / 2,
            y: bounds.height - bandHeight,
            width: notchWidth,
            height: bandHeight
        )
    }

    /// The flare the resting bar actually gets. `NotchShape` clamps it by height, and
    /// the bar is far shorter than the panel, so its straight body reaches further out
    /// than a plain `topFlare` inset would suggest.
    private var idleFlare: CGFloat {
        min(NotchShape.topFlare, (bandHeight + PanelSizes.restingExtraHeight) * 0.55)
    }

    private var idleCardFrame: CGRect {
        let resting = notchWidth + (NotchShape.topFlare + Metrics.idleWing) * 2
        // An activity widens the bar to whatever it needs to be readable, but never
        // past the panel it would otherwise open into.
        let needed = activityBarWidth.map { $0 + idleFlare * 2 } ?? 0
        let width = min(bounds.width, max(resting, needed))
        let extra = PanelSizes.restingExtraHeight
        return CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - bandHeight - extra,
            width: width,
            height: bandHeight + extra
        )
    }

    /// The straight part of the resting bar, which is all the content may use.
    private var idleBodyWidth: CGFloat {
        max(notchWidth, idleCardFrame.width - idleFlare * 2)
    }

    /// Where the notch sits inside the preview canvas and the idle bar.
    var notchSpan: CGFloat { notchWidth }

    private var expandedCardFrame: CGRect {
        CGRect(origin: .zero, size: bounds.size)
    }

    // MARK: - Presentation

    func present(_ presentation: Presentation, animated: Bool = true) {
        guard self.presentation != presentation else { return }
        self.presentation = presentation

        let targetFrame: CGRect
        let cardAlpha: CGFloat
        switch presentation {
        case .hidden:
            targetFrame = collapsedCardFrame
            cardAlpha = 0
        case .idle:
            targetFrame = idleCardFrame
            cardAlpha = 1
            // Content lays itself out inside the bar's straight body, not inside the
            // whole panel — anything wider is cut off by the slab's mask.
            idleContent.barWidth = idleBodyWidth
        case .expanded:
            targetFrame = expandedCardFrame
            cardAlpha = 1
        }

        // Every transition is a morph between two rects centred on the notch — hidden,
        // resting bar and full panel all behave identically. Direction is decided by
        // area, so resting bar → panel and hidden → resting bar both count as growing.
        let current = card.presentedShapeBounds ?? card.shapeRect
        let growing = targetFrame.width * targetFrame.height > current.width * current.height
        let duration: CFTimeInterval = animated ? (growing ? 0.38 : 0.28) : 0
        // Cubic ease-out for growing: the old curve covered two thirds of the distance in
        // the first 40ms, which read as a pop on the small resting bar. Closing eases in
        // and out so the shrink is actually seen.
        let timing = growing
            ? CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
            : CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)

        if presentation == .expanded { headerActions.refreshBattery() }

        let incoming: NSView? = presentation == .expanded ? expandedContent
            : presentation == .idle ? idleContent
            : nil
        let outgoing: [NSView] = [expandedContent, idleContent].filter { $0 !== incoming }

        // The surface is fully visible for the whole morph; it starts and ends behind
        // the notch, so there is nothing to fade in.
        if presentation != .hidden {
            card.alphaValue = 1
        }

        // A breath belongs to the resting bar alone. Leaving it — for the panel, or for
        // nothing at all — drops any burst still owed rather than animating a shape
        // that is on its way somewhere else.
        if presentation != .idle { card.cancelBreathing() }

        let radius = presentation == .expanded ? NotchShape.bottomRadius : NotchShape.idleBottomRadius
        if presentation == .idle, activityBarWidth != nil, growing, animated {
            // An activity arriving from behind the notch pops out rather than easing out.
            card.popShape(to: targetFrame, bottomRadius: radius, overshoot: 12, duration: 0.5)
        } else {
            card.animateShape(to: targetFrame, bottomRadius: radius, duration: duration, timing: timing)
        }

        let apply = { (view: NSView) -> NSView in animated ? view.animator() : view }

        // Leaving content goes quickly, so the shrinking shape never squeezes it.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? duration * 0.4 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            outgoing.forEach { apply($0).alphaValue = 0 }
        }

        // Arriving content waits until the shape has made room for it.
        if let incoming {
            let reveal = { [weak self] in
                guard let self, self.presentation == presentation else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = animated ? duration * 0.55 : 0
                    context.timingFunction = timing
                    apply(incoming).alphaValue = 1
                }
            }
            if animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration * (growing ? 0.3 : 0.5), execute: reveal)
            } else {
                reveal()
            }
        }

        // Only once the shape has shrunk back into the notch does the surface go.
        if presentation == .hidden {
            let fade = { [weak self] in
                guard let self, self.presentation == .hidden else { return }
                self.card.alphaValue = 0
            }
            if animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: fade)
            } else {
                fade()
            }
        }
    }

    // MARK: - Rendering

    func renderNowPlaying(_ state: NowPlayingState) {
        switch state {
        case .track(let track):
            hasTrack = true
            loadArtwork(track)
            idleContent.update(artwork: artwork, isPlaying: track.isPlaying)

        case .external(let source):
            // Whatever is making the sound, shown as itself: the site's icon for a video
            // in a browser, the app's icon for a call. Nothing here is controllable.
            hasTrack = false
            artworkKey = nil
            artwork = source.displayIcon
            idleContent.update(artwork: artwork, isPlaying: true)

        case .message:
            hasTrack = false
            artworkKey = nil
            artwork = nil
            // Nothing named is playing, but the speakers may still be busy.
            idleContent.update(artwork: nil, isPlaying: isAudioPlaying)
        }

        mediaDetail.render(state)
        widgetRow.render(state)
        refreshPanes()
    }

    private func loadArtwork(_ track: TrackInfo) {
        let key = track.artworkURL?.absoluteString ?? "app:\(track.sourceBundleIdentifier)"
        guard artworkKey != key else { return }
        artworkKey = key

        guard let url = track.artworkURL else {
            let icon = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: track.sourceBundleIdentifier)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            artwork = icon
            idleContent.update(artwork: icon, isPlaying: track.isPlaying)
            if let icon { applyArtworkTint(from: icon, key: key) }
            return
        }

        ArtworkLoader.shared.load(url) { [weak self] image in
            // A later track may have won the race while this download was in flight.
            guard let self, self.artworkKey == key else { return }
            self.artwork = image
            self.idleContent.update(artwork: image, isPlaying: track.isPlaying)
            if let image { self.applyArtworkTint(from: image, key: key) }
        }
    }

    /// Themes that follow the artwork recolour here rather than rebuilding the panel.
    private func applyArtworkTint(from image: NSImage, key: String) {
        guard ThemeStore.selected.followsArtwork,
              let color = ArtworkColor.panelColor(from: image, key: key) else { return }
        ThemeStore.artworkColor = color
        card.applySurfaceTint(color)
    }

    func setPendingCount(_ count: Int) {
        headerActions.setPendingCount(count)
    }

    func showMedia() {
        show(.home)
    }

    /// The widget list changed in settings.
    func rebuildZones() {
        widgetRow.rebuild()
        if selectedTab == .home {
            install(widgetRow)
        }
    }

    func showApp(_ details: AppDetails) {
        mode = .app
        headerTabs.select(nil, notify: false)
        headerActions.setOpen(nil)
        appDetail.render(details)
        install(appDetail)
    }

    func showPermission(_ request: PermissionRequest, queued: Int) {
        mode = .permission
        headerTabs.select(nil, notify: false)
        headerActions.setOpen(nil)
        permissionDetail.render(request: request, queued: queued)
        install(permissionDetail)
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
