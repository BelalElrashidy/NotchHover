import AppKit

/// The notch as it looks right now, on a stand-in desktop, pinned to the top of the
/// Appearance and Layout panes — Bartender's menu bar preview, for a notch. It redraws
/// on every change, and switches between resting, peek and open.
final class NotchStageView: NSView {
    private let imageView = NSImageView()
    private let picker = StagePicker(titles: ["Resting", "Peek", "Open"])
    private var presentation: NotchContentView.Presentation = .expanded
    private var imageHeight: NSLayoutConstraint?
    var theme: Theme = ThemeStore.selected

    static let height: CGFloat = 196

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        imageView.imageScaling = .scaleAxesIndependently
        picker.selected = 2
        picker.onSelect = { [weak self] index in
            self?.presentation = [.idle, .peek, .expanded][index]
            self?.refresh()
        }
        [imageView, picker].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        // Edge to edge and hung from the top, like the real notch; what runs past the
        // bottom is clipped.
        imageHeight = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 0.3)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageHeight!,
            // Centred under the panel, on the desktop — never over the panel's edge.
            picker.centerXAnchor.constraint(equalTo: centerXAnchor),
            picker.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
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
        let image = PreviewRenderer.snapshot(theme: theme, width: 760, presentation: presentation, margin: 170)
        imageView.image = image
        if let image, image.size.width > 0 {
            imageHeight?.isActive = false
            imageHeight = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: image.size.height / image.size.width)
            imageHeight?.isActive = true
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

    /// The panel, hanging from the top of a desktop that spans the page like every card
    /// under it.
    private var slab: CGRect { CGRect(x: 16, y: 0, width: bounds.width - 32, height: bounds.height - 16) }

    /// How much room a widget takes, as the panel's flex layout would give it; an empty
    /// slot — where a dragged-in widget will land — is a middling one.
    private static func weight(_ widget: PanelWidget?) -> CGFloat {
        widget.map { $0.idealWidth + $0.grow * 60 } ?? 220
    }

    private func frames(for list: [PanelWidget?]) -> [CGRect] {
        let area = CGRect(x: slab.minX + 12, y: 26, width: slab.width - 24, height: slab.height - 38)
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
        // The desktop: the stage's colours, in a card the width of the page.
        let desktop = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1),
                            NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.42, alpha: 1)])?.draw(in: desktop, angle: -20)
        // The panel itself, flush with the top edge and rounded below, as it hangs from the notch.
        let path = NSBezierPath(roundedRect: CGRect(x: slab.minX, y: slab.minY - 20, width: slab.width, height: slab.height + 20), xRadius: 18, yRadius: 18)
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
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -12)
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

/// Resting · Peek · Open, small and translucent so it sits on the stage's desktop
/// without competing with the notch.
final class StagePicker: NSView {
    var onSelect: ((Int) -> Void)?
    var selected = 0 { didSet { refresh() } }
    private var buttons: [ClosureButton] = []
    private let titles: [String]

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        let stack = NSStackView()
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        for (index, title) in titles.enumerated() {
            let button = ClosureButton(title: title) { [weak self] in
                self?.selected = index
                self?.onSelect?(index)
            }
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.heightAnchor.constraint(equalToConstant: 20).isActive = true
            // Sized for the bold title, so choosing one doesn't shift the others.
            let bold = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)])
            button.widthAnchor.constraint(equalToConstant: ceil(bold.size().width) + 16).isActive = true
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refresh() {
        for (index, button) in buttons.enumerated() {
            let isOn = index == selected
            button.layer?.backgroundColor = isOn ? NSColor.white.withAlphaComponent(0.25).cgColor : NSColor.clear.cgColor
            button.attributedTitle = NSAttributedString(string: titles[index], attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(isOn ? 1 : 0.7),
                .font: NSFont.systemFont(ofSize: 11, weight: isOn ? .semibold : .regular)
            ])
        }
    }
}

/// A theme drawn plainly: a desktop, the panel hanging from the top in the theme's
/// surface, a row of tabs, three widgets and an accent — enough to tell themes apart at a
/// glance, without text too small to read.
final class ThemeSwatchView: NSView {
    private let theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.38, alpha: 1),
                            NSColor(calibratedRed: 0.42, green: 0.34, blue: 0.50, alpha: 1)])?.draw(in: bounds, angle: -25)

        // The panel: three quarters of the width, hanging from the top.
        let panel = CGRect(x: bounds.width * 0.12, y: -14, width: bounds.width * 0.76, height: bounds.height * 0.78 + 14)
        let shape = NSBezierPath(roundedRect: panel, xRadius: 12, yRadius: 12)
        switch theme.surface {
        case .solid(let color): color.setFill()
        case .glass: NSColor.white.withAlphaComponent(0.22).setFill()
        }
        shape.fill()

        let inset: CGFloat = 8
        let inner = CGRect(x: panel.minX + inset, y: 6, width: panel.width - inset * 2, height: panel.maxY - 6 - inset)
        // Tabs along the top, the first one picked.
        let tab = CGRect(x: inner.minX, y: inner.minY, width: inner.width * 0.18, height: 5)
        theme.primaryText.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: tab, xRadius: 2.5, yRadius: 2.5).fill()
        theme.primaryText.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: tab.offsetBy(dx: tab.width + 4, dy: 0).insetBy(dx: tab.width * 0.2, dy: 0), xRadius: 2.5, yRadius: 2.5).fill()

        // Three widgets.
        let top = inner.minY + 12
        let height = inner.maxY - top
        let gap: CGFloat = 5
        let width = (inner.width - gap * 2) / 3
        for index in 0..<3 {
            let tile = CGRect(x: inner.minX + CGFloat(index) * (width + gap), y: top, width: width, height: height)
            theme.controlFill.setFill()
            NSBezierPath(roundedRect: tile, xRadius: 5, yRadius: 5).fill()
            // A line of "text" in each, and the accent in the first.
            theme.secondaryText.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: CGRect(x: tile.minX + 5, y: tile.minY + 6, width: tile.width * 0.55, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            theme.secondaryText.withAlphaComponent(0.4).setFill()
            NSBezierPath(roundedRect: CGRect(x: tile.minX + 5, y: tile.minY + 12, width: tile.width * 0.35, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            if index == 0 {
                theme.accent.setFill()
                NSBezierPath(roundedRect: CGRect(x: tile.minX + 5, y: tile.maxY - 9, width: tile.width - 10, height: 4), xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}
