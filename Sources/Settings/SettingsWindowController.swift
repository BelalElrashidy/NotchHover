import AppKit

/// Scroll documents draw from the top only when the view is flipped.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension Notification.Name {
    /// Posted when settings change so the panel can pick them up without a relaunch.
    static let notchHoverSettingsChanged = Notification.Name("NotchHoverSettingsChanged")
    /// Posted by the notch's gear button.
    static let notchHoverOpenSettings = Notification.Name("NotchHoverOpenSettings")
}

/// Settings: a category sidebar, the pane for that category, and a live preview of
/// the notch below it. Everything saves as you change it, and every control is drawn
/// from the active theme rather than left as a stock grey AppKit control.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum Category: Int, CaseIterable {
        case appearance
        case layout
        case playlists
        case shortcuts
        case apps
        case advanced

        var title: String {
            switch self {
            case .appearance: return "Appearance"
            case .layout: return "Layout"
            case .playlists: return "Playlists"
            case .shortcuts: return "Shortcuts"
            case .apps: return "Apps"
            case .advanced: return "Advanced"
            }
        }

        var symbol: String {
            switch self {
            case .appearance: return "paintpalette"
            case .layout: return "rectangle.split.3x1"
            case .playlists: return "music.note.list"
            case .shortcuts: return "bolt"
            case .apps: return "square.grid.2x2"
            case .advanced: return "gearshape"
            }
        }
    }

    private let playlistsSection = KeyValueSection(
        title: "Spotify playlists",
        hint: "Paste a Spotify link or URI — either works",
        keyPlaceholder: "Name",
        valuePlaceholder: "https://open.spotify.com/playlist/…"
    )
    private let shortcutsSection = SingleFieldSection(
        title: "Shortcuts",
        hint: "Names must match the Shortcuts app exactly",
        placeholder: "Shortcut name"
    )
    private let appsSection = AppListSection()

    private var restingBarRow: SegmentedRow?
    private var speakToggle: ToggleRow?
    private let layoutEditor = LayoutEditorView()
    private var themeCards: [String: NSButton] = [:]

    private let sidebarStack = NSStackView()
    private let sidebarContainer = NSView()
    private let detailContainer = FlippedView()
    private let previewImageView = NSImageView()
    private let previewCaption = NSTextField(labelWithString: "Live preview")
    private let savedNote = NSTextField(labelWithString: "Changes save as you make them")
    private var doneButton: NSButton?
    private let root = NSView()
    private var sidebarButtons: [Category: NSButton] = [:]
    private var selectedCategory: Category = .appearance
    private var theme: Theme = ThemeStore.selected

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchHover Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        window.delegate = self
        window.contentView = makeContentView()
        window.center()
        load()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        theme = ThemeStore.selected
        load()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        root.wantsLayer = true
        sidebarContainer.wantsLayer = true

        let sidebar = makeSidebar()
        let detail = makeDetailColumn()

        [sidebar, detail].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 184),
            detail.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detail.topAnchor.constraint(equalTo: root.topAnchor),
            detail.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        return root
    }

    private func makeSidebar() -> NSView {
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 3
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(sidebarStack)

        for category in Category.allCases {
            let button = NSButton(title: "  " + category.title, target: self, action: #selector(handleCategory(_:)))
            button.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.tag = category.rawValue
            button.font = .systemFont(ofSize: 13)
            sidebarButtons[category] = button
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 160).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }

        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor, constant: 12),
            sidebarStack.topAnchor.constraint(equalTo: sidebarContainer.topAnchor, constant: 18)
        ])

        return sidebarContainer
    }

    private func makeDetailColumn() -> NSView {
        let column = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewCaption.font = .systemFont(ofSize: 11)
        savedNote.font = .systemFont(ofSize: 11)

        let previewBox = NSStackView(views: [previewCaption, previewImageView])
        previewBox.orientation = .vertical
        previewBox.alignment = .leading
        previewBox.spacing = 6
        previewBox.translatesAutoresizingMaskIntoConstraints = false

        let done = SettingsStyle.capsule("Done", prominent: true, target: self, action: #selector(handleDone))
        doneButton = done
        let footer = NSStackView(views: [savedNote, NSView(), done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = detailContainer
        scroll.translatesAutoresizingMaskIntoConstraints = false

        [scroll, previewBox, footer].forEach(column.addSubview)

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            // Pinned on three sides so the pane's height is free to exceed the scroller.
            detailContainer.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: 24),
            detailContainer.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -24),
            detailContainer.topAnchor.constraint(equalTo: clip.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: column.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: previewBox.topAnchor, constant: -12),
            previewBox.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 24),
            previewBox.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            previewImageView.widthAnchor.constraint(equalToConstant: 400),
            previewImageView.heightAnchor.constraint(equalToConstant: 112),
            footer.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -18)
        ])

        return column
    }

    // MARK: - Categories

    private func select(_ category: Category) {
        selectedCategory = category

        for (candidate, button) in sidebarButtons {
            let active = candidate == category
            button.layer?.backgroundColor = active ? theme.accent.cgColor : NSColor.clear.cgColor
            button.contentTintColor = active ? theme.onAccentText : theme.secondaryText
            button.attributedTitle = NSAttributedString(
                string: "  " + candidate.title,
                attributes: [
                    .foregroundColor: active ? theme.onAccentText : theme.primaryText,
                    .font: NSFont.systemFont(ofSize: 13)
                ]
            )
        }

        detailContainer.subviews.forEach { $0.removeFromSuperview() }
        let pane = makePane(for: category)
        pane.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            pane.trailingAnchor.constraint(lessThanOrEqualTo: detailContainer.trailingAnchor),
            pane.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            // Drives the scroll document's height; without it the container collapses.
            pane.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -20)
        ])
    }

    private func makePane(for category: Category) -> NSView {
        switch category {
        case .appearance: return appearancePane()
        case .layout: return layoutPane()
        case .playlists: return playlistsSection
        case .shortcuts: return shortcutsSection
        case .apps: return appsSection
        case .advanced: return advancedPane()
        }
    }

    private func appearancePane() -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 10
        themeCards.removeAll()

        for row in stride(from: 0, to: Theme.all.count, by: 3) {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 10

            for candidate in Theme.all[row..<min(row + 3, Theme.all.count)] {
                let card = NSButton(title: candidate.name, target: self, action: #selector(handleThemeCard(_:)))
                card.image = PreviewRenderer.snapshot(theme: candidate, width: 150)
                card.imagePosition = .imageAbove
                card.imageScaling = .scaleProportionallyDown
                card.isBordered = false
                card.wantsLayer = true
                card.layer?.cornerRadius = 8
                card.layer?.borderWidth = 2
                card.identifier = NSUserInterfaceItemIdentifier(candidate.id)
                card.attributedTitle = NSAttributedString(
                    string: candidate.name,
                    attributes: [.foregroundColor: theme.primaryText, .font: NSFont.systemFont(ofSize: 11)]
                )
                card.widthAnchor.constraint(equalToConstant: 158).isActive = true
                card.heightAnchor.constraint(equalToConstant: 78).isActive = true
                themeCards[candidate.id] = card
                rowStack.addArrangedSubview(card)
            }
            grid.addArrangedSubview(rowStack)
        }

        highlightSelectedThemeCard()

        let restingRow = SegmentedRow(labels: ["Always", "While playing", "Never"])
        restingRow.select(storedRestingBarIndex(), notify: false)
        restingRow.onSelect = { [weak self] index in
            UserDefaults.standard.set(["always", "playing", "never"][index], forKey: "RestingBar")
            self?.save()
        }
        restingBarRow = restingRow

        let stack = NSStackView(views: [
            SettingsStyle.heading("Appearance"),
            grid,
            labeledRow("Resting bar", control: restingRow)
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        return stack
    }

    private func layoutPane() -> NSView {
        layoutEditor.reload()
        return layoutEditor
    }

    private func advancedPane() -> NSView {
        let toggle = ToggleRow(title: "Speak notifications aloud")
        toggle.set(isOn: UserDefaults.standard.bool(forKey: "SpeakNotifications"), notify: false)
        toggle.onChange = { [weak self] value in
            UserDefaults.standard.set(value, forKey: "SpeakNotifications")
            self?.save()
        }
        speakToggle = toggle

        let trusted = NotificationWatcher.isTrusted
        let status = SettingsStyle.label(
            trusted
                ? "Accessibility granted — banners are being read"
                : "Reading notifications needs Accessibility access",
            size: 11,
            secondary: true
        )

        let clipboardToggle = ToggleRow(title: "Record clipboard history")
        clipboardToggle.set(isOn: ClipboardHistory.shared.isPaused == false, notify: false)
        clipboardToggle.onChange = { isOn in
            ClipboardHistory.shared.isPaused = isOn == false
        }
        let clipboardNote = SettingsStyle.label(
            "Stored only on this Mac. Copies from password managers are never recorded.",
            size: 11,
            secondary: true
        )
        let clearClipboard = SettingsStyle.capsule("Clear clipboard history", target: self, action: #selector(handleClearClipboard))

        let gesturesToggle = ToggleRow(title: "Trackpad gestures")
        gesturesToggle.set(isOn: SwipeRecognizer.isEnabled, notify: false)
        gesturesToggle.onChange = { isOn in UserDefaults.standard.set(isOn, forKey: "TrackpadGestures") }
        let gesturesNote = SettingsStyle.label(
            "Two fingers down on the notch to open it, up to close, sideways to change tab — or, on the resting bar, the track.",
            size: 11,
            secondary: true
        )
        let hapticsToggle = ToggleRow(title: "Haptic feedback")
        hapticsToggle.set(isOn: Haptics.isEnabled, notify: false)
        hapticsToggle.onChange = { isOn in UserDefaults.standard.set(isOn, forKey: "Haptics") }

        var rows: [NSView] = [
            SettingsStyle.heading("Advanced"),
            gesturesToggle, gesturesNote, hapticsToggle,
            clipboardToggle, clipboardNote, clearClipboard,
            toggle, status
        ]
        if trusted == false {
            rows.append(SettingsStyle.capsule("Allow notifications…", target: self, action: #selector(handleNotificationAccess)))
        }

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        return stack
    }

    private func labeledRow(_ title: String, control: NSView) -> NSView {
        let label = SettingsStyle.label(title, secondary: true)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        label.widthAnchor.constraint(equalToConstant: 96).isActive = true
        return stack
    }

    private func storedRestingBarIndex() -> Int {
        switch UserDefaults.standard.string(forKey: "RestingBar") ?? "playing" {
        case "always": return 0
        case "never": return 2
        default: return 1
        }
    }

    private func highlightSelectedThemeCard() {
        for (id, card) in themeCards {
            let active = id == theme.id
            card.layer?.borderColor = active ? theme.accent.cgColor : NSColor.clear.cgColor
            card.layer?.backgroundColor = active ? theme.accent.withAlphaComponent(0.14).cgColor : NSColor.clear.cgColor
        }
    }

    // MARK: - Theming

    private func applyTheme(_ newTheme: Theme) {
        theme = newTheme
        // Controls are rebuilt below and must be drawn in this theme, not the stored one.
        SettingsStyle.themeOverride = newTheme
        window?.appearance = newTheme.appearance
        window?.backgroundColor = newTheme.windowBackground
        root.layer?.backgroundColor = newTheme.windowBackground.cgColor
        sidebarContainer.layer?.backgroundColor = newTheme.elevatedBackground.cgColor
        previewCaption.textColor = newTheme.secondaryText
        savedNote.textColor = newTheme.tertiaryText
        // Built once at init, so it needs restyling by hand when the theme changes.
        doneButton?.layer?.backgroundColor = newTheme.accent.cgColor
        doneButton?.attributedTitle = NSAttributedString(
            string: "Done",
            attributes: [
                .foregroundColor: newTheme.onAccentText,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        select(selectedCategory)
        refreshPreview()
    }

    private func refreshPreview() {
        previewImageView.image = PreviewRenderer.snapshot(theme: theme, width: 400)
        previewCaption.stringValue = "Live preview — \(theme.name)"
    }

    // MARK: - Load / save

    private func load() {
        let defaults = UserDefaults.standard

        playlistsSection.entries = (defaults.stringArray(forKey: PlaylistsPaneView.defaultsKey) ?? [])
            .compactMap { entry in
                let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
        playlistsSection.reloadRows()
        playlistsSection.onChange = { [weak self] in self?.savePlaylists() }

        shortcutsSection.entries = defaults.stringArray(forKey: ShortcutsRunner.defaultsKey) ?? []
        shortcutsSection.reloadRows()
        shortcutsSection.onChange = { [weak self] in self?.saveShortcuts() }

        appsSection.reload()
        appsSection.onChange = { [weak self] in self?.save() }
        layoutEditor.onChange = { [weak self] in
            self?.refreshPreview()
            self?.save()
        }

        applyTheme(ThemeStore.selected)
    }

    private func savePlaylists() {
        playlistsSection.commitEdits()
        let playlists = playlistsSection.entries
            .filter { $0.key.isEmpty == false && $0.value.isEmpty == false }
            .compactMap { entry -> String? in
                guard let uri = SpotifyURI.normalize(entry.value) else { return nil }
                return "\(entry.key)|\(uri)"
            }
        UserDefaults.standard.set(playlists, forKey: PlaylistsPaneView.defaultsKey)
        save()
    }

    private func saveShortcuts() {
        shortcutsSection.commitEdits()
        UserDefaults.standard.set(shortcutsSection.entries.filter { $0.isEmpty == false }, forKey: ShortcutsRunner.defaultsKey)
        save()
    }

    /// Every control calls this the moment it changes; there is no Save button.
    private func save() {
        NotificationCenter.default.post(name: .notchHoverSettingsChanged, object: nil)
    }

    @objc private func handleThemeCard(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let picked = Theme.all.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(picked.id, forKey: ThemeStore.defaultsKey)
        applyTheme(picked)
        save()
    }

    @objc private func handleCategory(_ sender: NSButton) {
        guard let category = Category(rawValue: sender.tag) else { return }
        select(category)
    }

    @objc private func handleClearClipboard() {
        ClipboardHistory.shared.clear()
    }

    @objc private func handleNotificationAccess() {
        NotificationWatcher.requestTrust()
        NotificationWatcher.openAccessibilitySettings()
    }

    @objc private func handleDone() {
        // Text fields commit on focus loss, so nothing is lost by closing.
        window?.makeFirstResponder(nil)
        savePlaylists()
        saveShortcuts()
        window?.performClose(nil)
    }

    /// Exercises the window without a pointer: --settings-selftest
    func runSelfTest() {
        func report(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }

        report("start: \(playlistsSection.entries.count) playlist rows, \(playlistsSection.rowCount) row views")
        playlistsSection.addRow()
        report("after add: \(playlistsSection.entries.count) entries, \(playlistsSection.rowCount) row views")
        playlistsSection.removeRow(at: 0)
        report("after remove: \(playlistsSection.entries.count) entries, \(playlistsSection.rowCount) row views")

        for category in Category.allCases {
            select(category)
            report("category \(category.title): \(detailContainer.subviews.count) pane view(s)")
        }

        for (candidate, category) in [(Theme.midnight, Category.layout), (Theme.frost, Category.appearance)] {
            applyTheme(candidate)
            select(category)
            guard let content = window?.contentView else { continue }
            content.layoutSubtreeIfNeeded()
            let image = NSImage(size: content.bounds.size)
            image.lockFocus()
            if let context = NSGraphicsContext.current {
                content.displayIgnoringOpacity(content.bounds, in: context)
            }
            image.unlockFocus()

            let path = NSTemporaryDirectory() + "notchhover-settings-\(candidate.id).png"
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                report("wrote \(path)")
            }
        }
        applyTheme(ThemeStore.selected)
    }

    func windowWillClose(_ notification: Notification) {
        SettingsStyle.themeOverride = nil
        load()
    }
}
