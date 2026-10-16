import AppKit

/// One quick-launch tile in the notch panel.
struct AppShortcut {
    let name: String
    let bundleIdentifier: String
    let url: URL

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Resolves which apps appear in the shortcut row.
///
/// Override the list without rebuilding:
///   defaults write com.notchhover.NotchHover ShortcutBundleIdentifiers -array com.apple.Safari notion.id
enum AppShortcutStore {
    static let defaultsKey = "ShortcutBundleIdentifiers"
    static let maximumShortcuts = 6

    /// Ordered by how likely they are to be wanted; anything not installed is skipped.
    static let fallbackBundleIdentifiers = [
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
        "com.microsoft.VSCode",
        "com.tinyspeck.slackmacgap",
        "notion.id",
        "net.whatsapp.WhatsApp",
        "com.spotify.client",
        "company.thebrowser.Browser",
        "com.apple.Safari"
    ]

    static func shortcuts() -> [AppShortcut] {
        let configured = UserDefaults.standard.stringArray(forKey: defaultsKey)
        let identifiers = configured?.isEmpty == false ? configured! : fallbackBundleIdentifiers

        return identifiers
            .compactMap(makeShortcut)
            .prefix(maximumShortcuts)
            .map { $0 }
    }

    private static func makeShortcut(for bundleIdentifier: String) -> AppShortcut? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return AppShortcut(name: name, bundleIdentifier: bundleIdentifier, url: url)
    }

    /// Launches the app, or brings it forward if it is already running.
    static func activate(_ shortcut: AppShortcut) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: shortcut.url, configuration: configuration) { _, error in
            if let error {
                Log.shortcuts.error("Failed to open \(shortcut.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
