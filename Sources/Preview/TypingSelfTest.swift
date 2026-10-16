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

        /// Every button the user can see must be the thing a click at its centre lands
        /// on. A container with no height still draws its buttons, but hit-testing stops
        /// at the container — which is how the whole right side of the header went dead.
        func checkButtons(on tab: PanelTab) {
            content.selectTabForPreview(tab)
            content.layoutSubtreeIfNeeded()
            guard let root = panel.contentView else { return }
            var dead: [String] = []
            var total = 0
            for button in content.visibleButtons() {
                // Rows scrolled out of a list are not something anyone can click.
                let middle = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
                guard button.visibleRect.contains(middle) else { continue }
                total += 1
                let center = button.convert(middle, to: nil)
                let hit = root.hitTest(root.convert(center, from: nil))
                guard hit !== button, hit?.isDescendant(of: button) != true else { continue }
                let name = button.toolTip ?? button.title
                dead.append("\(name.isEmpty ? "untitled" : name) → \(hit.map { String(describing: Swift.type(of: $0)) } ?? "nothing")")
            }
            report("buttons on \(tab.title): \(total - dead.count)/\(total) clickable" + (dead.isEmpty ? "" : " — dead: " + dead.joined(separator: "; ")))
        }

        /// Sends a key the way AppKit does: as a key equivalent first, then as a key-down
        /// if nothing claimed it. Only shortcuts with no side effects outside the panel
        /// are pressed — nothing that changes the volume, the mic, or real clips.
        func press(_ characters: String, code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            ) else { return }
            if panel.performKeyEquivalent(with: event) == false { panel.sendEvent(event) }
        }

        func checkKeyboard() {
            var calls: [String] = []
            content.onPlayPause = { calls.append("play/pause") }
            content.onPreviousTrack = { calls.append("previous") }
            content.onNextTrack = { calls.append("next") }
            content.onDismiss = { calls.append("close") }
            content.selectTabForPreview(.home)
            panel.makeFirstResponder(nil)

            var results: [String] = []
            func expect(_ label: String, _ condition: Bool) { results.append((condition ? "✓ " : "✗ ") + label) }

            press("2", code: 19, .command); expect("⌘2 opens Shelf", content.selectedTab == .shelf)
            press("4", code: 21, .command); expect("⌘4 opens Clipboard", content.selectedTab == .clipboard)
            press("1", code: 18, .command); expect("⌘1 opens Home", content.selectedTab == .home)
            press("\t", code: 48, .control); expect("⌃⇥ moves to the next tab", content.selectedTab == .shelf)
            press("\t", code: 48, [.control, .shift]); expect("⌃⇧⇥ moves back", content.selectedTab == .home)

            panel.makeFirstResponder(nil)
            press(" ", code: 49); expect("Space plays or pauses", calls.last == "play/pause")
            press("", code: 123, .command); expect("⌘← goes to the previous track", calls.last == "previous")
            press("", code: 124, .command); expect("⌘→ goes to the next track", calls.last == "next")

            press("/", code: 44, .command); expect("⌘/ shows the shortcuts", content.isShowingShortcuts)
            press("\u{1b}", code: 53); expect("Esc closes the shortcuts first", content.isShowingShortcuts == false && calls.last != "close")
            press("\u{1b}", code: 53); expect("Esc then closes the panel", calls.last == "close")

            press("3", code: 20, .command)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                expect("⌘3 opens Notes with the cursor in the editor", content.selectedTab == .notes && panel.firstResponder is NoteTextView)
                let before = calls.count
                press("", code: 123, .command)
                expect("⌘← while typing moves the cursor, not the track", calls.count == before)

                content.selectTabForPreview(.clipboard)
                panel.makeFirstResponder(nil)
                let first = content.clipboardSelectionIndex
                press("", code: 125)
                press("", code: 125)
                expect("↓ walks the clipboard list", content.clipboardSelectionIndex == first + 2 || ClipboardHistory.shared.items.count < 3)

                report("keyboard: " + results.joined(separator: "  "))
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for tab in PanelTab.headerTabs + [.clipboard] { checkButtons(on: tab) }
            checkKeyboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { check(.notes, label: "notes") {
                check(.clipboard, label: "clipboard search") {
                    if let savedDraft {
                        UserDefaults.standard.set(savedDraft, forKey: "NoteDraft")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "NoteDraft")
                    }
                    panel.orderOut(nil)
                    exit(0)
                }
            } }
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

    /// Every button in this subtree that is actually on screen.
    func visibleButtons() -> [NSButton] {
        guard isHiddenOrHasHiddenAncestor == false, alphaValue > 0.01 else { return [] }
        let own = (self as? NSButton).map { [$0] } ?? []
        return own + subviews.flatMap { $0.visibleButtons() }
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
