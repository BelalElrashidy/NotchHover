import AppKit

/// One display's notch: its own panel, what is drawn in it, and where it sits.
///
/// Every display gets one, so the resting bar and live activities show on all of them
/// at once. Only one is ever open — whichever the pointer went to — and the controller
/// treats that one as the target for anything interactive.
final class NotchDisplay {
    let id: CGDirectDisplayID
    let geometry: NotchGeometry
    let panel: NotchPanel
    let content: NotchContentView

    /// The size the panel opens to on this display.
    var panelSize: CGSize {
        NotchContentView.Metrics.panelSize(notchWidth: notchSize.width, notchHeight: notchSize.height)
    }

    /// Notchless displays lay out against the fallback strip, not a zero-width notch.
    private var notchSize: CGSize {
        geometry.hasNotch ? geometry.notchRect.size : .zero
    }

    init(id: CGDirectDisplayID, screen: NSScreen) {
        self.id = id
        geometry = NotchGeometry(screen: screen)
        let notch = geometry.hasNotch ? geometry.notchRect.size : .zero
        content = NotchContentView(notchWidth: notch.width, notchHeight: notch.height)
        panel = NotchPanel(contentView: content)
        panel.setFrame(geometry.expandedFrame(size: panelSize), display: false)
    }

    /// Stable within a session, which is all the controller needs to match a screen to
    /// the display already built for it.
    static func identifier(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Whether this display was built for the screen as it is now — a resolution
    /// change moves the notch and resizes everything around it.
    func matches(_ screen: NSScreen) -> Bool {
        let current = NotchGeometry(screen: screen)
        return current.notchRect == geometry.notchRect && current.hasNotch == geometry.hasNotch
    }
}
