import AppKit

/// Clicks into the notes editor and the clipboard search, then types: --typing-selftest
///
/// Typing into a panel that never activates the app is the fragile part of this
/// whole design — a click has to land on the text view itself for the panel to take
/// key status, and anything sitting over it makes that silently impossible. This puts
/// a real panel on screen, sends it mouse and key events, and reports where they went.
enum TypingSelfTest {
    private static var retained: [AnyObject] = []

    static func run() {
        func report(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }

        guard let screen = NSScreen.main else { exit(1) }
        let geometry = NotchGeometry(screen: screen)
        let notchWidth = geometry.hasNotch ? geometry.notchRect.width : 0
        let notchHeight = geometry.hasNotch ? geometry.notchRect.height : 0

        let content = NotchContentView(notchWidth: notchWidth, notchHeight: notchHeight)
        let panel = NotchPanel(contentView: content)
        let size = NotchContentView.Metrics.panelSize(notchWidth: notchWidth, notchHeight: notchHeight)
        panel.setFrame(geometry.expandedFrame(size: size), display: true)
        panel.orderFrontRegardless()
        content.present(.expanded, animated: false)
        retained = [content, panel]

        func click(_ view: NSView) {
            let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent? {
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                )
            }
            guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
            // A text view's mouseDown runs its own tracking loop, pulling the mouse-up off
            // the event queue — so the up has to be queued before the down is sent.
            NSApp.postEvent(up, atStart: false)
            panel.sendEvent(down)
        }

        func type(_ text: String) {
            for character in text {
                for kind in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(
                        with: kind, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil, characters: String(character),
                        charactersIgnoringModifiers: String(character), isARepeat: false, keyCode: 0
                    ) else { continue }
                    panel.sendEvent(event)
                }
            }
        }

        func check(_ tab: PanelTab, label: String, then next: @escaping () -> Void) {
            content.selectTabForPreview(tab)
            content.layoutSubtreeIfNeeded()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let textView = content.firstTextInput()
                let textField = content.firstTextField()
                guard let input: NSView = textView ?? textField else {
                    report("\(label): no text input found")
                    next()
                    return
                }
                // Click the box the user sees, not the text view inside it: that is what a
                // person aims at, and the gap between the two is exactly what is tested.
                let target = textView?.enclosingScrollView ?? input
                report("\(label): input frame \(NSStringFromRect(input.frame)), box \(NSStringFromRect(target.frame))")
                let center = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
                if let hit = panel.contentView?.hitTest(panel.contentView!.convert(center, from: nil)) {
                    var chain: [String] = []
                    var view: NSView? = hit
                    while let current = view, chain.count < 8 {
                        let detail = (current as? NSButton).map { " title=\($0.title) tip=\($0.toolTip ?? "-") image=\($0.image?.accessibilityDescription ?? "-")" } ?? ""
                        chain.append("\(Swift.type(of: current)) \(NSStringFromRect(current.frame))\(detail)")
                        view = current.superview
                    }
                    report("\(label): hit chain — " + chain.joined(separator: "  <  "))
                }
                click(target)
                let responder = panel.firstResponder
                // Only the first responder is worth reporting. Whether the panel becomes key
                // can't be tested this way: since macOS 14 a background app only gets key
                // status from real input, and synthetic events carry none.
                report("\(label): after click — first responder: \(responder.map { String(describing: Swift.type(of: $0)) } ?? "nil")")
                type("hello")
                let typed = textView?.string ?? textField?.stringValue ?? ""
                report("\(label): after typing — text is \"\(typed)\"")
                next()
            }
        }

        // The editor autosaves its draft into the real defaults; put it back afterwards.
        let savedDraft = UserDefaults.standard.string(forKey: "NoteDraft")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            check(.notes, label: "notes") {
                check(.clipboard, label: "clipboard search") {
                    if let savedDraft {
                        UserDefaults.standard.set(savedDraft, forKey: "NoteDraft")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "NoteDraft")
                    }
                    panel.orderOut(nil)
                    exit(0)
                }
            }
        }
    }
}

extension NSView {
    /// The first editable text view in this subtree — the notes editor, or the field
    /// editor behind a search box once it has focus.
    func firstTextInput() -> NSTextView? {
        if let text = self as? NSTextView, text.isEditable, text.isFieldEditor == false { return text }
        for subview in subviews {
            if let found = subview.firstTextInput() { return found }
        }
        return nil
    }

    /// The first editable text field in this subtree — a search box.
    func firstTextField() -> NSTextField? {
        if let field = self as? NSTextField, field.isEditable { return field }
        for subview in subviews {
            if let found = subview.firstTextField() { return found }
        }
        return nil
    }
}
