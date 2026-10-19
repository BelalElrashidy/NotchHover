import AppKit

/// Scroll documents draw from the top only when the view is flipped.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension Notification.Name {
    /// Posted when settings change so the panel can pick them up without a relaunch.
    static let notchHoverSettingsChanged = Notification.Name("NotchHoverSettingsChanged")
    /// Posted by the notch's gear button; an action id as the object opens Shortcuts on it.
    static let notchHoverOpenSettings = Notification.Name("NotchHoverOpenSettings")
}

/// Settings, laid out like System Settings: a sidebar of coloured icons in groups, with
/// search, and the chosen pane beside it. Appearance and Layout keep a live picture of
/// the notch pinned on top — Bartender's menu bar preview — and every row says what it
/// does, the way Linear's settings do. Everything saves as it changes.
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSSearchFieldDelegate {
    enum Category: Int, CaseIterable {
        case appearance, layout
        case music, calendar, clipboard, files, launchers
        case shortcuts, gestures, notifications
        case privacy, about

        var title: String {
            switch self {
            case .appearance: return "Appearance"
            case .layout: return "Layout"
            case .music: return "Music"
            case .calendar: return "Calendar and calls"
            case .clipboard: return "Clipboard"
            case .files: return "Shelf and screenshots"
            case .launchers: return "Launchers"
            case .shortcuts: return "Shortcuts"
            case .gestures: return "Gestures and haptics"
            case .notifications: return "Notifications"
            case .privacy: return "Privacy and permissions"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .layout: return "rectangle.split.3x1.fill"
            case .music: return "music.note"
            case .calendar: return "calendar"
            case .clipboard: return "doc.on.clipboard.fill"
            case .files: return "tray.full.fill"
            case .launchers: return "square.grid.2x2.fill"
            case .shortcuts: return "command"
            case .gestures: return "hand.tap.fill"
            case .notifications: return "bell.badge.fill"
            case .privacy: return "hand.raised.fill"
            case .about: return "info"
            }
        }

        var color: NSColor {
            switch self {
            case .appearance: return .systemPurple
            case .layout: return .systemBlue
            case .music: return .systemRed
            case .calendar: return .systemOrange
            case .clipboard: return .systemGray
            case .files: return .systemTeal
            case .launchers: return .systemIndigo
            case .shortcuts: return NSColor(white: 0.35, alpha: 1)
            case .gestures: return .systemPink
            case .notifications: return .systemRed
            case .privacy: return .systemBlue
            case .about: return NSColor(white: 0.45, alpha: 1)
            }
        }

        /// Groups are separated by a gap, as in System Settings.
        var startsGroup: Bool { [.music, .shortcuts, .privacy].contains(self) }

        /// Words a search should find this pane by.
        var keywords: String {
            switch self {
            case .appearance: return "theme colour color resting bar hover peek visualizer dark light glass"
            case .layout: return "widgets home panel size width height corner flare text"
            case .music: return "spotify playlists lyrics lock screen visualizer"
            case .calendar: return "meetings zoom meet teams join mute camera"
            case .clipboard: return "history paste pin boards"
            case .files: return "shelf drop files screenshots capture folder"
            case .launchers: return "apps shortcuts launcher"
            case .shortcuts: return "hotkeys keyboard keys quicklinks scripts commands"
            case .gestures: return "trackpad swipe haptic feedback hover delay"
            case .notifications: return "banners speak aloud accessibility"
            case .privacy: return "permissions internet online lyrics accessibility bluetooth calendar screen recording"
            case .about: return "version update github license"
            }
        }

        var hasStage: Bool { self == .appearance || self == .layout }
    }

    private let sidebarStack = NSStackView()
    private let search = NSSearchField()
    private let stage = NotchStageView()
    private let paneScroll = NSScrollView()
    private let paneDocument = FlippedView()
    private var stageHeight: NSLayoutConstraint?
    private var sidebarRows: [Category: NSView] = [:]
    private var selected: Category = .appearance
    private var theme: Theme = ThemeStore.selected
    private var shortcutsView: ShortcutsSettingsView?
    private var editor: CustomActionEditor?

    /// Every Shortcut in the Shortcuts app, read once, for the Launchers pane's picker.
    private var installedShortcuts: [String] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchHover Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
        load()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        load()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Opening Settings shouldn't put the cursor in search.
        window?.makeFirstResponder(nil)
    }

    /// From ⌘E in the ⌘K list: the Shortcuts table, recording that action's hotkey.
    func show(focusingAction id: String) {
        show()
        select(.shortcuts)
        shortcutsView?.focus(on: id)
    }

    // MARK: - Window

    private func makeContent() -> NSView {
        let root = NSView()
        root.wantsLayer = true

        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.identifier = NSUserInterfaceItemIdentifier("sidebar")
        search.placeholderString = "Search"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 1
        [search, sidebarStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview($0)
        }

        let detail = NSView()
        paneScroll.documentView = paneDocument
        paneScroll.drawsBackground = false
        paneScroll.hasVerticalScroller = true
        paneScroll.automaticallyAdjustsContentInsets = false
        paneDocument.translatesAutoresizingMaskIntoConstraints = false
        [stage, paneScroll].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            detail.addSubview($0)
        }

        [sidebar, detail].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        stageHeight = stage.heightAnchor.constraint(equalToConstant: NotchStageView.height)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 224),
            // Room for the traffic lights above the search field.
            search.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 44),
            // The same edges as the rows under it.
            search.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            search.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            sidebarStack.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),

            detail.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detail.topAnchor.constraint(equalTo: root.topAnchor),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stage.topAnchor.constraint(equalTo: detail.topAnchor),
            stage.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            stageHeight!,
            paneScroll.topAnchor.constraint(equalTo: stage.bottomAnchor),
            paneScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            paneScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            paneScroll.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
            paneDocument.leadingAnchor.constraint(equalTo: paneScroll.contentView.leadingAnchor),
            paneDocument.trailingAnchor.constraint(equalTo: paneScroll.contentView.trailingAnchor),
            paneDocument.topAnchor.constraint(equalTo: paneScroll.contentView.topAnchor)
        ])
        return root
    }

    private func applyTheme() {
        theme = ThemeStore.selected
        SettingsStyle.themeOverride = theme
        guard let root = window?.contentView else { return }
        window?.appearance = theme.appearance
        window?.backgroundColor = theme.windowBackground
        root.layer?.backgroundColor = theme.windowBackground.cgColor
        root.subviews.first { $0.identifier?.rawValue == "sidebar" }?.layer?.backgroundColor = theme.elevatedBackground.cgColor
        stage.theme = theme
        rebuildSidebar()
        select(selected)
    }

    // MARK: - Sidebar

    private func rebuildSidebar() {
        sidebarStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sidebarRows = [:]
        let query = search.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        let matches = Category.allCases.filter {
            query.isEmpty || "\($0.title) \($0.keywords)".lowercased().contains(query)
        }
        for category in matches {
            if category.startsGroup, query.isEmpty {
                let gap = NSView()
                gap.heightAnchor.constraint(equalToConstant: 10).isActive = true
                sidebarStack.addArrangedSubview(gap)
            }
            let row = SidebarRow(category: category, isSelected: category == selected, theme: theme)
            row.onSelect = { [weak self] in self?.select(category) }
            sidebarStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
            sidebarRows[category] = row
        }
        if matches.isEmpty {
            let none = NSTextField(labelWithString: "No settings match")
            none.textColor = theme.tertiaryText
            sidebarStack.addArrangedSubview(none)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        rebuildSidebar()
    }

    /// ↩ in search opens the first match.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let query = search.stringValue.lowercased()
        if let first = Category.allCases.first(where: { "\($0.title) \($0.keywords)".lowercased().contains(query) }) {
            select(first)
        }
        return true
    }

    // MARK: - Panes

    func select(_ category: Category) {
        selected = category
        for (candidate, row) in sidebarRows {
            (row as? SidebarRow)?.isSelected = candidate == category
        }
        // Collapsed rather than hidden: a hidden layer-backed stage left the whole window
        // drawing blank in snapshots.
        stageHeight?.constant = category.hasStage ? NotchStageView.height : 1
        if category.hasStage { stage.refresh() }

        paneDocument.subviews.forEach { $0.removeFromSuperview() }
        let pane = makePane(category)
        pane.translatesAutoresizingMaskIntoConstraints = false
        paneDocument.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: paneDocument.leadingAnchor, constant: 28),
            pane.trailingAnchor.constraint(equalTo: paneDocument.trailingAnchor, constant: -28),
            pane.topAnchor.constraint(equalTo: paneDocument.topAnchor, constant: category.hasStage ? 18 : 44),
            pane.bottomAnchor.constraint(equalTo: paneDocument.bottomAnchor, constant: -28)
        ])
        paneScroll.contentView.scroll(to: .zero)
    }

    private func page(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func makePane(_ category: Category) -> NSView {
        switch category {
        case .appearance: return appearancePane()
        case .layout: return layoutPane()
        case .music: return musicPane()
        case .calendar: return calendarPane()
        case .clipboard: return clipboardPane()
        case .files: return filesPane()
        case .launchers: return launchersPane()
        case .shortcuts: return shortcutsPane()
        case .gestures: return gesturesPane()
        case .notifications: return notificationsPane()
        case .privacy: return privacyPane()
        case .about: return aboutPane()
        }
    }

    // MARK: Appearance

    private func appearancePane() -> NSView {
        let cards = Theme.all.map { candidate -> NSView in
            let card = ThemeCard(theme: candidate, isSelected: candidate.id == theme.id)
            card.onPick = { [weak self] in
                UserDefaults.standard.set(candidate.id, forKey: ThemeStore.defaultsKey)
                self?.saved()
                self?.applyTheme()
            }
            return card
        }
        // Three to a row, filling the page: a picture the shape of the panel, and its name.
        let themes = EqualGrid(items: cards, columns: 3, spacing: 12) { width in width * ThemeCard.aspect + 24 }

        let resting = ["always", "playing", "never"]
        let restingIndex = resting.firstIndex(of: UserDefaults.standard.string(forKey: "RestingBar") ?? "playing") ?? 1
        let delays: [Double] = [0, 0.15, 0.3, 0.5, 0.8]
        let delay = UserDefaults.standard.object(forKey: "HoverDelay") as? Double ?? 0.3

        return page([
            SettingsKit.header("Appearance", "How the notch looks, and how it answers when you come near it."),
            labelled("Theme", themes),
            SettingsKit.section("Behaviour", rows: [
                SettingsKit.popup("Resting bar", detail: "The strip beside the notch between uses", options: ["Always", "While playing", "Never"],
                                  selected: restingIndex) { [weak self] index in
                    UserDefaults.standard.set(resting[index], forKey: "RestingBar")
                    self?.saved()
                },
                SettingsKit.popup("On hover", detail: "What resting the pointer on the notch does", options: ["Peek first", "Open the panel"],
                                  selected: UserDefaults.standard.string(forKey: "HoverAction") == "open" ? 1 : 0) { [weak self] index in
                    UserDefaults.standard.set(index == 1 ? "open" : "peek", forKey: "HoverAction")
                    self?.saved()
                },
                SettingsKit.popup("Hover delay", detail: "How long the pointer rests before anything opens", options: ["None", "0.15 s", "0.3 s", "0.5 s", "0.8 s"],
                                  selected: delays.firstIndex { abs($0 - delay) < 0.01 } ?? 2) { [weak self] index in
                    UserDefaults.standard.set(delays[index], forKey: "HoverDelay")
                    self?.saved()
                },
                SettingsKit.toggle("Live visualizer", detail: "The bars move with the music itself, in the artwork's colour. Nothing is recorded.",
                                   badge: .asks("System Audio Recording"), isOn: AudioLevels.isEnabled) { AudioLevels.isEnabled = $0 }
            ])
        ])
    }

    private func labelled(_ title: String, _ view: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = theme.secondaryText
        let stack = NSStackView(views: [label, view])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // MARK: Layout

    private func layoutPane() -> NSView {
        let canvas = PanelCanvasView()
        canvas.heightAnchor.constraint(equalToConstant: 128).isActive = true
        canvas.onChange = { [weak self] in
            self?.saved()
            self?.stage.refresh()
            self?.select(.layout)
        }

        let unused = PanelWidget.allCases.filter { PanelLayoutStore.widgets.contains($0) == false }
        let tiles = unused.map { widget -> NSView in
            let tile = WidgetGalleryTile(widget: widget)
            tile.onAdd = { canvas.append(widget) }
            return tile
        }
        let gallery = EqualGrid(items: tiles, minItemWidth: 100, spacing: 10) { _ in 60 }

        func size(_ title: String, _ detail: String?, key: String, value: CGFloat, range: ClosedRange<Double>, unit: String, scale: Double = 1) -> NSView {
            SettingsKit.row(title, detail: detail, control: SettingsKit.slider(value: Double(value) * scale, range: range, format: { "\(Int($0.rounded()))\(unit)" }) { [weak self] newValue in
                UserDefaults.standard.set(newValue / scale, forKey: key)
                self?.saved()
                self?.stage.refresh()
            })
        }

        return page([
            SettingsKit.header("Layout", "Home's widgets, as they sit in the panel. Drag one sideways to move it, hover for × to take it out, drag one in from below."),
            canvas,
            labelled(unused.isEmpty ? "Every widget is in the panel" : "More widgets", gallery),
            SettingsKit.section("Size", footer: "The panel fits its widgets unless the width is fixed.", rows: [
                SettingsKit.popup("Panel width", options: ["Fits the widgets", "Fixed"], selected: PanelSizes.usesAutomaticWidth ? 0 : 1) { [weak self] index in
                    UserDefaults.standard.set(index == 0 ? "auto" : "fixed", forKey: PanelSizes.Key.widthMode)
                    self?.saved()
                    self?.stage.refresh()
                },
                size("Fixed width", nil, key: PanelSizes.Key.width, value: PanelSizes.width, range: 420...1400, unit: "pt"),
                size("Height", nil, key: PanelSizes.Key.height, value: PanelSizes.height, range: 110...320, unit: "pt"),
                size("Corner radius", nil, key: PanelSizes.Key.cornerRadius, value: PanelSizes.cornerRadius, range: 12...48, unit: "pt"),
                size("Flare", "The curve where the panel meets the menu bar", key: PanelSizes.Key.flare, value: PanelSizes.flare, range: 0...60, unit: "pt"),
                size("Resting bar sides", nil, key: PanelSizes.Key.restingWing, value: PanelSizes.restingWing, range: 0...200, unit: "pt"),
                size("Resting bar drop", nil, key: PanelSizes.Key.restingExtraHeight, value: PanelSizes.restingExtraHeight, range: 0...40, unit: "pt"),
                size("Text size", nil, key: PanelSizes.Key.typeScale, value: PanelSizes.typeScale, range: 85...130, unit: "%", scale: 100)
            ])
        ])
    }

    // MARK: Music

    private func musicPane() -> NSView {
        page([
            SettingsKit.header("Music", "Spotify and Apple Music, read and controlled on your Mac."),
            SettingsKit.section("Extras", rows: [
                SettingsKit.toggle("Synced lyrics", detail: "The line being sung, in the peek and Now Playing. Each song's title, artist, album and length go to lrclib.net once; nothing else.",
                                   badge: .internet, isOn: LyricsService.isEnabled) { LyricsService.isEnabled = $0 },
                SettingsKit.toggle("Live visualizer", detail: "The bars follow the music itself. Not used on Bluetooth headphones.",
                                   badge: .asks("System Audio Recording"), isOn: AudioLevels.isEnabled) { AudioLevels.isEnabled = $0 },
                SettingsKit.toggle("Music on the lock screen", detail: LockScreenSpace.shared.isAvailable
                                   ? "Artwork, play, pause and skip while the Mac is locked. Anyone at your Mac can see the song."
                                   : "Not available on this version of macOS.",
                                   isOn: LockScreenMusic.isEnabled) { LockScreenMusic.isEnabled = $0 }
            ]),
            SettingsKit.section("Playlists", footer: "Paste a Spotify link or URI. Pinned playlists play from the notch's Playlists card.", rows: playlistRows())
        ])
    }

    // MARK: Calendar and calls

    private func calendarPane() -> NSView {
        let calendar = CalendarService.shared
        let access: NSView = calendar.isAuthorized
            ? SettingsKit.status("Allowed", good: true)
            : SettingsKit.button(calendar.isDenied ? "Open System Settings" : "Allow access", prominent: true) { [weak self] in
                Permission.calendars.request()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.select(.calendar) }
            }
        return page([
            SettingsKit.header("Calendar and calls", "Your schedule in the panel, a Join button on every call, and the call's controls while you're on it."),
            SettingsKit.section("Calendar", rows: [
                SettingsKit.row("Calendar access", detail: "Read only, on this Mac. Zoom, Meet, Teams, FaceTime and Webex links get a Join button.", control: access),
                SettingsKit.row("Before a call", detail: "The notch pops two minutes before a call with a link, and ⌘J joins it.")
            ]),
            SettingsKit.section("On a call", footer: "Google Meet needs one switch in your browser: in Chrome, View → Developer → Allow JavaScript from Apple Events; in Safari, Settings → Advanced, then Develop → Allow JavaScript from Apple Events.", rows: [
                SettingsKit.row("Mute, camera and leave", detail: "In the peek during a Zoom, Teams, Webex or Google Meet call. ⌃⌥M mutes from anywhere.",
                                control: SettingsKit.status(AXIsProcessTrusted() ? "Ready" : "Needs Accessibility", good: AXIsProcessTrusted()))
            ])
        ])
    }

    // MARK: Clipboard

    private func clipboardPane() -> NSView {
        page([
            SettingsKit.header("Clipboard", "Everything you copy, searchable from the notch, with boards for what you reuse."),
            SettingsKit.section(nil, footer: "Copies from password managers are never recorded.", rows: [
                SettingsKit.toggle("Record clipboard history", detail: "Kept in your Application Support folder, readable only by you.", badge: .onThisMac,
                                   isOn: ClipboardHistory.shared.isPaused == false) { ClipboardHistory.shared.isPaused = $0 == false },
                SettingsKit.row("Clear history", detail: "Pinned clips and clips on a board stay.",
                                control: SettingsKit.button("Clear") { ClipboardHistory.shared.clear() })
            ])
        ])
    }

    // MARK: Shelf and screenshots

    private func filesPane() -> NSView {
        page([
            SettingsKit.header("Shelf and screenshots", "Files held on the notch, things to do with them, and the screenshots you take."),
            SettingsKit.section("Shelf", rows: [
                SettingsKit.row("Drop zones", detail: "Drag files to the notch: drop on Shelf, AirDrop, a conversion, Zip or Copy text. Everything is done on your Mac."),
                SettingsKit.row("New files", detail: "Converted, resized or zipped files go beside the originals, never over them.")
            ]),
            SettingsKit.section("Screenshots", rows: [
                SettingsKit.row("Screenshots folder", detail: ScreenshotStore.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + " — change it in the Screenshot app's Options",
                                control: SettingsKit.button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ScreenshotStore.folder]) }),
                SettingsKit.row("Capture from the notch", detail: "⌃⌥4 for an area, or the buttons in the Screenshots view.",
                                control: SettingsKit.status(CGPreflightScreenCaptureAccess() ? "Allowed" : "Asks the first time", good: CGPreflightScreenCaptureAccess() ? true : nil))
            ])
        ])
    }

    // MARK: Launchers

    private func launchersPane() -> NSView {
        page([
            SettingsKit.header("Launchers", "Apps and macOS Shortcuts one click away in the notch. For keys and your own actions, see Shortcuts."),
            SettingsKit.section("Apps", footer: "Up to eight, in this order.", rows: appRows()),
            SettingsKit.section("macOS Shortcuts", footer: "Run from the notch's Shortcuts card.", rows: shortcutRows())
        ])
    }

    // MARK: Shortcuts

    private func shortcutsPane() -> NSView {
        let table = ShortcutsSettingsView()
        table.onEditCustom = { [weak self] action in self?.edit(action) }
        shortcutsView = table
        return page([
            SettingsKit.header("Shortcuts", "Every action NotchHover has, built in and your own. ⌘K in the panel runs any of them."),
            table
        ])
    }

    private func edit(_ action: CustomAction?) {
        let editor = CustomActionEditor(action: action)
        editor.onSave = { CustomActionStore.shared.save($0) }
        self.editor = editor
        if let sheet = editor.window { window?.beginSheet(sheet) }
    }

    // MARK: Gestures and haptics

    private func gesturesPane() -> NSView {
        page([
            SettingsKit.header("Gestures and haptics", "Two fingers on the trackpad, and a tap back when something happens."),
            SettingsKit.section(nil, rows: [
                SettingsKit.toggle("Trackpad gestures", detail: "Two fingers down on the notch to open it, up to close, sideways to change tab — or, on the resting bar, the track.",
                                   isOn: SwipeRecognizer.isEnabled) { UserDefaults.standard.set($0, forKey: "TrackpadGestures") },
                SettingsKit.toggle("Haptic feedback", detail: "A tap from a Force Touch trackpad when the panel opens, a tab changes or a swipe lands.",
                                   isOn: Haptics.isEnabled) { UserDefaults.standard.set($0, forKey: "Haptics") }
            ])
        ])
    }

    // MARK: Notifications

    private func notificationsPane() -> NSView {
        let trusted = NotificationWatcher.isTrusted
        return page([
            SettingsKit.header("Notifications", "Banners from other apps, mirrored into the notch."),
            SettingsKit.section(nil, rows: [
                SettingsKit.row("Mirror notification banners", detail: "Read from the banners on screen with Accessibility.",
                                control: trusted ? SettingsKit.status("On", good: true) : SettingsKit.button("Allow", prominent: true) { [weak self] in
                                    NotificationWatcher.requestTrust()
                                    NotificationWatcher.openAccessibilitySettings()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.select(.notifications) }
                                }),
                SettingsKit.toggle("Speak notifications aloud", isOn: UserDefaults.standard.bool(forKey: "SpeakNotifications")) { [weak self] in
                    UserDefaults.standard.set($0, forKey: "SpeakNotifications")
                    self?.saved()
                }
            ])
        ])
    }

    // MARK: Privacy and permissions

    private func privacyPane() -> NSView {
        let permissions = Permission.allCases.map { permission -> NSView in
            let granted = permission.isGranted
            let control: NSView = granted == true
                ? SettingsKit.status("Allowed", good: true)
                : SettingsKit.group([
                    SettingsKit.status(granted == false ? "Not allowed" : "Asked when needed", good: granted == false ? false : nil),
                    SettingsKit.button(granted == nil ? "Open" : "Allow") { [weak self] in
                        permission.request()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.select(.privacy) }
                    }
                ])
            return SettingsKit.row(permission.title, detail: permission.reason, control: control)
        }
        return page([
            SettingsKit.header("Privacy and permissions", "Everything stays on your Mac. These are the only exceptions, and they're off until you turn them on."),
            SettingsKit.section("Goes beyond your Mac", rows: [
                SettingsKit.toggle("Synced lyrics", detail: "Title, artist, album and length of each song, to lrclib.net, once.", badge: .internet,
                                   isOn: LyricsService.isEnabled) { LyricsService.isEnabled = $0 },
                SettingsKit.row("Spotify artwork", detail: "Spotify only hands out cover art as a link, so it's fetched from Spotify's image server. No account details are sent.")
            ]),
            SettingsKit.section("Permissions", footer: "Each is asked for only when you first use what needs it.", rows: permissions)
        ])
    }

    // MARK: About

    private func aboutPane() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let name = NSTextField(labelWithString: "NotchHover")
        name.font = .systemFont(ofSize: 26, weight: .bold)
        name.textColor = theme.primaryText
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let line = NSTextField(labelWithString: "Version \(version) · free and open source under GPL-3.0")
        line.textColor = theme.secondaryText
        let repo = "https://github.com/BelalElrashidy/NotchHover"
        func link(_ title: String, _ path: String) -> NSButton {
            SettingsKit.button(title) { if let url = URL(string: repo + path) { NSWorkspace.shared.open(url) } }
        }
        let buttons = SettingsKit.group([
            link("GitHub", ""),
            link("What's new", "/blob/main/CHANGELOG.md"),
            link("Releases", "/releases"),
            link("Report a problem", "/issues/new"),
            SettingsKit.button("Quit NotchHover") { NSApp.terminate(nil) }
        ])
        let hero = NSStackView(views: [icon, name, line, buttons])
        hero.orientation = .vertical
        hero.spacing = 10
        hero.setCustomSpacing(18, after: line)
        let privacy = NSTextField(wrappingLabelWithString: "No account, no analytics, no telemetry. Updates are on GitHub's Releases page; NotchHover never checks for them itself.")
        privacy.textColor = theme.tertiaryText
        privacy.alignment = .center
        return page([hero, privacy])
    }

    // MARK: - Saving

    private func load() {
        applyTheme()
        if installedShortcuts.isEmpty {
            ShortcutsRunner.allNames { [weak self] names in
                self?.installedShortcuts = names
                if self?.selected == .launchers { self?.select(.launchers) }
            }
        }
    }

    // MARK: - Lists

    /// Name and link for each pinned playlist, saved as you leave a field.
    private func playlistRows() -> [NSView] {
        var entries: [(name: String, link: String)] = (UserDefaults.standard.stringArray(forKey: PlaylistsPaneView.defaultsKey) ?? [])
            .compactMap { entry in
                let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }
        func store() {
            let lines = entries.compactMap { entry -> String? in
                guard entry.name.isEmpty == false, let uri = SpotifyURI.normalize(entry.link) else { return nil }
                return "\(entry.name)|\(uri)"
            }
            UserDefaults.standard.set(lines, forKey: PlaylistsPaneView.defaultsKey)
            saved()
        }
        var rows: [NSView] = entries.enumerated().map { index, entry in
            let name = SettingsKit.field(entry.name, placeholder: "Name", width: 150) { entries[index].name = $0; store() }
            let link = SettingsKit.field(entry.link, placeholder: "https://open.spotify.com/playlist/…", width: nil) { entries[index].link = $0; store() }
            let remove = SettingsKit.button("Remove") { [weak self] in
                entries.remove(at: index)
                store()
                self?.select(.music)
            }
            return SettingsKit.fieldRow([name, link, remove])
        }
        rows.append(SettingsKit.row(entries.isEmpty ? "No playlists yet" : "Another playlist",
                                    control: SettingsKit.button("Add playlist") { [weak self] in
            entries.append(("", ""))
            UserDefaults.standard.set(entries.map { "\($0.name)|\($0.link)" }, forKey: PlaylistsPaneView.defaultsKey)
            self?.select(.music)
        }))
        return rows
    }

    /// The launcher's apps, each with its icon, and a picker to add one.
    private func appRows() -> [NSView] {
        var identifiers = UserDefaults.standard.stringArray(forKey: AppShortcutStore.defaultsKey)
            ?? AppShortcutStore.shortcuts().map(\.bundleIdentifier)
        func store() {
            UserDefaults.standard.set(identifiers, forKey: AppShortcutStore.defaultsKey)
            saved()
            select(.launchers)
        }
        var rows: [NSView] = identifiers.enumerated().map { index, identifier in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? identifier
            let remove = SettingsKit.button("Remove") {
                identifiers.remove(at: index)
                store()
            }
            return SettingsKit.iconRow(url.map { NSWorkspace.shared.icon(forFile: $0.path) }, title: name, control: remove)
        }
        rows.append(SettingsKit.row(identifiers.isEmpty ? "No apps yet" : "Another app", control: SettingsKit.button("Add app…") {
            let panel = NSOpenPanel()
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            guard panel.runModal() == .OK, let url = panel.url, let identifier = Bundle(url: url)?.bundleIdentifier,
                  identifiers.contains(identifier) == false else { return }
            identifiers.append(identifier)
            store()
        }))
        return rows
    }

    /// Pinned macOS Shortcuts, chosen from the ones you have.
    private func shortcutRows() -> [NSView] {
        var names = UserDefaults.standard.stringArray(forKey: ShortcutsRunner.defaultsKey) ?? []
        func store() {
            UserDefaults.standard.set(names, forKey: ShortcutsRunner.defaultsKey)
            saved()
            select(.launchers)
        }
        var rows: [NSView] = names.enumerated().map { index, name in
            SettingsKit.iconRow(NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil), title: name,
                                control: SettingsKit.button("Remove") {
                names.remove(at: index)
                store()
            })
        }
        let available = installedShortcuts.filter { names.contains($0) == false }
        let picker = MenuButton(titles: ["Add a Shortcut"] + available)
        picker.onSelect = { index in
            guard index > 0 else { return }
            names.append(available[index - 1])
            store()
        }
        rows.append(SettingsKit.row(installedShortcuts.isEmpty ? "No Shortcuts found in the Shortcuts app" : "Pin one",
                                    control: installedShortcuts.isEmpty ? nil : picker))
        return rows
    }

    /// Every control calls this the moment it changes; there is no Save button.
    private func saved() {
        NotificationCenter.default.post(name: .notchHoverSettingsChanged, object: nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Fields save as they lose focus; ending editing here saves the one in use.
        window?.makeFirstResponder(nil)
        SettingsStyle.themeOverride = nil
    }

    // MARK: - Self-test

    /// Exercises the window without a pointer: --settings-selftest
    func runSelfTest() {
        func report(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        let order = ProcessInfo.processInfo.environment["SETTINGS_REVERSED"] == nil ? Category.allCases : Category.allCases.reversed()
        for category in order {
            select(category)
            window?.contentView?.layoutSubtreeIfNeeded()
            report("pane \(category.title): \(paneDocument.subviews.first?.fittingSize.height ?? 0 > 40 ? "built" : "EMPTY")")
            let target = ProcessInfo.processInfo.environment["SETTINGS_PANE_ONLY"] == nil ? window?.contentView : paneDocument
            guard let content = target, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
            report("  size \(content.bounds.size), document \(paneDocument.frame.size), scroll \(paneScroll.frame.size)")
            // Drawn in the window's own appearance: system colours resolve light otherwise.
            let image = NSImage(size: content.bounds.size)
            (window?.effectiveAppearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
                content.cacheDisplay(in: content.bounds, to: rep)
                image.lockFocus()
                theme.windowBackground.setFill()
                NSRect(origin: .zero, size: content.bounds.size).fill()
                rep.draw(in: NSRect(origin: .zero, size: content.bounds.size))
                image.unlockFocus()
            }
            let path = NSTemporaryDirectory() + "notchhover-settings-\(category.rawValue)-\(category.title.lowercased().replacingOccurrences(of: " ", with: "-")).png"
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                report("wrote \(path)")
            }
        }
        // The shortcut editor sheet, with a few steps in it.
        let editor = CustomActionEditor(action: CustomAction(id: UUID(), name: "Start work", symbol: "briefcase.fill", steps: [
            .openApp("/System/Applications/Notes.app"), .openURL("https://github.com/search?q={query}"), .shell("cd ~/Coding && git pull"), .wait(1)
        ]))
        if let content = editor.window?.contentView {
            editor.window?.layoutIfNeeded()
            content.layoutSubtreeIfNeeded()
            if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                let image = NSImage(size: content.bounds.size)
                content.effectiveAppearance.performAsCurrentDrawingAppearance {
                    content.cacheDisplay(in: content.bounds, to: rep)
                    image.lockFocus()
                    theme.windowBackground.setFill()
                    NSRect(origin: .zero, size: content.bounds.size).fill()
                    rep.draw(in: NSRect(origin: .zero, size: content.bounds.size))
                    image.unlockFocus()
                }
                if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "notchhover-settings-editor.png"))
                    report("wrote editor")
                }
            }
        }

        search.stringValue = "lyrics"
        rebuildSidebar()
        report("search \"lyrics\" finds: \(sidebarRows.keys.map(\.title).sorted().joined(separator: ", "))")
        search.stringValue = ""
        rebuildSidebar()
    }
}

