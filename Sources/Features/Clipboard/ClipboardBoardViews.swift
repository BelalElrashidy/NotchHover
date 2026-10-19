import AppKit

extension NSPasteboard.PasteboardType {
    /// A clip being dragged inside NotchHover — onto a board.
    static let clipboardItem = NSPasteboard.PasteboardType("com.notchhover.clipboard-item")
}

/// One board along the top of the clipboard: a dot in its colour, its name, how many
/// clips it holds. Click to show it; drop a card on it to keep that card there.
final class BoardChipView: NSView {
    var onSelect: (() -> Void)?
    var onDropItem: ((UUID) -> Void)?
    let filter: ClipboardHistory.Filter
    var isSelected = false { didSet { refreshBackground() } }

    private var isDropTarget = false { didSet { refreshBackground() } }

    init(title: String, color: NSColor?, symbol: String? = nil, filter: ClipboardHistory.Filter, count: Int? = nil) {
        self.filter = filter
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        var views: [NSView] = []
        if let color {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            dot.layer?.backgroundColor = color.cgColor
            dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
            views.append(dot)
        } else if let symbol {
            let image = NSImageView(image: Style.symbolImage(symbol, pointSize: 10) ?? NSImage())
            image.contentTintColor = Style.secondaryText
            views.append(image)
        }
        if title.isEmpty == false {
            let label = Style.label(title, size: 11, weight: .medium)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(label)
        }
        if let count { views.append(Style.label("\(count)", size: 10, color: Style.tertiaryText)) }

        let stack = NSStackView(views: views)
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        // A chip is exactly as wide as what it says; it never truncates.
        widthAnchor.constraint(equalToConstant: ceil(stack.fittingSize.width)).isActive = true
        refreshBackground()

        if case .board = filter { toolTip = "\(title) — drop a card here to keep it" }
        if filter != .history { registerForDraggedTypes([.clipboardItem]) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refreshBackground() {
        layer?.backgroundColor = (isSelected ? Style.primaryText.withAlphaComponent(0.2) : Style.controlFill).cgColor
        layer?.borderWidth = isDropTarget ? 1.5 : 0
        layer?.borderColor = Style.accent.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onSelect?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard case .board(let id) = filter else { return nil }
        let menu = NSMenu()
        let rename = NSMenuItem(title: "Rename…", action: #selector(handleRename), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)
        let colors = NSMenuItem(title: "Colour", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for name in ClipboardBoard.palette {
            let item = NSMenuItem(title: name.capitalized, action: #selector(handleColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.image = Self.swatch(ClipboardBoard.color(named: name))
            item.state = ClipboardHistory.shared.boards.first { $0.id == id }?.color == name ? .on : .off
            submenu.addItem(item)
        }
        colors.submenu = submenu
        menu.addItem(colors)
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete board", action: #selector(handleDelete), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 10, height: 10)).fill()
        image.unlockFocus()
        return image
    }

    @objc private func handleRename() {
        guard case .board(let id) = filter, let board = ClipboardHistory.shared.boards.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename board"
        let field = NSTextField(string: board.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardHistory.shared.renameBoard(id, to: field.stringValue.trimmingCharacters(in: .whitespaces))
        }
    }

    @objc private func handleColor(_ sender: NSMenuItem) {
        guard case .board(let id) = filter, let name = sender.representedObject as? String else { return }
        ClipboardHistory.shared.recolorBoard(id, to: name)
    }

    @objc private func handleDelete() {
        guard case .board(let id) = filter else { return }
        ClipboardHistory.shared.deleteBoard(id)
    }

    // MARK: Dropping a card

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTarget = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let string = sender.draggingPasteboard.string(forType: .clipboardItem), let id = UUID(uuidString: string) else { return false }
        onDropItem?(id)
        return true
    }
}

/// One clip as a card: a header saying what it is and where it came from, tinted by
/// kind, and the clip itself below — text, a link, a file, a picture, or a colour.
final class ClipboardCardView: NSView {
    static let size = CGSize(width: 132, height: 92)

    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var onPin: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleBoard: ((UUID) -> Void)?

    let isSelected: Bool
    private let item: ClipboardItem
    private var mouseDownEvent: NSEvent?

    private static let codeSources: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.apple.dt.Xcode", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "dev.zed.Zed"
    ]

    init(item: ClipboardItem, justCopied: Bool, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = Style.controlFill.cgColor
        layer?.borderColor = Style.accent.cgColor
        layer?.borderWidth = isSelected ? 2 : 0
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size.height).isActive = true

        // Header: what it is, and where it came from — or that it was just copied.
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = headerTint.cgColor
        header.frame = CGRect(x: 0, y: Self.size.height - 20, width: Self.size.width, height: 20)
        addSubview(header)

        let kind = Style.label(justCopied ? "Copied" : kindTitle, size: 10, weight: .semibold,
                               color: justCopied ? Style.accent : Style.primaryText)
        kind.frame = CGRect(x: 7, y: 3, width: 56, height: 14)
        header.addSubview(kind)

        // The boards it's on, as dots beside the kind, and a pin.
        kind.frame.size.width = ceil(kind.fittingSize.width)
        var dotX = kind.frame.maxX + 5
        for board in ClipboardHistory.shared.boards.filter({ item.boardIDs?.contains($0.id) == true }).prefix(4) {
            let dot = NSView(frame: CGRect(x: dotX, y: 7, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.backgroundColor = board.nsColor.cgColor
            header.addSubview(dot)
            dotX += 8
        }
        if item.isPinned {
            let pin = NSImageView(image: Style.symbolImage("pin.fill", pointSize: 8) ?? NSImage())
            pin.contentTintColor = Style.accent
            pin.frame = CGRect(x: dotX, y: 5, width: 10, height: 10)
            header.addSubview(pin)
            dotX += 12
        }

        let source = Style.label(item.sourceName ?? "", size: 9, color: Style.secondaryText)
        source.alignment = .right
        source.frame = CGRect(x: dotX + 2, y: 3, width: max(0, Self.size.width - dotX - 9), height: 14)
        header.addSubview(source)

        addBody()
        toolTip = "Click to copy, double-click to paste, drag onto a board — right-click for more"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hexColor: NSColor? {
        guard item.kind == .text, let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.range(of: #"^#?[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil,
              let value = Int(text.replacingOccurrences(of: "#", with: ""), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private var kindTitle: String {
        if hexColor != nil { return "Colour" }
        switch item.kind {
        case .text: return "Text"
        case .link: return "Link"
        case .file: return (item.filePaths?.count ?? 0) > 1 ? "Files" : "File"
        case .image: return "Image"
        }
    }

    private var headerTint: NSColor {
        let base: NSColor
        switch item.kind {
        case .link: base = .systemBlue
        case .file: base = .systemRed
        case .image: base = .systemPurple
        case .text: base = hexColor ?? .gray
        }
        return base.withAlphaComponent(0.22)
    }

    private func addBody() {
        let area = CGRect(x: 7, y: 6, width: Self.size.width - 14, height: Self.size.height - 32)

        if let color = hexColor {
            let swatch = NSView(frame: CGRect(x: area.minX, y: area.midY - 13, width: 26, height: 26))
            swatch.wantsLayer = true
            swatch.layer?.cornerRadius = 6
            swatch.layer?.backgroundColor = color.cgColor
            addSubview(swatch)
            let label = Style.label(item.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "", size: 11, weight: .medium)
            label.frame = CGRect(x: area.minX + 34, y: area.midY - 8, width: area.width - 34, height: 16)
            addSubview(label)
            return
        }

        switch item.kind {
        case .image:
            let image = NSImageView(frame: CGRect(x: 0, y: 0, width: Self.size.width, height: Self.size.height - 20))
            image.image = ClipboardHistory.shared.image(for: item)
            image.imageScaling = .scaleProportionallyUpOrDown
            addSubview(image)
        case .file:
            let icon = NSImageView(frame: CGRect(x: area.minX, y: area.midY - 14, width: 28, height: 28))
            icon.image = (item.filePaths?.first).map { NSWorkspace.shared.icon(forFile: $0) }
            addSubview(icon)
            // File names break badly across lines; one line, with the middle left out.
            let name = Style.label(item.preview, size: 11)
            name.lineBreakMode = .byTruncatingMiddle
            let height = name.fittingSize.height
            name.frame = CGRect(x: area.minX + 34, y: area.midY - height / 2, width: area.width - 34, height: height)
            addSubview(name)
        case .text, .link:
            let isCode = item.sourceBundleIdentifier.map(Self.codeSources.contains) ?? false
            var text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if item.kind == .link, let url = URL(string: text), let host = url.host {
                text = host.replacingOccurrences(of: "www.", with: "") + url.path
            }
            let label = NSTextField(wrappingLabelWithString: String(text.prefix(300)))
            label.font = isCode
                ? .monospacedSystemFont(ofSize: Style.scaled(10), weight: .regular)
                : .systemFont(ofSize: Style.scaled(11))
            label.textColor = item.kind == .link ? NSColor.systemBlue.blended(withFraction: 0.35, of: .white) : Style.primaryText
            label.maximumNumberOfLines = 4
            label.lineBreakMode = .byWordWrapping
            label.cell?.truncatesLastVisibleLine = true
            let height = min(area.height, label.sizeThatFits(CGSize(width: area.width, height: area.height)).height)
            label.frame = CGRect(x: area.minX, y: area.maxY - height, width: area.width, height: height)
            addSubview(label)
        }
    }

    // MARK: Clicks and drags

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The card is one thing to click: its labels and images never take the mouse.
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent,
              hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 4 else { return }
        mouseDownEvent = nil
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.id.uuidString, forType: .clipboardItem)
        // Dragged out of NotchHover, it carries the clip itself.
        switch item.kind {
        case .text, .link: pasteboardItem.setString(item.text ?? "", forType: .string)
        case .file: if let path = item.filePaths?.first { pasteboardItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL) }
        case .image: if let data = ClipboardHistory.shared.image(for: item)?.tiffRepresentation { pasteboardItem.setData(data, forType: .tiff) }
        }
        let dragging = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let snapshot = bitmapImageRepForCachingDisplay(in: bounds).map { rep -> NSImage in
            cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return image
        }
        dragging.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [dragging], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        event.clickCount >= 2 ? onPaste?() : onCopy?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        add("Copy", #selector(handleCopy))
        add("Paste into the front app", #selector(handlePaste))
        add(item.isPinned ? "Unpin" : "Pin", #selector(handlePin))

        let boards = ClipboardHistory.shared.boards
        if boards.isEmpty == false {
            let onBoards = NSMenuItem(title: "Boards", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for board in boards {
                let entry = NSMenuItem(title: board.name, action: #selector(handleBoard(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = board.id
                entry.state = item.boardIDs?.contains(board.id) == true ? .on : .off
                submenu.addItem(entry)
            }
            onBoards.submenu = submenu
            menu.addItem(onBoards)
        }
        menu.addItem(.separator())
        add("Delete", #selector(handleDelete))
        return menu
    }

    @objc private func handleCopy() { onCopy?() }
    @objc private func handlePaste() { onPaste?() }
    @objc private func handlePin() { onPin?() }
    @objc private func handleDelete() { onDelete?() }
    @objc private func handleBoard(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onToggleBoard?(id)
    }
}

extension ClipboardCardView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
