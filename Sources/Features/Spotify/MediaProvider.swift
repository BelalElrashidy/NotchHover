import AppKit

/// One app NotchHover can read a track from and send play, pause and skip to: a music
/// app, a video player, or a browser. `MediaHub` asks each running one in turn.
protocol MediaProvider: AnyObject {
    var appName: String { get }
    var bundleIdentifier: String { get }
    /// Nil when the app is running but has nothing loaded. Called on the media queue.
    func fetchTrack() throws -> TrackInfo?
    /// Called on the media queue.
    func control(_ action: MediaAction) throws
}

extension MediaProvider {
    /// Installed where apps are installed. An updater's own copy in Application
    /// Support — Microsoft's keeps a whole Edge there — doesn't count.
    var isInstalled: Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }
        return url.path.contains("/Application Support/") == false
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }
}

/// Runs AppleScript and turns its errors into `MediaError`s.
enum AppleScript {
    /// The error AppleScript reported, with its number, so a caller can tell a refusal
    /// from a script that simply failed.
    struct Failure: Error {
        let number: Int
        let message: String
    }

    static func run(_ source: String) throws -> NSAppleEventDescriptor {
        do {
            return try runReportingFailure(source)
        } catch let failure as Failure {
            throw MediaError.scriptExecutionFailed(failure.message)
        }
    }

    static func runReportingFailure(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw Failure(number: 0, message: "Unable to initialize AppleScript source.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = [
                errorInfo[NSAppleScript.errorMessage] as? String,
                errorInfo[NSAppleScript.errorBriefMessage] as? String
            ]
            .compactMap { $0 }
            .joined(separator: " | ")
            throw Failure(number: errorInfo[NSAppleScript.errorNumber] as? Int ?? 0,
                          message: message.isEmpty ? "Unknown AppleScript error." : message)
        }
        return result
    }

    /// A Swift string as an AppleScript string literal.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
