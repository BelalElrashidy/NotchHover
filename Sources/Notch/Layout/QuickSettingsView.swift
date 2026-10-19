import AppKit

/// Settings inside the notch: the gear turns the panel into its own quick settings, as
/// NotchDrop does, so the common switches change where you can see their effect. Four
/// tabs of compact rows; anything bigger — layout, shortcuts, launchers — is one click
/// away in the full window.
final class QuickSettingsView: NSView {
    var onAllSettings: ((SettingsWindowController.Category?) -> Void)?
    var onShowActions: (() -> Void)?
    /// Something changed that the rest of the app should pick up.
    var onChange: (() -> Void)?

    private enum Tab: String, CaseIterable { case look = "Look", playing = "Playing", privacy = "Privacy", keys = "Keys" }

    private var tab: Tab = .look
    private let tabsRow = NSStackView()
    private let grid = NSStackView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Style.theme.windowBackground.withAlphaComponent(0.97).cgColor
        layer?.cornerRadius = 14

        tabsRow.spacing = 4
        let all = ClosureButton(title: "All settings →") { [weak self] in self?.onAllSettings?(nil) }
        all.isBordered = false
        all.attributedTitle = NSAttributedString(string: "All settings →", attributes: [
            .foregroundColor: Style.accent, .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: .medium)
        ])
        let quit = ClosureButton(title: "Quit") { NSApp.terminate(nil) }
        quit.isBordered = false
        quit.attributedTitle = NSAttributedString(string: "Quit", attributes: [
            .foregroundColor: Style.tertiaryText, .font: NSFont.systemFont(ofSize: Style.scaled(11))
        ])
        let top = NSStackView(views: [tabsRow, NSView(), quit, all])
        top.spacing = 12
        top.alignment = .centerY

        grid.orientation = .horizontal
        grid.alignment = .top
        grid.distribution = .fillEqually
        grid.spacing = 22

        let stack = NSStackView(views: [top, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        tabsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for candidate in Tab.allCases {
            let chip = ClosureButton(title: candidate.rawValue) { [weak self] in
                self?.tab = candidate
                Haptics.tick()
                self?.reload()
            }
            chip.isBordered = false
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 11
            let selected = candidate == tab
            chip.layer?.backgroundColor = (selected ? Style.primaryText : Style.controlFill).cgColor
            chip.attributedTitle = NSAttributedString(string: candidate.rawValue, attributes: [
                .foregroundColor: selected ? Style.theme.windowBackground : Style.secondaryText,
                .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: .medium)
            ])
            chip.heightAnchor.constraint(equalToConstant: 22).isActive = true
            chip.widthAnchor.constraint(equalToConstant: chip.intrinsicContentSize.width + 20).isActive = true
            tabsRow.addArrangedSubview(chip)
        }

        let rows = makeRows()
        let left = column(Array(rows.prefix((rows.count + 1) / 2)))
        let right = column(Array(rows.dropFirst((rows.count + 1) / 2)))
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        [left, right].forEach(grid.addArrangedSubview)
    }

    private func column(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    // MARK: Rows

    private func makeRows() -> [NSView] {
        let defaults = UserDefaults.standard
        switch tab {
        case .look:
            let resting = ["always", "playing", "never"]
            let delays: [Double] = [0.15, 0.3, 0.6]
            let delay = defaults.object(forKey: "HoverDelay") as? Double ?? 0.3
            return [
                row("Theme", control: themeSwatches()),
                row("On hover", control: pills(["Peek", "Open"], selected: defaults.string(forKey: "HoverAction") == "open" ? 1 : 0) { [weak self] in
                    defaults.set($0 == 1 ? "open" : "peek", forKey: "HoverAction")
                    self?.onChange?()
                }),
                row("Resting bar", control: pills(["Always", "Playing", "Never"],
                                                  selected: resting.firstIndex(of: defaults.string(forKey: "RestingBar") ?? "playing") ?? 1) { [weak self] in
                    defaults.set(resting[$0], forKey: "RestingBar")
                    self?.onChange?()
                }),
                row("Hover delay", control: pills(["Quick", "Normal", "Slow"],
                                                  selected: delays.enumerated().min { abs($0.element - delay) < abs($1.element - delay) }?.offset ?? 1) { [weak self] in
                    defaults.set(delays[$0], forKey: "HoverDelay")
                    self?.onChange?()
                })
            ]
        case .playing:
            return [
                toggle("Live visualizer", note: "asks for audio recording", isOn: AudioLevels.isEnabled) { AudioLevels.isEnabled = $0 },
                toggle("Synced lyrics", note: "uses lrclib.net", isOn: LyricsService.isEnabled) { LyricsService.isEnabled = $0 },
                toggle("On the lock screen", note: nil, isOn: LockScreenMusic.isEnabled) { LockScreenMusic.isEnabled = $0 },
                row("Playlists", control: link("Edit…") { [weak self] in self?.onAllSettings?(.music) })
            ]
        case .privacy:
            return [
                toggle("Clipboard history", note: "on this Mac only", isOn: ClipboardHistory.shared.isPaused == false) {
                    ClipboardHistory.shared.isPaused = $0 == false
                },
                row("Clipboard", control: link("Clear history") { ClipboardHistory.shared.clear() }),
                toggle("Speak notifications", note: nil, isOn: defaults.bool(forKey: "SpeakNotifications")) { [weak self] in
                    defaults.set($0, forKey: "SpeakNotifications")
                    self?.onChange?()
                },
                row("Permissions", control: link("Review…") { [weak self] in self?.onAllSettings?(.privacy) })
            ]
        case .keys:
            return [
                toggle("Trackpad gestures", note: nil, isOn: SwipeRecognizer.isEnabled) { defaults.set($0, forKey: "TrackpadGestures") },
                toggle("Haptic feedback", note: nil, isOn: Haptics.isEnabled) { defaults.set($0, forKey: "Haptics") },
                row("Every action", control: link("⌘K") { [weak self] in self?.onShowActions?() }),
                row("Hotkeys", control: link("Edit…") { [weak self] in self?.onAllSettings?(.shortcuts) })
            ]
        }
    }

    private func row(_ title: String, note: String? = nil, control: NSView) -> NSView {
        let label = Style.label(title, size: 12)
        var text: [NSView] = [label]
        if let note { text.append(Style.label(note, size: 10, color: Style.tertiaryText)) }
        let textStack = NSStackView(views: text)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [textStack, spacer, control])
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        let rule = NSView()
        rule.wantsLayer = true
        rule.layer?.backgroundColor = Style.primaryText.withAlphaComponent(0.07).cgColor
        let wrapper = NSStackView(views: [stack, rule])
        wrapper.orientation = .vertical
        wrapper.spacing = 0
        stack.widthAnchor.constraint(equalTo: wrapper.widthAnchor).isActive = true
        rule.widthAnchor.constraint(equalTo: wrapper.widthAnchor).isActive = true
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        return wrapper
    }

    private func toggle(_ title: String, note: String?, isOn: Bool, onChange: @escaping (Bool) -> Void) -> NSView {
        let control = SwitchControl()
        control.isOn = isOn
        control.onChange = { [weak self] value in
            onChange(value)
            Haptics.tick()
            self?.onChange?()
        }
        return row(title, note: note, control: control)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> NSView {
        let button = ClosureButton(title: title, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = Style.controlFill.cgColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: Style.primaryText, .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: .medium)
        ])
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        button.widthAnchor.constraint(equalToConstant: button.intrinsicContentSize.width + 16).isActive = true
        return button
    }

    /// A small segmented control in the panel's own colours.
    private func pills(_ titles: [String], selected: Int, onSelect: @escaping (Int) -> Void) -> NSView {
        let stack = NSStackView()
        stack.spacing = 2
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 7
        stack.layer?.backgroundColor = Style.controlFill.cgColor
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        for (index, title) in titles.enumerated() {
            let button = ClosureButton(title: title) { [weak self] in
                onSelect(index)
                Haptics.tick()
                self?.reload()
            }
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            let isOn = index == selected
            button.layer?.backgroundColor = isOn ? Style.primaryText.withAlphaComponent(0.22).cgColor : NSColor.clear.cgColor
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: isOn ? Style.primaryText : Style.secondaryText,
                .font: NSFont.systemFont(ofSize: Style.scaled(10.5), weight: isOn ? .semibold : .regular)
            ])
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            button.widthAnchor.constraint(equalToConstant: button.intrinsicContentSize.width + 12).isActive = true
            stack.addArrangedSubview(button)
        }
        return stack
    }

    /// One swatch per theme, ringed when it's the one in use.
    private func themeSwatches() -> NSView {
        let stack = NSStackView()
        stack.spacing = 5
        for theme in Theme.all {
            let swatch = ClosureButton(title: "") { [weak self] in
                UserDefaults.standard.set(theme.id, forKey: ThemeStore.defaultsKey)
                Haptics.tick()
                self?.onChange?()
            }
            swatch.isBordered = false
            swatch.wantsLayer = true
            swatch.layer?.cornerRadius = 5
            if case .solid(let color) = theme.surface {
                swatch.layer?.backgroundColor = color.cgColor
            } else {
                swatch.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.5).cgColor
            }
            let isCurrent = theme.id == ThemeStore.selected.id
            swatch.layer?.borderWidth = isCurrent ? 2 : 0.5
            swatch.layer?.borderColor = (isCurrent ? Style.accent : Style.primaryText.withAlphaComponent(0.3)).cgColor
            swatch.toolTip = theme.name
            swatch.widthAnchor.constraint(equalToConstant: 24).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(swatch)
        }
        return stack
    }
}
