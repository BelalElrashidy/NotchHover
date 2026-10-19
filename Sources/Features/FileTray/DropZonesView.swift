import AppKit

/// What a file drag over the notch can be dropped on, after Dropover's instant actions
/// and Droppy's quick-action bar: the shelf, AirDrop, and the actions that fit the files
/// being dragged. Dropping on one does it straight away.
final class DropZonesView: NSView {
    enum Zone: Equatable {
        case shelf
        case airDrop
        case action(FileAction)

        var title: String {
            switch self {
            case .shelf: return "Shelf"
            case .airDrop: return "AirDrop"
            case .action(let action): return action.shortTitle
            }
        }

        var symbol: String {
            switch self {
            case .shelf: return "tray.and.arrow.down.fill"
            case .airDrop: return "paperplane.fill"
            case .action(let action): return action.symbol
            }
        }
    }

    private(set) var zones: [Zone] = []
    var hot: Zone? {
        didSet { if hot != oldValue { needsDisplay = true } }
    }

    /// Zones for these files: always the shelf, AirDrop and Zip; a conversion and text
    /// recognition when they fit.
    func configure(for urls: [URL]) {
        var zones: [Zone] = [.shelf, .airDrop]
        if let conversion = FileAction.conversion(for: urls) { zones.append(.action(conversion)) }
        zones.append(.action(.zip))
        if FileAction.actions(for: urls).contains(.copyText) { zones.append(.action(.copyText)) }
        self.zones = zones
        hot = nil
        needsDisplay = true
    }

    /// The drag is handled by the panel underneath, which asks which zone a point is in.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func zone(at point: NSPoint) -> Zone? {
        zip(zones, frames()).first { $0.1.contains(point) }?.0
    }

    /// The shelf gets the most room — it's the default — the rest share what's left.
    private func frames() -> [CGRect] {
        let inset: CGFloat = 12, gap: CGFloat = 8
        let area = bounds.insetBy(dx: inset, dy: 10)
        let weights = zones.map { $0 == .shelf ? 1.6 : 1.0 }
        let unit = (area.width - gap * CGFloat(zones.count - 1)) / weights.reduce(0, +)
        var x = area.minX
        return weights.map { weight in
            let rect = CGRect(x: x, y: area.minY, width: unit * weight, height: area.height)
            x += rect.width + gap
            return rect
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (zone, frame) in zip(zones, frames()) {
            let isHot = zone == hot
            let path = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
            if isHot {
                Style.accent.withAlphaComponent(0.2).setFill()
                path.fill()
            }
            (isHot ? Style.accent : Style.primaryText.withAlphaComponent(0.28)).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()

            let tint = isHot ? Style.primaryText : Style.secondaryText
            let title = NSAttributedString(string: zone.title, attributes: [
                .font: NSFont.systemFont(ofSize: Style.scaled(12), weight: .medium), .foregroundColor: tint
            ])
            let symbolSize: CGFloat = zone == .shelf ? 24 : 20
            let image = Style.symbolImage(zone.symbol, pointSize: symbolSize)
            let block = (image?.size.height ?? 0) + 6 + title.size().height
            var y = frame.midY + block / 2
            if let image {
                let tinted = image.tinted(tint)
                y -= image.size.height
                tinted.draw(in: CGRect(x: frame.midX - image.size.width / 2, y: y, width: image.size.width, height: image.size.height))
                y -= 6
            }
            y -= title.size().height
            title.draw(at: CGPoint(x: frame.midX - title.size().width / 2, y: y))
        }
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
