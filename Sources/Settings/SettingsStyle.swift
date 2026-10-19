import AppKit

/// Themed controls for the settings window. AppKit's stock controls only follow the
/// light/dark appearance, so they stayed grey whatever the theme — these are drawn
/// from the theme's own palette.
enum SettingsStyle {
    /// The theme the settings window is currently showing, which may differ from the
    /// stored one while a change is being previewed. Without this, controls were built
    /// from stored state and came out in the wrong palette.
    static var themeOverride: Theme?

    static var theme: Theme { themeOverride ?? ThemeStore.selected }

    static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = theme.primaryText
        return label
    }

    static func label(_ text: String, size: CGFloat = 12, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? theme.secondaryText : theme.primaryText
        return label
    }

    static func field(_ value: String, placeholder: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12)
        field.textColor = theme.primaryText
        field.drawsBackground = true
        field.backgroundColor = theme.controlFill
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.borderWidth = 1
        field.layer?.borderColor = theme.tertiaryText.withAlphaComponent(0.35).cgColor
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return field
    }

    static func capsule(_ title: String, prominent: Bool = false, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = prominent ? theme.accent.cgColor : theme.controlFill.cgColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: prominent ? theme.onAccentText : theme.primaryText,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    static func card(_ content: NSView, padding: CGFloat = 12) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.backgroundColor = theme.elevatedBackground.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -padding)
        ])
        return box
    }
}

/// Themed replacement for NSSegmentedControl.
final class SegmentedRow: NSView {
    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0
    private var buttons: [NSButton] = []

    init(labels: [String]) {
        super.init(frame: .zero)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, title) in labels.enumerated() {
            let button = SettingsStyle.capsule(title, target: self, action: #selector(handleTap(_:)))
            button.tag = index
            buttons.append(button)
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        select(0, notify: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ index: Int, notify: Bool = true) {
        selectedIndex = index
        let theme = SettingsStyle.theme
        for (position, button) in buttons.enumerated() {
            let active = position == index
            button.layer?.backgroundColor = active ? theme.accent.cgColor : theme.controlFill.cgColor
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .foregroundColor: active ? theme.onAccentText : theme.primaryText,
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium)
                ]
            )
        }
        if notify { onSelect?(index) }
    }

    @objc private func handleTap(_ sender: NSButton) {
        select(sender.tag)
    }
}

/// Themed on/off switch.
final class ToggleRow: NSView {
    var onChange: ((Bool) -> Void)?
    private(set) var isOn = false

    private let knob = NSView()
    private let track = NSView()

    init(title: String) {
        super.init(frame: .zero)

        let label = SettingsStyle.label(title)

        track.wantsLayer = true
        track.layer?.cornerRadius = 9
        knob.wantsLayer = true
        knob.layer?.cornerRadius = 7
        knob.layer?.backgroundColor = NSColor.white.cgColor
        track.addSubview(knob)

        let stack = NSStackView(views: [track, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            track.widthAnchor.constraint(equalToConstant: 34),
            track.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleToggle))
        addGestureRecognizer(click)
        set(isOn: false, notify: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(isOn value: Bool, notify: Bool = true) {
        isOn = value
        let theme = SettingsStyle.theme
        track.layer?.backgroundColor = value ? theme.accent.cgColor : theme.controlFill.cgColor
        knob.frame = CGRect(x: value ? 18 : 2, y: 2, width: 14, height: 14)
        if notify { onChange?(value) }
    }

    override func layout() {
        super.layout()
        knob.frame = CGRect(x: isOn ? 18 : 2, y: 2, width: 14, height: 14)
    }

    @objc private func handleToggle() {
        set(isOn: !isOn)
    }
}

/// Themed replacement for NSPopUpButton: a capsule that opens a menu.
final class MenuButton: NSView {
    var onSelect: ((Int) -> Void)?

    private let button: NSButton
    private let titles: [String]
    private(set) var selectedIndex = 0
    private var width: NSLayoutConstraint?

    init(titles: [String]) {
        self.titles = titles
        button = NSButton(title: titles.first ?? "", target: nil, action: nil)
        super.init(frame: .zero)

        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.target = self
        button.action = #selector(handleOpen)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        button.layer?.cornerRadius = 7

        select(0, notify: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ index: Int, notify: Bool = true) {
        guard titles.indices.contains(index) else { return }
        selectedIndex = index
        let theme = SettingsStyle.theme
        button.layer?.backgroundColor = theme.controlFill.cgColor
        button.attributedTitle = NSAttributedString(
            string: titles[index],
            attributes: [
                .foregroundColor: theme.primaryText,
                .font: NSFont.systemFont(ofSize: 12)
            ]
        )
        // The up-and-down chevron macOS's own pop-up menus use, with room around it.
        button.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        button.imagePosition = .imageTrailing
        button.imageHugsTitle = true
        button.contentTintColor = theme.secondaryText
        width?.isActive = false
        // Never so wide that it crowds out the row's own label; a long title is cut in
        // the middle instead, where a path's least telling part is.
        (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        width = widthAnchor.constraint(equalToConstant: min(300, ceil(button.intrinsicContentSize.width) + 22))
        width?.isActive = true
        if notify { onSelect?(index) }
    }

    @objc private func handleOpen() {
        let menu = NSMenu()
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(handlePick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == selectedIndex ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
    }

    @objc private func handlePick(_ sender: NSMenuItem) {
        select(sender.tag)
    }
}
