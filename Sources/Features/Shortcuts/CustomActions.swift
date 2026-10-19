import AppKit

/// A shortcut of your own: a name, an icon, and steps run in order. One step is a
/// quicklink or an app launcher; several make a routine — open these apps, run this
/// script, play that playlist.
struct CustomAction: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var steps: [Step]

    enum Step: Codable, Equatable {
        /// A web or app link. `{query}` asks for a word (from the ⌘K list, or the clipboard
        /// from a hotkey); `{clipboard}` is what's copied.
        case openURL(String)
        /// An app, by its path.
        case openApp(String)
        /// A macOS Shortcut, by name.
        case runShortcut(String)
        /// `zsh -lc`, so it sees your PATH.
        case shell(String)
        case appleScript(String)
        /// Typed into the front app. Needs Accessibility.
        case typeText(String)
        case wait(Double)

        var kind: String {
            switch self {
            case .openURL: return "Open link"
            case .openApp: return "Open app"
            case .runShortcut: return "Run Shortcut"
            case .shell: return "Shell"
            case .appleScript: return "AppleScript"
            case .typeText: return "Type text"
            case .wait: return "Wait"
            }
        }

        var summary: String {
            switch self {
            case .openURL(let url): return url
            case .openApp(let path): return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            case .runShortcut(let name): return name
            case .shell(let command): return command
            case .appleScript(let source): return source.components(separatedBy: .newlines).first ?? source
            case .typeText(let text): return text
            case .wait(let seconds): return "\(seconds) s"
            }
        }

        var symbol: String {
            switch self {
            case .openURL: return "link"
            case .openApp: return "app"
            case .runShortcut: return "bolt.fill"
            case .shell: return "terminal"
            case .appleScript: return "applescript"
            case .typeText: return "keyboard"
            case .wait: return "hourglass"
            }
        }

        var needsArgument: Bool {
            if case .openURL(let url) = self { return url.contains("{query}") }
            return false
        }
    }

    /// What it's called in the shortcuts list: a quicklink, an app, a script — or Steps.
    var kindTitle: String {
        guard steps.count == 1, let step = steps.first else { return "Steps" }
        switch step {
        case .openURL: return "Quicklink"
        case .openApp: return "App"
        case .runShortcut: return "Shortcut"
        case .shell, .appleScript: return "Script"
        case .typeText: return "Snippet"
        case .wait: return "Steps"
        }
    }

    var action: NotchAction {
        NotchAction(
            id: "custom.\(id.uuidString)",
            title: name,
            group: "Yours",
            symbol: symbol,
            defaultHotkey: nil,
            panelKeys: nil,
            isCustom: true,
            argumentPrompt: steps.contains(where: \.needsArgument) ? name : nil,
            run: { argument in CustomActionRunner.run(self, argument: argument) }
        )
    }
}

/// Your shortcuts, saved beside everything else in Application Support.
final class CustomActionStore {
    static let shared = CustomActionStore()
    private static let fileName = "Shortcuts/custom.json"

    private(set) var items: [CustomAction] = []

    private init() {
        items = LocalStore.load([CustomAction].self, from: Self.fileName) ?? []
    }

    func save(_ action: CustomAction) {
        if let index = items.firstIndex(where: { $0.id == action.id }) {
            items[index] = action
        } else {
            items.append(action)
        }
        persist()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    /// Preview and self-test hook.
    func loadSample(_ sample: [CustomAction]) {
        items = sample
    }

    private func persist() {
        LocalStore.ensureDirectory(LocalStore.url("Shortcuts"))
        LocalStore.save(items, to: Self.fileName)
        ActionRegistry.shared.changed()
    }
}

/// Runs a shortcut's steps one after another, off the main thread except where macOS
/// wants it.
enum CustomActionRunner {
    static func run(_ action: CustomAction, argument: String?) {
        DispatchQueue.global(qos: .userInitiated).async {
            for step in action.steps {
                guard perform(step, argument: argument) else {
                    Log.ui.error("Shortcut \(action.name, privacy: .public) stopped at \(step.kind, privacy: .public)")
                    return
                }
            }
        }
    }

    /// Fills `{query}` and `{clipboard}`; percent-encoded for links.
    static func fill(_ template: String, argument: String?, encode: Bool) -> String {
        let clipboard = DispatchQueue.main.sync { NSPasteboard.general.string(forType: .string) } ?? ""
        func encoded(_ value: String) -> String {
            encode ? (value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? value) : value
        }
        return template
            .replacingOccurrences(of: "{query}", with: encoded(argument ?? clipboard))
            .replacingOccurrences(of: "{clipboard}", with: encoded(clipboard))
    }

    @discardableResult
    static func perform(_ step: CustomAction.Step, argument: String?) -> Bool {
        switch step {
        case .openURL(let template):
            guard let url = URL(string: fill(template, argument: argument, encode: true)) else { return false }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            return true

        case .openApp(let path):
            let semaphore = DispatchSemaphore(value: 0)
            var opened = false
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { app, _ in
                    opened = app != nil
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + 10)
            return opened

        case .runShortcut(let name):
            return runProcess("/usr/bin/shortcuts", ["run", name])

        case .shell(let command):
            return runProcess("/bin/zsh", ["-lc", fill(command, argument: argument, encode: false)])

        case .appleScript(let source):
            let filled = fill(source, argument: argument, encode: false)
            var ok = false
            DispatchQueue.main.sync {
                var error: NSDictionary?
                NSAppleScript(source: filled)?.executeAndReturnError(&error)
                ok = error == nil
            }
            return ok

        case .typeText(let text):
            guard AXIsProcessTrusted() else { return false }
            for character in fill(text, argument: argument, encode: false) {
                let utf16 = Array(String(character).utf16)
                for isDown in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown)
                    event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    event?.post(tap: .cghidEventTap)
                }
                usleep(4000)
            }
            return true

        case .wait(let seconds):
            Thread.sleep(forTimeInterval: min(30, max(0, seconds)))
            return true
        }
    }

    /// A step that hangs doesn't hold the rest forever: thirty seconds, then it's stopped.
    private static func runProcess(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); return false }
        return process.terminationStatus == 0
    }
}