/// A sidebar entry: a coloured square with a white symbol, and the name.
private final class SidebarRow: NSView {
    var onSelect: (() -> Void)?
    var isSelected: Bool { didSet { refresh() } }
    private let title: NSTextField
    private let theme: Theme

    init(category: SettingsWindowController.Category, isSelected: Bool, theme: Theme) {
        self.isSelected = isSelected
        self.theme = theme
        title = NSTextField(labelWithString: category.title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        let square = NSView()
        square.wantsLayer = true
        square.layer?.cornerRadius = 5
        square.layer?.cornerCurve = .continuous
        square.layer?.backgroundColor = category.color.cgColor
        let symbol = NSImageView(image: NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) ?? NSImage())
        symbol.contentTintColor = .white
        symbol.translatesAutoresizingMaskIntoConstraints = false
        square.addSubview(symbol)
        title.font = .systemFont(ofSize: 13)

        let stack = NSStackView(views: [square, title])
        stack.spacing = 9
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            square.widthAnchor.constraint(equalToConstant: 20),
            square.heightAnchor.constraint(equalToConstant: 20),
            symbol.centerXAnchor.constraint(equalTo: square.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: square.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refresh() {
        layer?.backgroundColor = isSelected ? theme.accent.cgColor : NSColor.clear.cgColor
        title.textColor = isSelected ? theme.onAccentText : theme.primaryText
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onSelect?() }
}

/// A theme as a picture of the panel in it, ringed when chosen — Linear's theme tiles.
private final class ThemeCard: NSView {
    var onPick: (() -> Void)?

    /// Height over width of the pictures, so the frame fits them with no bands.
    static let aspect: CGFloat = {
        guard let sample = PreviewRenderer.snapshot(theme: Theme.all[0], width: 150), sample.size.width > 0 else { return 0.3 }
        return sample.size.height / sample.size.width
    }()

    init(theme candidate: Theme, isSelected: Bool) {
        super.init(frame: .zero)
        let theme = SettingsKit.theme
        let image = NSImageView(image: PreviewRenderer.snapshot(theme: candidate, width: 150) ?? NSImage())
        image.imageScaling = .scaleAxesIndependently
        image.wantsLayer = true
        image.layer?.cornerRadius = 8
        image.layer?.masksToBounds = true
        image.layer?.borderWidth = isSelected ? 2.5 : 0.5
        image.layer?.borderColor = (isSelected ? theme.accent : theme.primaryText.withAlphaComponent(0.15)).cgColor
        let name = NSTextField(labelWithString: candidate.name)
        name.font = .systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular)
        name.textColor = theme.primaryText
        let stack = NSStackView(views: [image, name])
        stack.orientation = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.alignment = .centerX
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalTo: stack.widthAnchor),
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: Self.aspect),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onPick?() }
}
