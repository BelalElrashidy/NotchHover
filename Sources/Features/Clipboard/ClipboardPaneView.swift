import AppKit

/// Borderless text fields draw their text pinned to the top; this centres it and pads
/// the sides, for both drawing and the live editor.
final class CenteredTextFieldCell: NSTextFieldCell {
    private func adjusted(_ rect: NSRect) -> NSRect {
        var result = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        let offset = max(0, (result.height - textHeight) / 2)
        result.origin.y += offset
        result.size.height -= offset
        return result.insetBy(dx: 6, dy: 0)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        adjusted(rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: adjusted(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: adjusted(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

final class ClipboardSearchField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CenteredTextFieldCell.self }
        set {}
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Clipboard history: search, click to copy, paste straight into the front app.
final class ClipboardPaneView: NSView, NSTextFieldDelegate {
    /// Paste needs the panel out of the way first, so the controller handles it.
    var onPaste: ((ClipboardItem) -> Void)?
    var onDismiss: (() -> Void)?

    private let isCompact: Bool
    private let searchField = ClipboardSearchField()
    private lazy var pauseButton = Style.symbolButton("pause.circle", pointSize: 13, target: self, action: #selector(handlePause))
    private lazy var clearButton = Style.symbolButton("trash", pointSize: 12, target: self, action: #selector(handleClear))
    private let listStack = NSStackView()
    private let emptyLabel = Style.label("", size: 11, color: nil)
    private var observer: UUID?
    private var copiedID: UUID?

    init(isCompact: Bool = false) {
        self.isCompact = isCompact
        super.init(frame: .zero)
        configure()
        observer = ClipboardHistory.shared.addObserver { [weak self] in self?.reload() }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer { ClipboardHistory.shared.removeObserver(observer) }
    }

    private func configure() {
        emptyLabel.textColor = Style.tertiaryText

        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search clipboard — ↩ copies the top result",
            attributes: [.foregroundColor: Style.tertiaryText, .font: NSFont.systemFont(ofSize: Style.scaled(12))]
        )
        searchField.font = .systemFont(ofSize: Style.scaled(12))
        searchField.textColor = Style.primaryText
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 7
        searchField.layer?.cornerCurve = .continuous
        searchField.layer?.backgroundColor = Style.controlFill.cgColor
        searchField.delegate = self

        pauseButton.toolTip = "Pause recording"
        clearButton.toolTip = "Clear history (pinned items stay)"
        [pauseButton, clearButton].forEach { $0.contentTintColor = Style.secondaryText }

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 1

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(listStack)

        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        var constraints = [
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: document.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ]

        if isCompact {
            constraints.append(scroll.topAnchor.constraint(equalTo: topAnchor, constant: 6))
        } else {
            let header = NSStackView(views: [searchField, pauseButton, clearButton])
            header.orientation = .horizontal
            header.alignment = .centerY
            header.spacing = 8
            header.translatesAutoresizingMaskIntoConstraints = false
            addSubview(header)
            constraints += [
                header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                searchField.heightAnchor.constraint(equalToConstant: 24),
                scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6)
            ]
        }

        NSLayoutConstraint.activate(constraints)
    }

    /// Puts the cursor in search, for the keyboard shortcut.
    func focus() {
        window?.makeFirstResponder(searchField)
    }

    // MARK: - List

    private var results: [ClipboardItem] {
        ClipboardHistory.shared.search(isCompact ? "" : searchField.stringValue)
    }

    private func reload() {
        let history = ClipboardHistory.shared
        pauseButton.image = Style.symbolImage(history.isPaused ? "play.circle" : "pause.circle", pointSize: 13)
        pauseButton.toolTip = history.isPaused ? "Resume recording" : "Pause recording"

        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let items = results.prefix(isCompact ? 4 : 60)
        guard items.isEmpty == false else {
            emptyLabel.stringValue = history.isPaused
                ? "Recording is paused"
                : (searchField.stringValue.isEmpty ? "Copy something and it appears here" : "No matches")
            listStack.addArrangedSubview(emptyLabel)
            return
        }

        for item in items {
            let row = ClipboardRowView(item: item, isCompact: isCompact, justCopied: item.id == copiedID)
            row.onCopy = { [weak self] in self?.copy(item) }
            row.onPaste = { [weak self] in self?.onPaste?(item) }
            row.onPin = { ClipboardHistory.shared.togglePin(item.id) }
            row.onDelete = { ClipboardHistory.shared.delete(item.id) }
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func copy(_ item: ClipboardItem) {
        ClipboardHistory.shared.copy(item)
        copiedID = item.id
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard self?.copiedID == item.id else { return }
            self?.copiedID = nil
            self?.reload()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if let first = results.first { copy(first) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty {
                onDismiss?()
            } else {
                searchField.stringValue = ""
                reload()
            }
            return true
        default:
            return false
        }
    }

    @objc private func handlePause() {
        ClipboardHistory.shared.isPaused.toggle()
    }

    @objc private func handleClear() {
        ClipboardHistory.shared.clear()
    }
}

/// One clipboard entry.
final class ClipboardRowView: NSView {
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?

    init(item: ClipboardItem, isCompact: Bool, justCopied: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = justCopied ? Style.accent.withAlphaComponent(0.25).cgColor : NSColor.clear.cgColor

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        switch item.kind {
        case .image:
            icon.image = ClipboardHistory.shared.image(for: item)
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 3
            icon.layer?.masksToBounds = true
        case .file:
            icon.image = (item.filePaths?.first).map { NSWorkspace.shared.icon(forFile: $0) }
        default:
            icon.image = Style.symbolImage(item.symbol, pointSize: 11)
            icon.contentTintColor = Style.secondaryText
        }

        let preview = Style.label(item.preview, size: 11)
        preview.lineBreakMode = .byTruncatingTail
        // The preview gives way first; the source and time must stay whole.
        preview.setContentCompressionResistancePriority(.init(200), for: .horizontal)

        let meta = Style.label(
            justCopied ? "Copied" : [item.sourceName, RelativeTime.string(for: item.copied)].compactMap { $0 }.joined(separator: " · "),
            size: 9,
            color: justCopied ? Style.accent : Style.tertiaryText
        )
        // Priorities alone lost this fight and clipped the time; its own text width is
        // a hard floor instead.
        meta.widthAnchor.constraint(greaterThanOrEqualToConstant: ceil(meta.intrinsicContentSize.width) + 2).isActive = true
        meta.setContentHuggingPriority(.required, for: .horizontal)
        preview.setContentHuggingPriority(.init(1), for: .horizontal)

        var views: [NSView] = [icon, preview, meta]
        if item.isPinned {
            let pin = NSImageView()
            pin.image = Style.symbolImage("pin.fill", pointSize: 8)
            pin.contentTintColor = Style.accent
            views.insert(pin, at: 2)
        }

        if isCompact == false {
            let paste = Style.symbolButton("arrow.down.doc", pointSize: 10, target: self, action: #selector(handlePaste))
            paste.toolTip = AXIsProcessTrusted() ? "Paste into the front app" : "Paste needs Accessibility access — copies instead"
            let pin = Style.symbolButton(item.isPinned ? "pin.slash" : "pin", pointSize: 10, target: self, action: #selector(handlePin))
            pin.toolTip = item.isPinned ? "Unpin" : "Pin — survives clearing"
            let delete = Style.symbolButton("xmark", pointSize: 9, target: self, action: #selector(handleDelete))
            delete.toolTip = "Delete"
            [paste, pin, delete].forEach { $0.contentTintColor = Style.tertiaryText }
            views += [paste, pin, delete]
        }

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onCopy?() }
    @objc private func handlePaste() { onPaste?() }
    @objc private func handlePin() { onPin?() }
    @objc private func handleDelete() { onDelete?() }
}
