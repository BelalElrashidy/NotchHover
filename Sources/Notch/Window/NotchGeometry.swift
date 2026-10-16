import AppKit

/// Describes where the notch sits on a screen, and where the panel should drop down from it.
struct NotchGeometry {
    /// Screen coordinates of the notch itself (or a stand-in strip on notchless displays).
    let notchRect: CGRect
    /// The area that triggers the panel — the notch, padded to make it easier to hit.
    let hoverRect: CGRect
    /// Whether the display physically has a notch.
    let hasNotch: Bool

    private enum Constants {
        static let hoverHorizontalPadding: CGFloat = 12
        /// Notchless displays get a strip of this size at the top center.
        static let fallbackNotchSize = CGSize(width: 180, height: 26)
    }

    init(screen: NSScreen) {
        let frame = screen.frame
        let notchHeight = screen.safeAreaInsets.top

        // Both auxiliary areas are non-nil only on displays with a notch; the gap
        // between them is the notch.
        if notchHeight > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = frame.width - leftArea.width - rightArea.width
            notchRect = CGRect(
                x: frame.minX + leftArea.width,
                y: frame.maxY - notchHeight,
                width: notchWidth,
                height: notchHeight
            )
            hasNotch = true
        } else {
            let size = Constants.fallbackNotchSize
            notchRect = CGRect(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
            hasNotch = false
        }

        hoverRect = notchRect.insetBy(dx: -Constants.hoverHorizontalPadding, dy: 0)
    }

    func isPointerInHoverArea(_ point: CGPoint) -> Bool {
        hoverRect.containsPointer(point)
    }

    /// Frame for the expanded panel: anchored to the top of the screen, centered on the notch.
    func expandedFrame(size: CGSize) -> CGRect {
        CGRect(
            x: notchRect.midX - size.width / 2,
            y: notchRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Frame for the collapsed panel — the notch itself, so expansion reads as the notch growing.
    var collapsedFrame: CGRect {
        notchRect
    }

    /// The screen currently under the pointer, falling back to the built-in display.
    static var activeScreen: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.containsPointer(location) } ?? NSScreen.main
    }
}

extension CGRect {
    /// `contains` treats the top and right edges as outside the rect, but a pointer pinned
    /// to the top of the screen reports exactly `maxY` — the most natural way to reach the
    /// notch. Inclusive bounds keep that gesture working.
    func containsPointer(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
