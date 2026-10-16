import AppKit

/// A line of "what's going on" for an app, shown when its tile is clicked.
struct AppDetailLine {
    let label: String
    let value: String
}

struct AppDetails {
    let shortcut: AppShortcut
    let statusText: String
    let lines: [AppDetailLine]
}

/// Gathers whatever each app can tell us. Claude gets a dedicated path — running
/// sessions, the project it is working in, and the state of the permission bridge —
/// while everything else reports process-level facts.
enum AppDetailProvider {
    static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"

    /// Runs the process/file lookups off the main thread.
    static func fetch(for shortcut: AppShortcut, pendingRequests: Int, completion: @escaping (AppDetails) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let details = shortcut.bundleIdentifier == claudeBundleIdentifier
                ? claudeDetails(for: shortcut, pendingRequests: pendingRequests)
                : genericDetails(for: shortcut)
            DispatchQueue.main.async { completion(details) }
        }
    }

    // MARK: - Claude

    private static func claudeDetails(for shortcut: AppShortcut, pendingRequests: Int) -> AppDetails {
        let sessions = claudeCodeSessionCount()
        let recent = mostRecentProject()

        var lines: [AppDetailLine] = [
            AppDetailLine(label: "Desktop", value: shortcut.isRunning ? "Running" : "Not running"),
            AppDetailLine(label: "Code sessions", value: sessions == 0 ? "None" : "\(sessions) running")
        ]

        if let recent {
            lines.append(AppDetailLine(label: "Project", value: recent.name))
            lines.append(AppDetailLine(label: "Last active", value: relativeTime(since: recent.modified)))
        }

        lines.append(AppDetailLine(
            label: "Approvals",
            value: bridgeHookInstalled()
                ? (pendingRequests > 0 ? "\(pendingRequests) waiting" : "Ready")
                : "Hook not installed"
        ))

        let status = pendingRequests > 0
            ? "\(pendingRequests) permission request\(pendingRequests == 1 ? "" : "s") waiting"
            : (sessions > 0 ? "\(sessions) session\(sessions == 1 ? "" : "s") active" : "Idle")

        return AppDetails(shortcut: shortcut, statusText: status, lines: lines)
    }

    /// Claude Code runs as a `claude` executable outside the desktop app's process tree.
    private static func claudeCodeSessionCount() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .filter { $0.isEmpty == false }
                .count ?? 0
        } catch {
            return 0
        }
    }

    private static func mostRecentProject() -> (name: String, modified: Date)? {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: projects,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let newest = entries
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return nil
                }
                return (url, date)
            }
            .max { $0.1 < $1.1 }

        guard let newest else { return nil }
        // Directory names are the project path with separators flattened to dashes.
        let name = newest.0.lastPathComponent
            .split(separator: "-")
            .last
            .map(String.init) ?? newest.0.lastPathComponent
        return (name, newest.1)
    }

    private static func bridgeHookInstalled() -> Bool {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let contents = try? String(contentsOf: settings, encoding: .utf8) else { return false }
        return contents.contains("claude-permission-hook")
    }

    // MARK: - Everything else

    private static func genericDetails(for shortcut: AppShortcut) -> AppDetails {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier).first

        var lines = [AppDetailLine(label: "Status", value: running == nil ? "Not running" : "Running")]

        if let running {
            if let launch = running.launchDate {
                lines.append(AppDetailLine(label: "Since", value: relativeTime(since: launch)))
            }
            lines.append(AppDetailLine(label: "Frontmost", value: running.isActive ? "Yes" : "No"))
        }

        if let version = versionString(for: shortcut) {
            lines.append(AppDetailLine(label: "Version", value: version))
        }

        return AppDetails(
            shortcut: shortcut,
            statusText: running == nil ? "Not running — click Open to launch" : "Running",
            lines: lines
        )
    }

    private static func versionString(for shortcut: AppShortcut) -> String? {
        let plist = shortcut.url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return info["CFBundleShortVersionString"] as? String
    }

    private static func relativeTime(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
