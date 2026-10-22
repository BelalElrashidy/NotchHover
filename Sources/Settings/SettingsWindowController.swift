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

    /// Room to read a pane without scrolling for most of them: most of the screen,
    /// short of filling it, and no smaller than the panes were laid out for.
    private static var defaultSize: NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        return NSSize(width: min(1240, max(960, visible.width * 0.72)),
                      height: min(900, max(680, visible.height * 0.86)))
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchHover Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 860, height: 600)
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
        // However you last left it, it opens that way again.
        window.setFrameAutosaveName("NotchHoverSettings")
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
            // A wide window keeps rows a readable width, centred, rather than stretching a
            // switch a whole screen away from its label.
            pane.leadingAnchor.constraint(greaterThanOrEqualTo: paneDocument.leadingAnchor, constant: 28),
            pane.centerXAnchor.constraint(equalTo: paneDocument.centerXAnchor),
            pane.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxPaneWidth),
            {
                let fill = pane.leadingAnchor.constraint(equalTo: paneDocument.leadingAnchor, constant: 28)
                fill.priority = .defaultHigh
                return fill
            }(),
            pane.topAnchor.constraint(equalTo: paneDocument.topAnchor, constant: category.hasStage ? 18 : 44),
            pane.bottomAnchor.constraint(equalTo: paneDocument.bottomAnchor, constant: -28)
        ])
        paneScroll.contentView.scroll(to: .zero)
    }

    private static let maxPaneWidth: CGFloat = 900

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

    /// The chosen theme's own adjustments: how see-through it is — or, for clear glass,
    /// how dark and how blurred — and the accent colour.
    private func themeTweakRows() -> [NSView] {
        let base = Theme.all.first { $0.id == theme.id } ?? theme
        var rows: [NSView] = []
        if base.surface == .glass {
            rows.append(SettingsKit.row("Tint", detail: "Darkens the glass, so a bright or busy desktop behind it doesn't drown out the panel",
                                        control: SettingsKit.slider(value: Double(ThemeTweaks.glassTint) * 100, range: 0...85,
                                                                    format: { "\(Int($0.rounded()))%" }) { [weak self] value in
                UserDefaults.standard.set(value / 100, forKey: ThemeTweaks.glassTintKey)
                self?.saved()
                self?.stage.refresh()
            }))
            rows.append(SettingsKit.row("Blur", detail: "Frosted softens what's behind the glass; clear keeps it sharp",
                                        control: SettingsKit.segmented(["Clear", "Frosted"], selected: ThemeTweaks.glassFrosted ? 1 : 0) { [weak self] index in
                UserDefaults.standard.set(index == 1, forKey: ThemeTweaks.glassFrostedKey)
                self?.saved()
                self?.select(.appearance)
            }))
        } else {
            rows.append(SettingsKit.row("Opacity", detail: "Below 100%, the desktop shows through the panel",
                                        control: SettingsKit.slider(value: Double(ThemeTweaks.opacity(for: base)) * 100, range: 30...100,
                                                                    format: { "\(Int($0.rounded()))%" }) { [weak self] value in
                UserDefaults.standard.set(value / 100, forKey: ThemeTweaks.opacityKey(for: base))
                self?.saved()
                self?.stage.refresh()
            }))
        }
        let accents = ThemeTweaks.accents
        rows.append(SettingsKit.popup("Accent colour", detail: "Buttons, the selected tab, progress bars",
                                      options: accents.map(\.title),
                                      selected: accents.firstIndex { $0.name == ThemeTweaks.accentName } ?? 0) { [weak self] index in
            UserDefaults.standard.set(accents[index].name, forKey: ThemeTweaks.accentKey)
            self?.saved()
            self?.applyTheme()
        })
        return rows
    }

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
        let themes = EqualGrid(items: cards, columns: 3, spacing: 16) { width in width * ThemeCard.aspect + 30 }

        let resting = ["always", "playing", "never"]
        let restingIndex = resting.firstIndex(of: UserDefaults.standard.string(forKey: "RestingBar") ?? "playing") ?? 1
        let delays: [Double] = [0, 0.15, 0.3, 0.5, 0.8]
        let delay = UserDefaults.standard.object(forKey: "HoverDelay") as? Double ?? 0.3

        return page([
            SettingsKit.header("Appearance", "How the notch looks, and how it answers when you come near it."),
            labelled("Theme", themes),
            SettingsKit.section("Adjust \(theme.name)", rows: themeTweakRows()),
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

    /// Which board the Layout pane is editing.
    private var editingBoard: PanelLayoutStore.Board = .home

    private func layoutPane() -> NSView {
        let board = editingBoard
        let canvas = PanelCanvasView()
        canvas.board = board
        canvas.heightAnchor.constraint(equalToConstant: 128).isActive = true
        canvas.onChange = { [weak self] in
            self?.saved()
            self?.stage.refresh()
            self?.select(.layout)
        }

        let unused = PanelWidget.allCases.filter { PanelLayoutStore.widgets(for: board).contains($0) == false }

        // Home, or the second board — the same editor below works on whichever is picked.
        let boardPicker = SettingsKit.segmented(PanelLayoutStore.Board.allCases.map(\.title), selected: board.rawValue) { [weak self] index in
            self?.editingBoard = PanelLayoutStore.Board(rawValue: index) ?? .home
            self?.select(.layout)
        }
        var boardRows: [NSView] = [SettingsKit.row("Board", detail: "Two boards of widgets: Home, and a second one of your own beside it", control: boardPicker)]
        if board == .second {
            let name = SettingsKit.field(UserDefaults.standard.string(forKey: PanelLayoutStore.secondNameKey) ?? "", placeholder: "Board",
                                         width: 180) { [weak self] text in
                UserDefaults.standard.set(text.trimmingCharacters(in: .whitespaces), forKey: PanelLayoutStore.secondNameKey)
                self?.saved()
                self?.select(.layout)
            }
            boardRows.append(SettingsKit.row("Name", detail: "What its tab says", control: name))
        }
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
            SettingsKit.header("Layout", "Your boards' widgets, as they sit in the panel. Drag one sideways to move it, hover for × to take it out, drag one in from below."),
            SettingsKit.section(nil, rows: boardRows),
            canvas,
            labelled(unused.isEmpty ? "Every widget is in the panel" : "More widgets", gallery),
            SettingsKit.section("Beside the notch", footer: "Left: a tab after Home. Right: a circle before the gear. Off: not in the header — still on Home's cards and its keyboard shortcut. Each side has room for \(HeaderLayout.maxLeft).",
                                rows: headerRows()),
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

    /// Home, fixed, then every view that can be placed: left ones in order, right ones
    /// in order, then the ones left out.
    private func headerRows() -> [NSView] {
        let left = HeaderLayout.left, right = HeaderLayout.right
        let hidden = HeaderLayout.movable.filter { left.contains($0) == false && right.contains($0) == false }
        func changed() {
            saved()
            stage.refresh()
            select(.layout)
        }
        var rows: [NSView] = [
            SettingsKit.iconRow(Self.tabIcon(.home), title: "Home", control: SettingsKit.status("Always first on the left", good: nil))
        ]
        for tab in left + right + hidden {
            let place = HeaderLayout.place(of: tab)
            let side = place == .left ? left : (place == .right ? right : [])
            let index = side.firstIndex(of: tab)
            let choice = SettingsKit.segmented(HeaderLayout.Place.allCases.map(\.title), selected: place.rawValue,
                                               enabled: HeaderLayout.Place.allCases.map { HeaderLayout.canMove(tab, to: $0) }) { picked in
                HeaderLayout.Place(rawValue: picked).map { HeaderLayout.move(tab, to: $0) }
                changed()
            }
            var controls: [NSView] = []
            if let index {
                controls.append(SettingsKit.iconButton("chevron.up", tip: place == .left ? "Further left" : "Earlier", enabled: index > 0) {
                    HeaderLayout.shift(tab, by: -1); changed()
                })
                controls.append(SettingsKit.iconButton("chevron.down", tip: place == .left ? "Closer to the notch" : "Later", enabled: index < side.count - 1) {
                    HeaderLayout.shift(tab, by: 1); changed()
                })
            }
            controls.append(choice)
            rows.append(SettingsKit.iconRow(Self.tabIcon(tab), title: tab.title, control: SettingsKit.group(controls)))
        }
        rows.append(SettingsKit.row("Back to how it came", control: SettingsKit.button("Reset") {
            HeaderLayout.reset()
            changed()
        }))
        return rows
    }

    private static func tabIcon(_ tab: PanelTab) -> NSImage? {
        NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    // MARK: Music

    private func musicPane() -> NSView {
        page([
            SettingsKit.header("Music", "Spotify, Apple Music, TV, QuickTime, VLC and your browser's tabs, read and controlled on your Mac."),
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
            SettingsKit.section("Browsers", footer: "The browser runs a few lines of script in the playing tab and hands back the title, artist, artwork and position. Nothing is sent anywhere. Without it, the notch shows the tab's name only.",
                                rows: browserRows()),
            SettingsKit.section("Playlists", footer: "Spotify links and your Music playlists play straight from the notch's Playlists card. Apple Music links open in Music, which can't be told to play one.", rows: playlistRows())
        ])
    }

    /// Each installed browser, whether it lets NotchHover read its tabs' media, and how
    /// to let it.
    private func browserRows() -> [NSView] {
        var rows: [NSView] = BrowserMediaProvider.all.filter(\.isInstalled).map { browser in
            let status: NSView
            let detail: String
            switch browser.access {
            case .allowed:
                status = SettingsKit.status("Allowed", good: true)
                detail = "Song, artwork, play, pause, skip and seek from any tab."
            case .blocked:
                status = SettingsKit.status("Off", good: false)
                detail = browser.allowInstructions
            case .unknown:
                status = SettingsKit.status("Not checked", good: nil)
                detail = browser.allowInstructions
            }
            let check = SettingsKit.button("Check") { [weak self] in
                guard browser.isRunning else {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier).map { NSWorkspace.shared.open($0) }
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    browser.checkAccess()
                    DispatchQueue.main.async { self?.select(.music) }
                }
            }
            check.toolTip = browser.isRunning ? "Ask \(browser.appName) now" : "Open \(browser.appName) first"
            return SettingsKit.row(browser.appName, detail: detail, control: SettingsKit.group([status, check]))
        }
        // Firefox and the browsers built on it can't be scripted at all; their open tabs
        // are read from the file they keep on disk.
        let firefoxFamily = [("Firefox", "org.mozilla.firefox"), ("Zen", "app.zen-browser.zen"), ("LibreWolf", "io.gitlab.librewolf"),
                             ("Waterfox", "net.waterfox.waterfox"), ("Floorp", "one.ablaze.floorp")]
        for (name, identifier) in firefoxFamily {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                  url.path.contains("/Application Support/") == false else { continue }
            rows.append(SettingsKit.row(name, detail: "The most likely playing tab's name and icon, from the tabs \(name) keeps on disk. \(name) can't be asked for more, or controlled.",
                                        control: SettingsKit.status("Title only", good: nil)))
        }
        if rows.isEmpty {
            rows.append(SettingsKit.row("No supported browser installed"))
        }
        return rows
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
                screenshotFolderRow(),
            ] + screenshotKeysRow() + [
                SettingsKit.row("Where they are now", detail: Self.shortPath(ScreenshotStore.folder),
                                control: SettingsKit.button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ScreenshotStore.folder]) }),
                SettingsKit.row("Capture from the notch", detail: "⌃⌥4 for an area, or the buttons in the Screenshots view.",
                                control: SettingsKit.status(CGPreflightScreenCaptureAccess() ? "Allowed" : "Asks the first time", good: CGPreflightScreenCaptureAccess() ? true : nil))
            ])
        ])
    }

    private static func shortPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static let screenshotKeysKey = "ScreenshotFolderForKeys"
    private static let previousSystemFolderKey = "ScreenshotPreviousSystemFolder"

    /// Where NotchHover's screenshots go: macOS's folder, two usual places, or one you pick.
    private func screenshotFolderRow() -> NSView {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let presets: [(title: String, url: URL?)] = [
            ("Same as macOS — \(Self.shortPath(ScreenshotStore.systemFolder))", nil),
            ("Pictures › Screenshots", home.appendingPathComponent("Pictures/Screenshots", isDirectory: true)),
            ("Documents › Screenshots", home.appendingPathComponent("Documents/Screenshots", isDirectory: true))
        ]
        let chosen = ScreenshotStore.chosenFolder?.standardizedFileURL
        var options = presets.map(\.title)
        var selected = presets.firstIndex { $0.url?.standardizedFileURL == chosen } ?? 0
        if let chosen, presets.contains(where: { $0.url?.standardizedFileURL == chosen }) == false {
            options.append(chosen.lastPathComponent)
            selected = options.count - 1
        }
        options.append("Choose a folder…")
        let chooseIndex = options.count - 1

        return SettingsKit.popup("Save screenshots to", detail: "Screenshots taken from the notch. The Screenshots view shows these and the ones from macOS's keys.",
                                 options: options, selected: selected) { [weak self] index in
            var folder: URL?
            if index == chooseIndex {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.prompt = "Save Here"
                panel.directoryURL = ScreenshotStore.folder
                guard panel.runModal() == .OK, let url = panel.url else { self?.select(.files); return }
                folder = url
            } else if index < presets.count {
                folder = presets[index].url
            } else {
                folder = ScreenshotStore.chosenFolder
            }
            if let folder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            UserDefaults.standard.set(folder?.path, forKey: ScreenshotStore.folderKey)
            if UserDefaults.standard.bool(forKey: Self.screenshotKeysKey) {
                Self.applyFolderToKeys(folder)
                // Back to macOS's own folder: there's nothing left to point the keys at.
                if folder == nil { UserDefaults.standard.set(false, forKey: Self.screenshotKeysKey) }
            }
            ScreenshotStore.shared.restart()
            self?.saved()
            self?.select(.files)
        }
    }

    /// Optionally, ⇧⌘3, ⇧⌘4 and ⇧⌘5 save there too — only offered once a folder is chosen.
    private func screenshotKeysRow() -> [NSView] {
        guard let chosen = ScreenshotStore.chosenFolder else { return [] }
        return [SettingsKit.toggle("Use it for ⇧⌘3, ⇧⌘4 and ⇧⌘5 too",
                                   detail: "Changes the Screenshot app's Save to, the same setting. Turning this off puts it back how it was.",
                                   isOn: UserDefaults.standard.bool(forKey: Self.screenshotKeysKey)) { [weak self] isOn in
            UserDefaults.standard.set(isOn, forKey: Self.screenshotKeysKey)
            Self.applyFolderToKeys(isOn ? chosen : nil)
            ScreenshotStore.shared.restart()
            self?.saved()
            self?.select(.files)
        }]
    }

    /// Points macOS's screenshot keys at a folder, remembering where they pointed before;
    /// nil puts that back.
    private static func applyFolderToKeys(_ folder: URL?) {
        let system = UserDefaults(suiteName: "com.apple.screencapture")
        if let folder {
            if UserDefaults.standard.object(forKey: previousSystemFolderKey) == nil {
                UserDefaults.standard.set(system?.string(forKey: "location") ?? "", forKey: previousSystemFolderKey)
            }
            ScreenshotStore.setSystemFolder(folder)
        } else {
            let previous = UserDefaults.standard.string(forKey: previousSystemFolderKey) ?? ""
            ScreenshotStore.setSystemFolder(previous.isEmpty ? nil : URL(fileURLWithPath: previous))
            UserDefaults.standard.removeObject(forKey: previousSystemFolderKey)
        }
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

    /// Name and link for each pinned playlist, saved as you leave a field, with where it
    /// plays; then ways to add one.
    private func playlistRows() -> [NSView] {
        var entries = PinnedPlaylists.entries
        func store() {
            PinnedPlaylists.entries = entries.filter { $0.name.isEmpty == false && PinnedPlaylists.normalize($0.link) != nil }
            saved()
        }
        var rows: [NSView] = entries.enumerated().map { index, entry in
            let name = SettingsKit.field(entry.name, placeholder: "Name", width: 160) { entries[index].name = $0; store() }
            let link = SettingsKit.field(entry.service == .musicLibrary ? "Music library playlist" : entry.link,
                                         placeholder: "Spotify or Apple Music link", width: nil) { [weak self] text in
                guard entry.service != .musicLibrary else { return }
                entries[index].link = PinnedPlaylists.normalize(text) ?? text
                store()
                self?.select(.music)
            }
            link.isEditable = entry.service != .musicLibrary
            link.toolTip = entry.service.title
            let service = SettingsKit.status(entry.service == .appleMusicLink ? "Opens in Music" : entry.service == .musicLibrary ? "Music" : entry.service == .spotify ? "Spotify" : "Not a music link",
                                             good: entry.service == .unknown ? false : nil)
            // One width for every row's label, so the link fields line up.
            service.widthAnchor.constraint(equalToConstant: 118).isActive = true
            let remove = SettingsKit.button("Remove") { [weak self] in
                entries.remove(at: index)
                store()
                self?.select(.music)
            }
            return SettingsKit.fieldRow([name, link, service, remove])
        }
        let addLink = SettingsKit.button("Add link") { [weak self] in
            entries.append(.init(name: "", link: ""))
            UserDefaults.standard.set(entries.map { "\($0.name)|\($0.link)" }, forKey: PinnedPlaylists.defaultsKey)
            self?.select(.music)
        }
        let addFromMusic = SettingsKit.button("Add from Music…") { [weak self] in
            self?.showMusicLibraryMenu()
        }
        addFromMusic.identifier = NSUserInterfaceItemIdentifier("addFromMusic")
        rows.append(SettingsKit.row(entries.isEmpty ? "No playlists yet" : "Another one",
                                    detail: "Or share a Spotify or Apple Music link and choose NotchHover",
                                    control: SettingsKit.group([addFromMusic, addLink])))
        return rows
    }

    /// Your Music playlists, in a menu under the button; picking one pins it.
    private func showMusicLibraryMenu() {
        func find(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == "addFromMusic" { return view }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        guard let root = window?.contentView, let button = find(root) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let playlists = PinnedPlaylists.musicLibraryPlaylists()
            DispatchQueue.main.async {
                let menu = NSMenu()
                if playlists.isEmpty {
                    menu.addItem(withTitle: "No playlists in your Music library", action: nil, keyEquivalent: "")
                }
                for playlist in playlists {
                    menu.addItem(ClosureMenuItem(playlist.name) {
                        var all = PinnedPlaylists.entries
                        guard all.contains(where: { $0.link == playlist.link }) == false else { return }
                        all.append(playlist)
                        PinnedPlaylists.entries = all
                        self?.saved()
                        self?.select(.music)
                    })
                }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            }
        }
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

/// A theme as a simple picture of the panel in its colours — the way macOS's own
/// Appearance tiles show Light and Dark rather than a shrunken screenshot — with room
/// around it, its name below, and a ring set just outside when it's the one in use.
private final class ThemeCard: NSView {
    var onPick: (() -> Void)?

    /// The tile's height for its width, so the grid can size rows before layout.
    static let aspect: CGFloat = 0.42

    init(theme candidate: Theme, isSelected: Bool) {
        super.init(frame: .zero)
        let theme = SettingsKit.theme
        let swatch = ThemeSwatchView(theme: candidate)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 10
        swatch.layer?.masksToBounds = true

        // The ring sits 3pt outside the tile, so the tile itself is never covered.
        let ring = NSView()
        ring.wantsLayer = true
        ring.layer?.cornerRadius = 13
        ring.layer?.borderWidth = isSelected ? 2.5 : 0
        ring.layer?.borderColor = theme.accent.cgColor

        let name = NSTextField(labelWithString: candidate.name)
        name.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        name.textColor = isSelected ? theme.primaryText : theme.secondaryText
        name.alignment = .center

        [ring, swatch, name].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            ring.topAnchor.constraint(equalTo: topAnchor),
            ring.leadingAnchor.constraint(equalTo: leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: trailingAnchor),
            ring.heightAnchor.constraint(equalTo: ring.widthAnchor, multiplier: Self.aspect),
            swatch.topAnchor.constraint(equalTo: ring.topAnchor, constant: 3),
            swatch.leadingAnchor.constraint(equalTo: ring.leadingAnchor, constant: 3),
            swatch.trailingAnchor.constraint(equalTo: ring.trailingAnchor, constant: -3),
            swatch.bottomAnchor.constraint(equalTo: ring.bottomAnchor, constant: -3),
            name.topAnchor.constraint(equalTo: ring.bottomAnchor, constant: 8),
            name.leadingAnchor.constraint(equalTo: leadingAnchor),
            name.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        toolTip = candidate.summary
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onPick?() }
}
