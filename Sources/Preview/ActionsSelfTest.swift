import AppKit
import Carbon.HIToolbox

/// Hotkeys, clashes and your own shortcuts, without pressing anything: --actions-selftest
/// Uses its own defaults keys' values and puts them back.
enum ActionsSelfTest {
    static func run() {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: "ShortcutHotkeys"), defaults.object(forKey: "ShortcutsDisabled"))
        defer {
            defaults.set(saved.0, forKey: "ShortcutHotkeys")
            defaults.set(saved.1, forKey: "ShortcutsDisabled")
        }
        defaults.removeObject(forKey: "ShortcutHotkeys")
        defaults.removeObject(forKey: "ShortcutsDisabled")

        let home = KeyCombo.controlOption(kVK_ANSI_H, "H")
        expect("⌃⌥H reads as ⌃⌥H", home.display == "⌃⌥H")
        expect("…and draws as three keycaps", home.parts == ["⌃", "⌥", "H"])

        let registry = ActionRegistry.shared
        func action(_ id: String, _ key: KeyCombo?) -> NotchAction {
            NotchAction(id: id, title: id, group: "Test", symbol: "bolt", defaultHotkey: key, panelKeys: nil,
                        isCustom: false, argumentPrompt: nil, run: { _ in })
        }
        CustomActionStore.shared.loadSample([])
        registry.register([action("a", home), action("b", nil)])
        expect("a default hotkey applies", registry.hotkey(for: "a") == home)
        expect("no clash to begin with", registry.conflictingIDs.isEmpty)

        registry.setHotkey(home, for: "b")
        expect("the same keys on two actions is a clash", registry.conflictingIDs == ["a", "b"])
        expect("…and says which", registry.conflict(for: home, excluding: "b")?.id == "a")
        registry.setEnabled(false, for: "a")
        expect("switching one off ends the clash", registry.conflictingIDs.isEmpty)
        registry.setEnabled(true, for: "a")

        registry.setHotkey(nil, for: "a")
        expect("a hotkey can be removed", registry.hotkey(for: "a") == nil && registry.isChanged("a"))
        registry.resetHotkey(for: "a")
        expect("…and reset to its default", registry.hotkey(for: "a") == home && registry.isChanged("a") == false)

        let quicklink = CustomAction(id: UUID(), name: "Search", symbol: "magnifyingglass", steps: [.openURL("https://example.com/?q={query}")])
        expect("a {query} link asks for a word", quicklink.action.argumentPrompt != nil)
        expect("one link step is a Quicklink", quicklink.kindTitle == "Quicklink")
        var filled = ""
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            filled = CustomActionRunner.fill("https://example.com/?q={query}", argument: "notch & hover", encode: true)
            done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        expect("the word is encoded into the link (\(filled))", filled == "https://example.com/?q=notch%20%26%20hover")

        let failed = results.filter { $0.hasPrefix("✗") }.count
        FileHandle.standardError.write(Data(("actions: " + results.joined(separator: "  ") + "\n").utf8))
        exit(failed == 0 ? 0 : 1)
    }
}
