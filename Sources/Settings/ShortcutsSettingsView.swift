import AppKit

/// Every action in one table, after Raycast v2's Shortcuts tab: search and filter at the
/// top, a hotkey you click to record, clashes in red, built-ins first and yours after.
final class ShortcutsSettingsView: NSView, NSSearchFieldDelegate {
    /// Opens the editor for a shortcut of yours — nil for a new one.
    var onEditCustom: ((CustomAction?) -> Void)?

    private enum Filter: String, CaseIterable {
        case all = "All", builtIn = "Built-in", yours = "Yours", hotkey = "Has hotkey", clashes = "Clashes"
    }

    private let search = NSSearchField()
    private let chips = NSStackView()
    private let rows = NSStackView()
    private var filter: Filter = .all
    /// The row to bring into view and start recording — ⌘E from the ⌘K list.
    private var focusID: String?

    init() {
        super.init(frame: .zero)
        search.placeholderString = "Search"
        search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 160).isActive = true

        chips.spacing = 6
        let newButton = SettingsKit.button("+ New shortcut", prominent: true) { [weak self] in self?.onEditCustom?(nil) }
        let top = NSStackView(views: [search, chips, NSView(), newButton])
        top.alignment = .centerY
        top.spacing = 8

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        let restore = SettingsKit.button("Restore defaults") {
            ActionRegistry.shared.resetAll()
        }
        let hint = NSTextField(labelWithString: "Click a hotkey to record a new one · ⌫ clears it · double-click one of yours to edit it")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = SettingsKit.theme.tertiaryText
        let bottom = NSStackView(views: [restore, NSView(), hint])
        bottom.alignment = .centerY

