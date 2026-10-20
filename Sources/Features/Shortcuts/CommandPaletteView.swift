import AppKit

/// ⌘K in the notch, after Raycast's action panel: every action NotchHover has — built in
/// and yours — with its keys. Type to narrow it, ↵ to run, ⌘E to change a hotkey. It is
/// also the list of shortcuts: ⌘/ opens it too.
final class CommandPaletteView: NSView, NSTextFieldDelegate {
    /// Runs after the panel is out of the way.
    var onRun: ((NotchAction, String?) -> Void)?
    var onClose: (() -> Void)?
    /// ⌘E: change this action's hotkey in Settings.
    var onEdit: ((NotchAction) -> Void)?

    private let field = ClipboardSearchField()
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let footer = Style.label("↵ run   ⌘E change its hotkey   ⎋ close", size: 10, color: Style.tertiaryText)
    private let promptChip = Style.label("", size: 11, weight: .semibold)
    private var results: [NotchAction] = []
    private var selectedID: String?
    /// A quicklink waiting for its word.
    private var argumentFor: NotchAction?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Style.theme.windowBackground.withAlphaComponent(0.97).cgColor
        layer?.cornerRadius = 14

        field.font = .systemFont(ofSize: Style.scaled(13))
        field.textColor = Style.primaryText
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 8
        field.layer?.backgroundColor = Style.fieldFill.cgColor
        field.delegate = self

        promptChip.wantsLayer = true
        promptChip.drawsBackground = true
        promptChip.backgroundColor = Style.accent.withAlphaComponent(0.25)
        promptChip.isHidden = true

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 1
        list.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let fieldRow = NSStackView(views: [promptChip, field])
        fieldRow.spacing = 6
        fieldRow.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        [fieldRow, scroll, footer].forEach(addSubview)

        NSLayoutConstraint.activate([
            fieldRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            fieldRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            fieldRow.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            field.heightAnchor.constraint(equalToConstant: 26),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: fieldRow.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])

        ActionRegistry.shared.addObserver { [weak self] in self?.reload() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Opens fresh: empty search, the first action chosen, the cursor in the field.
    func begin() {
        argumentFor = nil
        field.stringValue = ""
        selectedID = nil
        reload()
        window?.makeKey()
        window?.makeFirstResponder(field)
    }

    private func reload() {
        if let action = argumentFor {
            promptChip.stringValue = "  \(action.title)  "
            promptChip.isHidden = false
            field.placeholderString = "Type, then ↵"
        } else {
            promptChip.isHidden = true
            field.placeholderAttributedString = NSAttributedString(
                string: "Search actions and shortcuts",
                attributes: [.foregroundColor: Style.tertiaryText, .font: NSFont.systemFont(ofSize: Style.scaled(13))]
            )
        }

        let registry = ActionRegistry.shared
        let words = field.stringValue.lowercased().split(separator: " ").map(String.init)
        results = argumentFor != nil ? [] : registry.actions.filter { action in
            guard registry.isEnabled(action.id) else { return false }
            let haystack = "\(action.title) \(action.group)".lowercased()
            return words.allSatisfy(haystack.contains)
        }
        if results.contains(where: { $0.id == selectedID }) == false { selectedID = results.first?.id }

        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for action in results {
            let row = PaletteRow(action: action, hotkey: registry.hotkey(for: action.id), isSelected: action.id == selectedID)
            row.onRun = { [weak self] in self?.choose(action) }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if results.isEmpty, argumentFor == nil {
            list.addArrangedSubview(Style.label("No action matches", size: 11, color: Style.tertiaryText))
        }
    }

    private func move(by offset: Int) {
        guard results.isEmpty == false else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(current + offset, 0), results.count - 1)].id
        reload()
        list.arrangedSubviews.first { ($0 as? PaletteRow)?.isSelected == true }.map { $0.scrollToVisible($0.bounds) }
    }

    private func choose(_ action: NotchAction) {
        if action.argumentPrompt != nil, argumentFor == nil {
            argumentFor = action
            field.stringValue = ""
            reload()
            return
        }
        onRun?(action, nil)
    }

    // MARK: Keys

    func controlTextDidChange(_ obj: Notification) {
        guard argumentFor == nil else { return }
        selectedID = nil
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(by: -1); return true
        case #selector(NSResponder.moveDown(_:)): move(by: 1); return true
        case #selector(NSResponder.insertNewline(_:)):
            if let action = argumentFor {
                onRun?(action, field.stringValue)
            } else if let action = results.first(where: { $0.id == selectedID }) {
                choose(action)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if argumentFor != nil {
                argumentFor = nil
                field.stringValue = ""
                reload()
            } else {
                onClose?()
            }
            return true
        default:
            return false
        }
    }

    /// ⌘E, from the panel's key handling.
    func editSelected() {
        guard let action = results.first(where: { $0.id == selectedID }) else { return }
        onEdit?(action)
    }

    var selectedTitle: String? { results.first { $0.id == selectedID }?.title }
}

/// One action: its icon and name, where it belongs, and its keys as keycaps.
private final class PaletteRow: NSView {
    var onRun: (() -> Void)?
    let isSelected: Bool

    init(action: NotchAction, hotkey: KeyCombo?, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = isSelected ? Style.primaryText.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor

        let icon = NSImageView(image: Style.symbolImage(action.symbol, pointSize: 12) ?? NSImage())
        icon.contentTintColor = Style.secondaryText
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let title = Style.label(action.title, size: 12, weight: .medium)
        let group = Style.label(action.isCustom ? (action.argumentPrompt == nil ? "Yours" : "Yours · asks for a word") : action.group,
                                size: 10, color: Style.tertiaryText)
        title.setContentCompressionResistancePriority(.init(700), for: .horizontal)
        group.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Priorities alone lost this fight on the first row; the text's own width is a floor.
        group.widthAnchor.constraint(greaterThanOrEqualToConstant: ceil(group.intrinsicContentSize.width)).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        var views: [NSView] = [icon, title, group, spacer]
        if let hotkey { views.append(Keycaps(hotkey.parts)) }
        if let panelKeys = action.panelKeys {
            // Its key inside the panel, quieter than a hotkey that works everywhere.
            let label = Style.label(panelKeys, size: 10, color: Style.tertiaryText)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: ceil(label.intrinsicContentSize.width)).isActive = true
            label.toolTip = "In the open panel"
            views.append(label)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onRun?() }
}

/// Keys drawn as keycaps: ⌃ ⌥ H.
final class Keycaps: NSStackView {
    init(_ parts: [String]) {
        super.init(frame: .zero)
        spacing = 3
        for part in parts {
            let cap = Style.label(part, size: 10, weight: .medium)
            cap.alignment = .center
            cap.wantsLayer = true
            cap.drawsBackground = true
            cap.backgroundColor = Style.controlFill
            cap.layer?.cornerRadius = 4
            cap.layer?.borderWidth = 0.5
            cap.layer?.borderColor = Style.primaryText.withAlphaComponent(0.18).cgColor
            cap.widthAnchor.constraint(greaterThanOrEqualToConstant: 17).isActive = true
            cap.heightAnchor.constraint(equalToConstant: 17).isActive = true
            addArrangedSubview(cap)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
