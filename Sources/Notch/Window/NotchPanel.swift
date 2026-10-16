import AppKit

/// Borderless panel that drops out of the notch. Floats above the menu bar without
/// stealing focus from whatever the user is working in.
final class NotchPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // Clear glass plus a window shadow reads as a drawn border, so neither the
        // window nor the card casts one.
        hasShadow = false
        isMovable = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    // Borderless panels refuse key status by default, which would break button clicks.
    override var canBecomeKey: Bool { true }
}
