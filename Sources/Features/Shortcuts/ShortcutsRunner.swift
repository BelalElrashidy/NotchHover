import AppKit

/// Runs macOS Shortcuts through the `shortcuts` CLI.
enum ShortcutsRunner {
    static let defaultsKey = "PinnedShortcuts"
    static let maximumPinned = 5

    /// Pinned names, or the first few the system reports.
    static func pinnedNames(completion: @escaping ([String]) -> Void) {
        if let configured = UserDefaults.standard.stringArray(forKey: defaultsKey), configured.isEmpty == false {
            completion(Array(configured.prefix(maximumPinned)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let names = run(arguments: ["list"])?
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.isEmpty == false } ?? []
            DispatchQueue.main.async {
                completion(Array(names.prefix(maximumPinned)))
            }
        }
    }

    /// Every Shortcut in the Shortcuts app, for picking from in Settings.
    static func allNames(completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let names = run(arguments: ["list"])?
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.isEmpty == false } ?? []
            DispatchQueue.main.async { completion(names) }
        }
    }

    static func run(named name: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run(arguments: ["run", name])
            Log.system.notice("Ran shortcut \(name, privacy: .public)")
        }
    }

    @discardableResult
    private static func run(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            Log.system.error("shortcuts CLI failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
