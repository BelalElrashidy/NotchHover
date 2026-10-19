import AppKit
import QuickLookThumbnailing

/// The file shelf: files parked on the notch as tiles with their own thumbnails. Click to
/// select, drag one out, double-click to open. Underneath, the actions that fit what is
/// selected — or everything, when nothing is — as Droppy and Dropover offer them:
/// convert, resize, copy the text, cut out the subject, make a PDF, zip, AirDrop.
final class TrayPaneView: NSView {
    private let hintLabel = Style.label("Drop files on the notch to park them", size: 11, color: Style.secondaryText)
    private let itemsStack = NSStackView()
    private let chipsStack = NSStackView()
    private let chipsScroll = NSScrollView()
    private lazy var shareButton = Style.pushButton("Send", prominent: true, target: self, action: #selector(handleShare))
    private lazy var clearButton = Style.pushButton("Clear", prominent: false, target: self, action: #selector(handleClear))

    private let isCompact: Bool
    private var selection = Set<URL>()
    private var chipActions: [() -> Void] = []

    init(isCompact: Bool = false) {
        self.isCompact = isCompact
        super.init(frame: .zero)

        itemsStack.orientation = .horizontal
        itemsStack.alignment = .top
        itemsStack.spacing = isCompact ? 6 : 10

        chipsStack.orientation = .horizontal
        chipsStack.spacing = 6
        chipsScroll.documentView = chipsStack
        chipsScroll.drawsBackground = false
        chipsScroll.hasHorizontalScroller = false
        chipsScroll.horizontalScrollElasticity = .allowed
        chipsStack.translatesAutoresizingMaskIntoConstraints = false

        let views: [NSView] = isCompact
            ? [hintLabel, itemsStack, { let row = NSStackView(views: [shareButton, clearButton]); row.spacing = 8; return row }()]
            : [hintLabel, itemsStack, chipsScroll]
        let root = NSStackView(views: views)
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = isCompact ? 8 : 9
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        if isCompact == false {
            NSLayoutConstraint.activate([
                root.widthAnchor.constraint(equalTo: widthAnchor, constant: -20),
                chipsScroll.heightAnchor.constraint(equalToConstant: 24),
                chipsScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
                chipsStack.topAnchor.constraint(equalTo: chipsScroll.contentView.topAnchor),
                chipsStack.leadingAnchor.constraint(equalTo: chipsScroll.contentView.leadingAnchor),
                chipsStack.heightAnchor.constraint(equalToConstant: 24)
            ])
        }

        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let items = FileTray.shared.items
        selection.formIntersection(items)

        if items.isEmpty {
            hintLabel.stringValue = isCompact ? "Drop files here" : "Drop files on the notch to keep them here, or onto an action"
        } else {
            let count = "\(items.count) item\(items.count == 1 ? "" : "s")"
            hintLabel.stringValue = selection.isEmpty
                ? (isCompact ? count : "\(count) · click to select, drag one out")
                : "\(count) · \(selection.count) selected"
        }

        itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for url in items.prefix(isCompact ? 4 : 8) {
            let tile = TrayItemView(url: url, isCompact: isCompact)
            tile.isSelected = selection.contains(url)
            tile.onToggle = { [weak self] in self?.toggle(url) }
            itemsStack.addArrangedSubview(tile)
        }

        [shareButton, clearButton].forEach {
            $0.isEnabled = items.isEmpty == false
            $0.alphaValue = items.isEmpty ? 0.4 : 1
        }
        if isCompact == false { rebuildChips(items: items) }
    }

    private func toggle(_ url: URL) {
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
        Haptics.tick()
        reload()
    }

    /// What the chips act on: the selection, or the whole shelf.
    private var targets: [URL] {
        let items = FileTray.shared.items
        return selection.isEmpty ? items : items.filter(selection.contains)
    }

    private func rebuildChips(items: [URL]) {
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chipActions = []
        chipsScroll.isHidden = items.isEmpty
        guard items.isEmpty == false else { return }

        func add(_ title: String, _ symbol: String, prominent: Bool = false, _ action: @escaping () -> Void) {
            let chip = Self.chip(title, symbol: symbol, prominent: prominent, tag: chipActions.count, target: self, action: #selector(handleChip(_:)))
            chipActions.append(action)
            chipsStack.addArrangedSubview(chip)
        }

        for action in FileAction.actions(for: targets) {
            add(action.title, action.symbol) { [weak self] in
                guard let self else { return }
                FileActionRunner.run(action, on: self.targets)
            }
        }
        add("AirDrop", "paperplane.fill") { [weak self] in
            guard let self else { return }
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: self.targets)
        }
        add("Show in Finder", "folder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting(self.targets)
        }
        add(selection.isEmpty ? "Clear" : "Remove", "xmark") { [weak self] in
            guard let self else { return }
            if self.selection.isEmpty {
                FileTray.shared.clear()
            } else {
                self.targets.forEach(FileTray.shared.remove)
                self.selection.removeAll()
            }
        }
    }

    @objc private func handleChip(_ sender: NSButton) {
        guard chipActions.indices.contains(sender.tag) else { return }
        Haptics.tick()
        chipActions[sender.tag]()
    }

    private static func chip(_ title: String, symbol: String, prominent: Bool, tag: Int, target: AnyObject, action: Selector) -> NSButton {
        let button = ClickThroughButton(title: title, target: target, action: action)
        button.tag = tag
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = Style.controlFill.cgColor
        button.image = Style.symbolImage(symbol, pointSize: 10)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.contentTintColor = Style.primaryText
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: Style.primaryText, .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: .medium)
        ])
        button.toolTip = title
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.widthAnchor.constraint(equalToConstant: button.intrinsicContentSize.width + 18).isActive = true
        return button
    }

    @objc private func handleShare() {
        FileTray.shared.share(from: shareButton)
    }

    /// The share sheet — where AirDrop lives — for ⌘S.
    func share() {
        guard FileTray.shared.items.isEmpty == false else { return }
        let picker = NSSharingServicePicker(items: targets)
        picker.show(relativeTo: itemsStack.bounds, of: itemsStack, preferredEdge: .minY)
    }

    @objc private func handleClear() {
        FileTray.shared.clear()
    }
}

