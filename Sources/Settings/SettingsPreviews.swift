import AppKit

/// The notch as it looks right now, on a stand-in desktop, pinned to the top of the
/// Appearance and Layout panes — Bartender's menu bar preview, for a notch. It redraws
/// on every change, and switches between resting, peek and open.
final class NotchStageView: NSView {
    private let imageView = NSImageView()
    private let picker = SegmentedRow(labels: ["Resting", "Peek", "Open"])
    private var presentation: NotchContentView.Presentation = .expanded
    var theme: Theme = ThemeStore.selected

    static let height: CGFloat = 176

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        picker.select(2, notify: false)
        picker.onSelect = { [weak self] index in
            self?.presentation = [.idle, .peek, .expanded][index]
            self?.refresh()
        }
        [imageView, picker].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            picker.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The same stand-in desktop the picture is drawn on, so its edges disappear.
    override func makeBackingLayer() -> CALayer {
        let desktop = CAGradientLayer()
        desktop.colors = [NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1).cgColor,
                          NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.42, alpha: 1).cgColor]
        desktop.startPoint = CGPoint(x: 0, y: 0)
        desktop.endPoint = CGPoint(x: 1, y: 1)
        return desktop
    }

    func refresh() {
        // A wide margin of desktop, so the notch sits in a scene rather than filling it.
        let image = PreviewRenderer.snapshot(theme: theme, width: 760, presentation: presentation, margin: 90)
        imageView.image = image
        // The picture is the stage: the desktop fills it edge to edge.
        if let image, image.size.height > 0 {
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: image.size.width / image.size.height).isActive = true
        }
    }
}

extension NSPasteboard.PasteboardType {
    static let panelWidget = NSPasteboard.PasteboardType("com.notchhover.panel-widget")
}

/// The Home row drawn as the panel: each widget a tile as wide as it would be. Drag a
/// tile sideways to move it, hover for × to take it out, drop one from the gallery in.
/// NotchNook's "Customize widgets" and Crest's tiles, without the cell grid our widgets
/// don't have.
final class PanelCanvasView: NSView {
    var onChange: (() -> Void)?

