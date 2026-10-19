import AppKit
import Carbon.HIToolbox

/// A key with modifiers, as Carbon's hot key API wants it, plus how to show it.
struct KeyCombo: Codable, Equatable, Hashable {
    /// A `kVK_…` code.
    let keyCode: Int
    /// Carbon modifiers: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    let modifiers: Int
    /// The key's own label, captured when it was recorded — "H", "4", "→".
    let key: String

    var display: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + key
    }

    /// Each part on its own, for drawing keycaps.
    var parts: [String] { display.map(String.init) }

    /// From a key press in the recorder. Nil without a modifier: a bare letter would
    /// fire every time it's typed.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        guard modifiers & (cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.keyCode = Int(event.keyCode)
        self.modifiers = modifiers
        self.key = Self.label(for: Int(event.keyCode), characters: event.charactersIgnoringModifiers)
    }

    init(keyCode: Int, modifiers: Int, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    static func label(for keyCode: Int, characters: String?) -> String {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1...kVK_F20 where characters == nil: return "F"
        default: return (characters ?? "?").uppercased()
        }
    }

    /// ⌃⌥ and a letter — NotchHover's own prefix.
    static func controlOption(_ keyCode: Int, _ key: String) -> KeyCombo {
        KeyCombo(keyCode: keyCode, modifiers: controlKey | optionKey, key: key)
    }
}

/// One thing NotchHover can do, by name: built in, or one of yours.
struct NotchAction {
    let id: String
    let title: String
    let group: String
    let symbol: String
    /// The global hotkey it ships with, if any.
    let defaultHotkey: KeyCombo?
    /// Keys that do it inside the open panel — shown, not changeable.
    let panelKeys: String?
    let isCustom: Bool
    /// Asks for a word before running: a quicklink with `{query}` in it.
    let argumentPrompt: String?
    let run: (_ argument: String?) -> Void
}

/// Every action, its hotkey, and whether it's on. Built-ins are registered by the app at
/// launch; yours come from `CustomActionStore`. Changing a hotkey re-registers them all,
/// since Carbon has no way to change one in place.
final class ActionRegistry {
    static let shared = ActionRegistry()

    private(set) var builtIns: [NotchAction] = []
    private var observers: [UUID: () -> Void] = [:]

    private enum Key {
        static let hotkeys = "ShortcutHotkeys"
        static let disabled = "ShortcutsDisabled"
    }

    var actions: [NotchAction] {
        builtIns + CustomActionStore.shared.items.map(\.action)
    }

    @discardableResult
    func addObserver(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func register(_ actions: [NotchAction]) {
        builtIns = actions
        bindHotkeys()
    }

    func action(_ id: String) -> NotchAction? {
        actions.first { $0.id == id }
    }

    // MARK: Hotkeys

    /// Yours, or the one it ships with. An empty override means "none".
    func hotkey(for id: String) -> KeyCombo? {
        let overrides = UserDefaults.standard.dictionary(forKey: Key.hotkeys) as? [String: Data] ?? [:]
        if let data = overrides[id] {
            return data.isEmpty ? nil : try? JSONDecoder().decode(KeyCombo.self, from: data)
        }
        return action(id)?.defaultHotkey
    }

    func setHotkey(_ combo: KeyCombo?, for id: String) {
        var overrides = UserDefaults.standard.dictionary(forKey: Key.hotkeys) as? [String: Data] ?? [:]
        if combo == action(id)?.defaultHotkey {
            overrides[id] = nil
        } else {
            overrides[id] = combo.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        }
        UserDefaults.standard.set(overrides, forKey: Key.hotkeys)
        changed()
    }

    func resetHotkey(for id: String) {
        var overrides = UserDefaults.standard.dictionary(forKey: Key.hotkeys) as? [String: Data] ?? [:]
        overrides[id] = nil
        UserDefaults.standard.set(overrides, forKey: Key.hotkeys)
        changed()
    }

    func isChanged(_ id: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: Key.hotkeys) as? [String: Data])?[id] != nil
    }

    func resetAll() {
        UserDefaults.standard.removeObject(forKey: Key.hotkeys)
        UserDefaults.standard.removeObject(forKey: Key.disabled)
        changed()
    }

    /// Another action already using this combination.
    func conflict(for combo: KeyCombo, excluding id: String) -> NotchAction? {
        actions.first { $0.id != id && isEnabled($0.id) && hotkey(for: $0.id) == combo }
    }

    var conflictingIDs: Set<String> {
        var seen: [KeyCombo: String] = [:]
        var clashes = Set<String>()
        for action in actions where isEnabled(action.id) {
            guard let combo = hotkey(for: action.id) else { continue }
            if let other = seen[combo] { clashes.formUnion([other, action.id]) } else { seen[combo] = action.id }
        }
        return clashes
    }

    // MARK: On and off

    func isEnabled(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Key.disabled) ?? []).contains(id) == false
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        var disabled = Set(UserDefaults.standard.stringArray(forKey: Key.disabled) ?? [])
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        UserDefaults.standard.set(Array(disabled), forKey: Key.disabled)
        changed()
    }

    // MARK: Running

    func run(_ id: String, argument: String? = nil) {
        guard let action = action(id), isEnabled(id) else { return }
        Log.ui.notice("Action: \(action.title, privacy: .public)")
        action.run(argument)
    }

    func changed() {
        bindHotkeys()
        observers.values.forEach { $0() }
    }

    private func bindHotkeys() {
        HotKeys.shared.unregisterAll()
        for action in actions where isEnabled(action.id) {
            guard let combo = hotkey(for: action.id) else { continue }
            let id = action.id
            HotKeys.shared.register(keyCode: combo.keyCode, modifiers: combo.modifiers) { [weak self] in
                guard let self, let action = self.action(id) else { return }
                // A hotkey can't ask for a word; a quicklink gets the clipboard instead.
                action.run(action.argumentPrompt == nil ? nil : NSPasteboard.general.string(forType: .string))
            }
        }
    }
}