/// One parked file: its thumbnail and name. Click to select, drag it out, double-click
/// to open it.
final class TrayItemView: NSView {
    var onToggle: (() -> Void)?
    var isSelected = false {
        didSet {
            thumbnail.layer?.borderWidth = isSelected ? 2 : 0
            nameLabel.textColor = isSelected ? Style.primaryText : Style.secondaryText
        }
    }

    private let url: URL
    private let thumbnail = ClickThroughImageView()
    private let nameLabel: NSTextField
    private var mouseDownEvent: NSEvent?

    init(url: URL, isCompact: Bool = false) {
        self.url = url
        nameLabel = Style.label(url.lastPathComponent, size: 10, color: Style.secondaryText)
        super.init(frame: .zero)

        let side: CGFloat = isCompact ? 34 : 44
        thumbnail.image = NSWorkspace.shared.icon(forFile: url.path)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 8
        thumbnail.layer?.borderColor = Style.accent.cgColor
        thumbnail.toolTip = url.lastPathComponent
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.alignment = .center
        nameLabel.isHidden = isCompact

        [thumbnail, nameLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: isCompact ? side : 70),
            thumbnail.widthAnchor.constraint(equalToConstant: side),
            thumbnail.heightAnchor.constraint(equalToConstant: side),
            thumbnail.topAnchor.constraint(equalTo: topAnchor),
            thumbnail.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 3),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomAnchor.constraint(equalTo: isCompact ? thumbnail.bottomAnchor : nameLabel.bottomAnchor)
        ])

        loadThumbnail(side: side)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Quick Look's own thumbnail — the picture itself for an image, the first page of a
    /// PDF — made on the Mac, falling back to the file's icon.
    private func loadThumbnail(side: CGFloat) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        // Pictures are read straight from the file: quick, and works without Quick Look.
        if FileAction.kind(of: url) == .image,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: side * scale
           ] as CFDictionary) {
            thumbnail.image = NSImage(cgImage: image, size: NSSize(width: side, height: side))
            thumbnail.imageScaling = .scaleProportionallyUpOrDown
            thumbnail.layer?.masksToBounds = true
            return
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async { self?.thumbnail.image = image }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            NSWorkspace.shared.open(url)
            mouseDownEvent = nil
            return
        }
        mouseDownEvent = event
    }

    /// A drag that moves a few points takes the file out; a click without one selects.
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 4 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(thumbnail.frame, contents: thumbnail.image)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        onToggle?()
    }
}

extension TrayItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy out of the tray: the file itself never moves.
        .copy
    }
}
