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
        // Whoever builds a panel gets its shortcuts with it — the controller, a test, a
        // preview — rather than each having to remember to wire them up.
        keyHandler = { [weak contentView] event in
            (contentView as? NotchContentView)?.handleKey(event) ?? false
        }
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // Clear glass plus a window shadow reads as a drawn border, so neither the
        // window nor the card casts one.
        hasShadow = false
        isMovable = false
        // Above the menu bar — which full-screen apps slide down over the notch when the
        // pointer reaches the top — matching Boring Notch and Atoll.
        level = .mainMenu + 3
        // Every Space, including other apps' full-screen ones, without moving as Spaces
        // change and without joining ⌘` window cycling.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    // Borderless panels refuse key status by default, which would break button clicks.
    override var canBecomeKey: Bool { true }

    /// The panel's keyboard shortcuts. Asked first for ⌘ combinations — before the main
    /// menu and before a text view sees them — and last for plain keys that nothing
    /// focused wanted, like Space with no text field active. Returns whether it acted.
    var keyHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}