        let stack = NSStackView(views: [top, header(), rows, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        [top, rows, bottom].forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        ActionRegistry.shared.addObserver { [weak self] in self?.reload() }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Brings one action into view and starts recording its hotkey.
    func focus(on id: String) {
        focusID = id
        filter = .all
        search.stringValue = ""
        reload()
    }

    private func header() -> NSView {
        func column(_ title: String, width: CGFloat?) -> NSTextField {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11)
            label.textColor = SettingsKit.theme.tertiaryText
            if let width { label.widthAnchor.constraint(equalToConstant: width).isActive = true }
            return label
        }
        let stack = NSStackView(views: [column("Action", width: nil), column("Kind", width: 80), column("Hotkey, anywhere", width: 170),
                                        column("In panel", width: 60), column("On", width: 30)])
        stack.spacing = 8
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        // The action column takes the slack, so every other column lines up.
        stack.arrangedSubviews.first?.setContentHuggingPriority(.init(1), for: .horizontal)
        stack.arrangedSubviews.first?.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return stack
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    private func reload() {
        let registry = ActionRegistry.shared
        let clashes = registry.conflictingIDs

        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for option in Filter.allCases {
            let count = option == .clashes ? clashes.count : nil
            if option == .clashes, count == 0 { continue }
            let title = count.map { "\(option.rawValue) \($0)" } ?? option.rawValue
            let chip = SettingsKit.button(title) { [weak self] in
                self?.filter = option
                self?.reload()
            }
            if option == filter { chip.layer?.backgroundColor = SettingsKit.theme.primaryText.withAlphaComponent(0.2).cgColor }
            if option == .clashes { chip.contentTintColor = .systemRed }
            chips.addArrangedSubview(chip)
        }

        let words = search.stringValue.lowercased().split(separator: " ").map(String.init)
        let actions = registry.actions.filter { action in
            switch filter {
            case .all: break
            case .builtIn: if action.isCustom { return false }
            case .yours: if action.isCustom == false { return false }
            case .hotkey: if registry.hotkey(for: action.id) == nil { return false }
            case .clashes: if clashes.contains(action.id) == false { return false }
            }
            let haystack = "\(action.title) \(action.group)".lowercased()
            return words.allSatisfy(haystack.contains)
        }

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var lastGroup: String?
        var focusRow: ShortcutRow?
        for action in actions {
            if action.group != lastGroup {
                lastGroup = action.group
                let label = NSTextField(labelWithString: action.group)
                label.font = .systemFont(ofSize: 11, weight: .semibold)
                label.textColor = SettingsKit.theme.secondaryText
                let wrapper = NSStackView(views: [label])
                wrapper.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 3, right: 0)
                rows.addArrangedSubview(wrapper)
            }
            let custom = CustomActionStore.shared.items.first { "custom.\($0.id.uuidString)" == action.id }
            let row = ShortcutRow(action: action, clashesWith: clashes.contains(action.id) ? clashName(for: action) : nil, custom: custom)
            row.onEdit = { [weak self] in self?.onEditCustom?(custom) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            if action.id == focusID { focusRow = row }
        }
        if actions.isEmpty {
            let empty = NSTextField(labelWithString: "Nothing matches")
            empty.textColor = SettingsKit.theme.tertiaryText
            rows.addArrangedSubview(empty)
        }
        if let focusRow {
            focusID = nil
            DispatchQueue.main.async {
                focusRow.scrollToVisible(focusRow.bounds)
                focusRow.startRecording()
            }
        }
    }

    private func clashName(for action: NotchAction) -> String? {
        guard let combo = ActionRegistry.shared.hotkey(for: action.id) else { return nil }
        return ActionRegistry.shared.conflict(for: combo, excluding: action.id)?.title
    }
}

/// One action: icon and name, kind, the hotkey recorder, its key in the panel, on/off.
private final class ShortcutRow: NSView {
    var onEdit: (() -> Void)?
    private let action: NotchAction
    private let recorder: HotkeyRecorder

    init(action: NotchAction, clashesWith: String?, custom: CustomAction?) {
        self.action = action
        let registry = ActionRegistry.shared
        recorder = HotkeyRecorder(combo: registry.hotkey(for: action.id), isChanged: registry.isChanged(action.id))
        super.init(frame: .zero)
        let theme = SettingsKit.theme
        wantsLayer = true
        layer?.cornerRadius = 6
        if clashesWith != nil { layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor }

        let icon = NSImageView(image: NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = theme.secondaryText
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let title = NSTextField(labelWithString: action.title)
        title.font = .systemFont(ofSize: 12)
        title.textColor = theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        let name = NSStackView(views: [icon, title])
        name.spacing = 8
        name.setHuggingPriority(.init(1), for: .horizontal)
        name.setClippingResistancePriority(.init(1), for: .horizontal)

        let kind = NSTextField(labelWithString: custom.map { $0.steps.count > 1 ? "\($0.steps.count) steps" : $0.kindTitle } ?? "Built-in")
        kind.font = .systemFont(ofSize: 11)
        kind.textColor = theme.secondaryText
        kind.widthAnchor.constraint(equalToConstant: 80).isActive = true

        recorder.onRecord = { combo in registry.setHotkey(combo, for: action.id) }
        recorder.onReset = { registry.resetHotkey(for: action.id) }
        let clash = NSTextField(labelWithString: clashesWith.map { "also \($0)" } ?? "")
        clash.font = .systemFont(ofSize: 10)
        clash.textColor = .systemRed
        clash.lineBreakMode = .byTruncatingTail
        let hotkey = NSStackView(views: [recorder, clash])
        hotkey.spacing = 6
        hotkey.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let panel = NSTextField(labelWithString: action.panelKeys ?? "")
        panel.font = .systemFont(ofSize: 11)
        panel.textColor = theme.tertiaryText
        panel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let enabled = SwitchControl()
        enabled.isOn = registry.isEnabled(action.id)
        enabled.onChange = { registry.setEnabled($0, for: action.id) }
        let enabledBox = NSStackView(views: [enabled])
        enabledBox.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let stack = NSStackView(views: [name, kind, hotkey, panel, enabledBox])
        stack.spacing = 8
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        toolTip = action.isCustom ? "Double-click to edit · right-click to delete" : nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startRecording() { recorder.startRecording() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, action.isCustom { onEdit?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if action.isCustom {
            menu.addItem(ClosureMenuItem("Edit…") { [weak self] in self?.onEdit?() })
            menu.addItem(ClosureMenuItem("Delete") { [action] in
                if let id = UUID(uuidString: action.id.replacingOccurrences(of: "custom.", with: "")) { CustomActionStore.shared.delete(id) }
            })
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem("Run it now") { [action] in ActionRegistry.shared.run(action.id) })
        menu.addItem(ClosureMenuItem("Reset hotkey") { [action] in ActionRegistry.shared.resetHotkey(for: action.id) })
        return menu
    }
}

/// A menu item whose action is a closure.
final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    convenience init(_ title: String, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.handler = handler
        target = self
    }

    @objc private func fire() { handler?() }
}

/// Click, press the keys: Raycast's recorder. The keys show as keycaps as they're pressed;
/// ⌫ clears it, ⎋ leaves it as it was.
final class HotkeyRecorder: NSView {
    var onRecord: ((KeyCombo?) -> Void)?
    var onReset: (() -> Void)?

    private var combo: KeyCombo?
    private let isChanged: Bool
    private var isRecording = false { didSet { rebuild() } }
    private let content = NSStackView()

    init(combo: KeyCombo?, isChanged: Bool) {
        self.combo = combo
        self.isChanged = isChanged
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        content.spacing = 3
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuild() {
        let theme = SettingsKit.theme
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        layer?.borderWidth = isRecording ? 1.5 : 0
        layer?.borderColor = theme.accent.cgColor
        layer?.backgroundColor = isRecording ? theme.accent.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor
        if isRecording {
            content.addArrangedSubview(label("Press keys…", color: theme.accent))
        } else if let combo {
            content.addArrangedSubview(Keycaps(combo.parts))
            if isChanged { content.addArrangedSubview(label("•", color: theme.accent)) }
        } else {
            content.addArrangedSubview(label("Record hotkey", color: theme.tertiaryText))
        }
        toolTip = isChanged ? "Changed from the default — right-click to reset" : nil
    }

    private func label(_ text: String, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = color
        return label
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { startRecording() }

    func startRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    /// ⌘-combinations come here before keyDown; a recorder wants them all.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case 53: // ⎋
            window?.makeFirstResponder(nil)
        case 51, 117: // ⌫, ⌦
            combo = nil
            window?.makeFirstResponder(nil)
            onRecord?(nil)
        default:
            guard let recorded = KeyCombo(event: event) else {
                NSSound.beep()
                return
            }
            combo = recorded
            window?.makeFirstResponder(nil)
            onRecord?(recorded)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Reset to default") { [weak self] in self?.onReset?() })
        menu.addItem(ClosureMenuItem("Remove hotkey") { [weak self] in self?.onRecord?(nil) })
        return menu
    }
}

/// Make or change a shortcut of yours: a name, an icon, and its steps in order.
final class CustomActionEditor: NSWindowController, NSWindowDelegate {
    var onSave: ((CustomAction) -> Void)?

    private var action: CustomAction
    private let nameField = NSTextField()
    private let iconPicker: MenuButton
    private let stepsStack = NSStackView()
    private var stepFields: [NSTextField?] = []

    private static let symbols = ["bolt.fill", "magnifyingglass", "link", "briefcase.fill", "terminal", "app", "music.note",
                                  "globe", "doc.text", "star.fill", "hammer.fill", "paperplane.fill"]

    init(action: CustomAction?) {
        self.action = action ?? CustomAction(id: UUID(), name: "", symbol: "bolt.fill", steps: [.openURL("https://")])
        iconPicker = MenuButton(titles: Self.symbols)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = action == nil ? "New shortcut" : "Edit shortcut"
        super.init(window: window)
        window.delegate = self
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let theme = SettingsKit.theme
        window?.appearance = theme.appearance
        window?.backgroundColor = theme.windowBackground

        nameField.stringValue = action.name
        nameField.placeholderString = "Search GitHub"
        iconPicker.select(Self.symbols.firstIndex(of: action.symbol) ?? 0, notify: false)

        let nameRow = SettingsKit.row("Name", control: { nameField.widthAnchor.constraint(equalToConstant: 260).isActive = true; return nameField }())
        let iconRow = SettingsKit.row("Icon", detail: "An SF Symbol", control: iconPicker)

        stepsStack.orientation = .vertical
        stepsStack.alignment = .leading
        stepsStack.spacing = 6
        rebuildSteps()

        let addStep = MenuButton(titles: ["+ Add a step", "Open a link", "Open an app…", "Run a Shortcut", "Shell command", "AppleScript", "Type text", "Wait"])
        addStep.onSelect = { [weak self] index in
            guard let self, index > 0 else { return }
            self.commitFields()
            switch index {
            case 1: self.action.steps.append(.openURL("https://"))
            case 2: self.pickApp()
            case 3: self.action.steps.append(.runShortcut(""))
            case 4: self.action.steps.append(.shell(""))
            case 5: self.action.steps.append(.appleScript("tell application \"Music\" to playpause"))
            case 6: self.action.steps.append(.typeText(""))
            default: self.action.steps.append(.wait(1))
            }
            addStep.select(0, notify: false)
            self.rebuildSteps()
        }

        let help = NSTextField(wrappingLabelWithString: "Steps run in order. In a link, {query} asks for a word when you run it from ⌘K (a hotkey uses what's copied), and {clipboard} is what's copied. Shell commands run with your login shell's PATH.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = theme.tertiaryText

        let cancel = SettingsKit.button("Cancel") { [weak self] in self?.close(saving: false) }
        let save = SettingsKit.button("Save", prominent: true) { [weak self] in self?.close(saving: true) }
        let buttons = NSStackView(views: [NSView(), cancel, save])

        let stepsTitle = NSTextField(labelWithString: "Steps")
        stepsTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        stepsTitle.textColor = theme.secondaryText

        let stack = NSStackView(views: [SettingsKit.section(nil, rows: [nameRow, iconRow]), stepsTitle, stepsStack, addStep, help, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)
        ])
        window?.contentView = content
    }

    private func rebuildSteps() {
        stepsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stepFields = []
        for (index, step) in action.steps.enumerated() {
            let icon = NSImageView(image: NSImage(systemSymbolName: step.symbol, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = SettingsKit.theme.secondaryText
            let kind = NSTextField(labelWithString: step.kind)
            kind.font = .systemFont(ofSize: 11)
            kind.textColor = SettingsKit.theme.secondaryText
            kind.widthAnchor.constraint(equalToConstant: 84).isActive = true

            var field: NSTextField?
            var views: [NSView] = [icon, kind]
            switch step {
            case .openApp(let path):
                views.append(NSTextField(labelWithString: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent))
            case .wait(let seconds):
                let input = NSTextField(string: String(seconds))
                input.widthAnchor.constraint(equalToConstant: 60).isActive = true
                field = input
                views.append(input)
                views.append(NSTextField(labelWithString: "seconds"))
            default:
                let input = NSTextField(string: Self.text(of: step))
                input.placeholderString = Self.placeholder(for: step)
                input.font = step.kind == "Shell" || step.kind == "AppleScript" ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 12)
                input.widthAnchor.constraint(equalToConstant: 330).isActive = true
                field = input
                views.append(input)
            }
            stepFields.append(field)
            let remove = SettingsKit.button("×") { [weak self] in
                guard let self else { return }
                self.commitFields()
                self.action.steps.remove(at: index)
                self.rebuildSteps()
            }
            views.append(remove)
            let row = NSStackView(views: views)
            row.spacing = 8
            row.alignment = .centerY
            stepsStack.addArrangedSubview(row)
        }
    }

    private static func text(of step: CustomAction.Step) -> String {
        switch step {
        case .openURL(let value), .runShortcut(let value), .shell(let value), .appleScript(let value), .typeText(let value): return value
        case .openApp(let path): return path
        case .wait(let seconds): return String(seconds)
        }
    }

    private static func placeholder(for step: CustomAction.Step) -> String {
        switch step {
        case .openURL: return "https://github.com/search?q={query}"
        case .runShortcut: return "The Shortcut's exact name"
        case .shell: return "open ~/Downloads"
        case .appleScript: return "tell application \"Music\" to playpause"
        case .typeText: return "Text to type"
        default: return ""
        }
    }

    /// Text fields hold edits until a step is added, removed, or the shortcut saved.
    private func commitFields() {
        for (index, field) in stepFields.enumerated() {
            guard let field, action.steps.indices.contains(index) else { continue }
            let value = field.stringValue
            switch action.steps[index] {
            case .openURL: action.steps[index] = .openURL(value)
            case .runShortcut: action.steps[index] = .runShortcut(value)
            case .shell: action.steps[index] = .shell(value)
            case .appleScript: action.steps[index] = .appleScript(value)
            case .typeText: action.steps[index] = .typeText(value)
            case .wait: action.steps[index] = .wait(Double(value) ?? 1)
            case .openApp: break
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url {
            action.steps.append(.openApp(url.path))
            if action.name.isEmpty, nameField.stringValue.isEmpty {
                nameField.stringValue = "Open " + url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func close(saving: Bool) {
        if saving {
            commitFields()
            action.name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            action.symbol = Self.symbols[max(0, iconPicker.selectedIndex)]
            guard action.name.isEmpty == false else {
                NSSound.beep()
                window?.makeFirstResponder(nameField)
                return
            }
            onSave?(action)
        }
        if let window, let parent = window.sheetParent { parent.endSheet(window) } else { window?.close() }
    }
}