    private var widgets: [PanelWidget] = []
    private var dragging: (widget: PanelWidget, offset: CGFloat, x: CGFloat)?
    private var hovered: PanelWidget?
    private var dropIndex: Int?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        registerForDraggedTypes([.panelWidget])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        widgets = PanelLayoutStore.widgets
        needsDisplay = true
    }

    private var slab: CGRect { bounds.insetBy(dx: 24, dy: 0).offsetBy(dx: 0, dy: -1).insetBy(dx: 0, dy: 1) }

    /// How much room a widget takes, as the panel's flex layout would give it; an empty
    /// slot — where a dragged-in widget will land — is a middling one.
    private static func weight(_ widget: PanelWidget?) -> CGFloat {
        widget.map { $0.idealWidth + $0.grow * 60 } ?? 220
    }

    private func frames(for list: [PanelWidget?]) -> [CGRect] {
        let area = CGRect(x: slab.minX + 16, y: 30, width: slab.width - 32, height: bounds.height - 44)
        let gap: CGFloat = 8
        let total = list.reduce(0) { $0 + Self.weight($1) }
        let available = area.width - gap * CGFloat(max(0, list.count - 1))
        var x = area.minX
        return list.map { widget in
            let width = total > 0 ? available * Self.weight(widget) / total : 0
            defer { x += width + gap }
            return CGRect(x: x, y: area.minY, width: width, height: area.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let theme = SettingsKit.theme
        // The panel's slab, hanging from the top like the real one.
        let path = NSBezierPath(roundedRect: CGRect(x: slab.minX, y: -20, width: slab.width, height: bounds.height + 20), xRadius: 22, yRadius: 22)
        if case .solid(let color) = theme.surface { color.setFill() } else { NSColor.black.setFill() }
        path.fill()

        var list: [PanelWidget?] = widgets
        if let dragging, let from = list.firstIndex(of: dragging.widget) {
            list.remove(at: from)
            list.insert(dragging.widget, at: insertionIndex(for: dragging.x, in: list.compactMap { $0 }))
        } else if let dropIndex {
            list.insert(nil, at: min(dropIndex, list.count))
        }
        let tiles = frames(for: list)

        for (index, slot) in list.enumerated() {
            let frame = tiles[index]
            let tile = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
            guard let widget = slot else {
                theme.accent.withAlphaComponent(0.25).setFill()
                tile.fill()
                continue
            }
            theme.primaryText.withAlphaComponent(dragging?.widget == widget ? 0.16 : 0.08).setFill()
            tile.fill()
            if dragging?.widget == widget || hovered == widget {
                theme.accent.setStroke()
                tile.lineWidth = 1.5
                tile.stroke()
            }
            drawLabel(for: widget, in: frame, color: theme.primaryText)
            if hovered == widget, dragging == nil {
                let close = closeRect(for: frame)
                theme.controlFill.setFill()
                NSBezierPath(ovalIn: close).fill()
                let x = NSAttributedString(string: "×", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: theme.primaryText])
                x.draw(at: CGPoint(x: close.midX - x.size().width / 2, y: close.midY - x.size().height / 2))
            }
        }

        if widgets.isEmpty, dropIndex == nil {
            let hint = NSAttributedString(string: "Drag widgets here from below", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.secondaryText])
            hint.draw(at: CGPoint(x: bounds.midX - hint.size().width / 2, y: bounds.midY - 4))
        }
    }

    private func drawLabel(for widget: PanelWidget, in frame: CGRect, color: NSColor) {
        if let image = NSImage(systemSymbolName: widget.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) {
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: CGRect(x: frame.midX - image.size.width / 2, y: frame.midY - 18, width: image.size.width, height: image.size.height))
        }
        let title = NSAttributedString(string: widget.title, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: color])
        let size = title.size()
        title.draw(in: CGRect(x: max(frame.minX + 4, frame.midX - size.width / 2), y: frame.midY + 4, width: min(size.width, frame.width - 8), height: size.height))
    }

    private func closeRect(for frame: CGRect) -> CGRect {
        CGRect(x: frame.maxX - 20, y: frame.minY + 4, width: 16, height: 16)
    }

    private func insertionIndex(for x: CGFloat, in list: [PanelWidget]) -> Int {
        let tiles = frames(for: list + [nil])
        return tiles.firstIndex { x < $0.midX } ?? list.count
    }

    private func widget(at point: CGPoint) -> (PanelWidget, CGRect)? {
        zip(widgets, frames(for: widgets)).first { $0.1.contains(point) }.map { ($0.0, $0.1) }
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let now = widget(at: point)?.0
        if now != hovered { hovered = now; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (widget, frame) = widget(at: point) else { return }
        if closeRect(for: frame).insetBy(dx: -3, dy: -3).contains(point) {
            commit(widgets.filter { $0 != widget })
            return
        }
        dragging = (widget, point.x - frame.minX, point.x)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging != nil else { return }
        dragging?.x = convert(event.locationInWindow, from: nil).x
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragging else { return }
        var list = widgets
        list.removeAll { $0 == dragging.widget }
        list.insert(dragging.widget, at: insertionIndex(for: dragging.x, in: list))
        self.dragging = nil
        commit(list)
    }

    private func commit(_ list: [PanelWidget]) {
        PanelLayoutStore.set(list)
        reload()
        Haptics.tick()
        onChange?()
    }

    // MARK: Dropping from the gallery

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let x = convert(sender.draggingLocation, from: nil).x
        dropIndex = insertionIndex(for: x, in: widgets)
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropIndex = nil
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropIndex = nil }
        guard let raw = sender.draggingPasteboard.string(forType: .panelWidget), let widget = PanelWidget(rawValue: raw),
              widgets.contains(widget) == false else { return false }
        var list = widgets
        list.insert(widget, at: min(dropIndex ?? list.count, list.count))
        commit(list)
        return true
    }

    /// The gallery's click-to-add.
    func append(_ widget: PanelWidget) {
        guard widgets.contains(widget) == false else { return }
        commit(widgets + [widget])
    }
}

/// A widget waiting in the gallery: click to add it, or drag it to its place.
final class WidgetGalleryTile: NSView, NSDraggingSource {
    let widget: PanelWidget
    var onAdd: (() -> Void)?
    private var downEvent: NSEvent?

    init(widget: PanelWidget) {
        self.widget = widget
        super.init(frame: .zero)
        let theme = SettingsKit.theme
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = theme.elevatedBackground.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = theme.primaryText.withAlphaComponent(0.1).cgColor

        let icon = NSImageView(image: NSImage(systemSymbolName: widget.symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = theme.primaryText
        let title = NSTextField(labelWithString: widget.title)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [icon, title])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 92),
            heightAnchor.constraint(equalToConstant: 58),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 84)
        ])
        toolTip = "Drag into the panel, or click to add it at the end"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) { downEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downEvent,
              hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 3 else { return }
        downEvent = nil
        let item = NSPasteboardItem()
        item.setString(widget.rawValue, forType: .panelWidget)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let image = bitmapImageRepForCachingDisplay(in: bounds).map { rep -> NSImage in
            cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return image
        }
        dragging.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragging], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard downEvent != nil else { return }
        downEvent = nil
        onAdd?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
