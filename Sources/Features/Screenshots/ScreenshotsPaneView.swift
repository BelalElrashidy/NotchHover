import AppKit

/// A screenshot's thumbnail that behaves like the file: drag it into any app, click it
/// for whatever the view decides, double-click to open it in Preview.
final class ScreenshotThumbnailView: NSImageView {
    let url: URL
    var onClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?

    init(url: URL, side: CGFloat) {
        self.url = url
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = Style.controlFill.cgColor
        image = Self.thumbnail(of: url, maxPixels: side * 2 * (NSScreen.main?.backingScaleFactor ?? 2))
        toolTip = "Drag it anywhere · double-click to open"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func thumbnail(of url: URL, maxPixels: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels
              ] as CFDictionary) else { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(cgImage: image, size: .zero)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            mouseDownEvent = nil
            ScreenshotStore.markup(url)
            return
        }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent,
              hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 4 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        onClick?()
    }
}

extension ScreenshotThumbnailView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// The Screenshots view: take one — an area, a window, the screen, or in five seconds —
/// and the recent ones as a strip, each with copy, markup, copy-the-text and delete.
final class ScreenshotsPaneView: NSView {
    /// Taking a screenshot puts the panel away first, so it isn't in the picture.
    var onCapture: ((ScreenshotStore.Capture) -> Void)?

    private let titleLabel = Style.label("Screenshots", size: 12, weight: .semibold)
    private let countLabel = Style.label("", size: 11, color: Style.secondaryText)
    private let captureStack = NSStackView()
    private let stripStack = NSStackView()
    private let stripScroll = NSScrollView()
    private let emptyLabel = Style.label("", size: 11, color: Style.secondaryText)
    private var observer: UUID?

    init() {
        super.init(frame: .zero)

        for (index, kind) in ScreenshotStore.Capture.allCases.enumerated() {
            let button = ClickThroughButton(title: kind.title, target: self, action: #selector(handleCapture(_:)))
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.backgroundColor = (index == 0 ? Style.accent : Style.controlFill).cgColor
            button.image = Style.symbolImage(kind.symbol, pointSize: 10)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.contentTintColor = index == 0 ? Style.theme.onAccentText : Style.primaryText
            button.attributedTitle = NSAttributedString(string: kind.title, attributes: [
                .foregroundColor: index == 0 ? Style.theme.onAccentText : Style.primaryText,
                .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: .medium)
            ])
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            button.widthAnchor.constraint(equalToConstant: button.intrinsicContentSize.width + 16).isActive = true
            button.toolTip = kind == .area ? "Capture an area — ⌃⌥4" : "Capture the \(kind.title.lowercased())"
            captureStack.addArrangedSubview(button)
        }
        captureStack.spacing = 6

        let header = NSStackView(views: [titleLabel, countLabel, NSView(), captureStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        stripStack.orientation = .horizontal
        stripStack.alignment = .top
        stripStack.spacing = 10
        stripStack.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stripStack)
        stripScroll.documentView = document
        stripScroll.drawsBackground = false
        stripScroll.hasHorizontalScroller = false
        stripScroll.horizontalScrollElasticity = .allowed
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stripScroll)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stripScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stripScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stripScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            stripScroll.heightAnchor.constraint(equalToConstant: ScreenshotTileView.size.height),
            document.topAnchor.constraint(equalTo: stripScroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: stripScroll.contentView.leadingAnchor),
            document.heightAnchor.constraint(equalTo: stripScroll.contentView.heightAnchor),
            stripStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stripStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stripStack.topAnchor.constraint(equalTo: document.topAnchor)
        ])

        observer = ScreenshotStore.shared.addObserver { [weak self] in self?.reload() }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let items = ScreenshotStore.shared.items
        countLabel.stringValue = items.isEmpty ? "" : "\(items.count) in \(ScreenshotStore.folder.lastPathComponent)"
        stripStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard items.isEmpty == false else {
            emptyLabel.stringValue = "Screenshots you take (⇧⌘4, or the buttons above) show up here"
            stripStack.addArrangedSubview(emptyLabel)
            return
        }
        for url in items.prefix(20) {
            stripStack.addArrangedSubview(ScreenshotTileView(url: url))
        }
    }

    @objc private func handleCapture(_ sender: NSButton) {
        let kinds = ScreenshotStore.Capture.allCases
        guard kinds.indices.contains(sender.tag) else { return }
        onCapture?(kinds[sender.tag])
    }
}

/// One screenshot in the strip: the picture, when it was taken, and its actions on hover.
final class ScreenshotTileView: NSView {
    static let size = CGSize(width: 128, height: 98)

    private let url: URL
    private let actions = NSStackView()

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size.height).isActive = true

        let thumbnail = ScreenshotThumbnailView(url: url, side: Self.size.width)
        thumbnail.frame = CGRect(x: 0, y: 18, width: Self.size.width, height: Self.size.height - 18)
        thumbnail.onClick = { ScreenshotStore.copy(url) }
        thumbnail.toolTip = "Click to copy · drag it anywhere · double-click for Markup"
        addSubview(thumbnail)

        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let time = Style.label(Calendar.current.isDateInToday(created)
                               ? created.formatted(date: .omitted, time: .shortened)
                               : RelativeTime.string(for: created), size: 10, color: Style.secondaryText)
        time.frame = CGRect(x: 2, y: 0, width: Self.size.width - 4, height: 14)
        addSubview(time)

        // The actions sit on the picture and show while the pointer is over it.
        for (symbol, tip, action) in [("doc.on.doc", "Copy", #selector(handleCopy)), ("pencil.tip", "Markup", #selector(handleMarkup)),
                                      ("text.viewfinder", "Copy text", #selector(handleText)), ("trash", "Move to Trash", #selector(handleDelete))] {
            let button = Style.symbolButton(symbol, pointSize: 10, target: self, action: action)
            button.toolTip = tip
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
            button.contentTintColor = .white
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 20).isActive = true
            actions.addArrangedSubview(button)
        }
        actions.spacing = 4
        actions.frame = CGRect(x: (Self.size.width - 100) / 2, y: 24, width: 100, height: 20)
        actions.isHidden = true
        addSubview(actions)

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseEntered(with event: NSEvent) { actions.isHidden = false }
    override func mouseExited(with event: NSEvent) { actions.isHidden = true }

    @objc private func handleCopy() { ScreenshotStore.copy(url); Haptics.tick() }
    @objc private func handleMarkup() { ScreenshotStore.markup(url) }
    @objc private func handleText() { FileActionRunner.run(.copyText, on: [url]) }
    @objc private func handleDelete() { ScreenshotStore.shared.delete(url) }
}
