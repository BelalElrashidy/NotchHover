import AppKit

/// Drives one media app over AppleScript. Spotify and Music share the same verbs
/// (`playpause`, `next track`, `player state`), so one provider covers both.
final class AppleScriptMediaProvider {
    let appName: String
    let bundleIdentifier: String
    /// Spotify exposes `artwork url`; Music only has embedded artwork data.
    private let supportsArtworkURL: Bool
    /// Spotify reports track length in milliseconds; Music reports seconds.
    private let reportsDurationInMilliseconds: Bool

    init(appName: String, bundleIdentifier: String, supportsArtworkURL: Bool, reportsDurationInMilliseconds: Bool = false) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.supportsArtworkURL = supportsArtworkURL
        self.reportsDurationInMilliseconds = reportsDurationInMilliseconds
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    // MARK: - Scripts

    private var currentTrackScript: String {
        // "playing" on its own is a reserved player state constant, so the variable
        // holding the comparison result needs a different name.
        let artworkLookup = supportsArtworkURL ? """
                try
                    set artURL to artwork url of current track
                end try
        """ : ""

        return """
        tell application "\(appName)"
            if player state is stopped then
                return ""
            end if
            set artURL to ""
        \(artworkLookup)
            set isPlayingText to (player state is playing) as text
            set pos to 0
            try
                set pos to player position
            end try
            set dur to 0
            try
                set dur to duration of current track
            end try
            set vol to -1
            try
                set vol to sound volume
            end try
            set shuf to "false"
            try
                set shuf to (shuffling as text)
            end try
            set alb to ""
            try
                set alb to album of current track
            end try
            return (name of current track) & "||" & (artist of current track) & "||" & artURL & "||" & isPlayingText & "||" & pos & "||" & dur & "||" & vol & "||" & shuf & "||" & alb
        end tell
        """
    }

    private func script(for action: MediaAction) -> String {
        switch action {
        case .playPause:
            return "tell application \"\(appName)\" to playpause"
        case .nextTrack:
            return "tell application \"\(appName)\" to next track"
        case .previousTrack:
            return "tell application \"\(appName)\" to previous track"
        case .toggleShuffle:
            return "tell application \"\(appName)\" to set shuffling to not shuffling"
        case .setVolume(let percent):
            return "tell application \"\(appName)\" to set sound volume to \(max(0, min(100, percent)))"
        case .seek(let seconds):
            return "tell application \"\(appName)\" to set player position to \(max(0, seconds))"
        case .play(let uri):
            // `play track` takes any Spotify URI, playlists and albums included.
            return "tell application \"\(appName)\" to play track \"\(uri)\""
        }
    }

    // MARK: - Operations (callers must be on the media queue)

    /// Returns nil when the player is running but stopped.
    func fetchTrack() throws -> TrackInfo? {
        let response = try execute(currentTrackScript).stringValue ?? ""
        guard response.isEmpty == false else { return nil }

        let components = response
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.count >= 2 else {
            throw MediaError.invalidResponse
        }

        func value(_ index: Int) -> String {
            components.count > index ? components[index] : ""
        }

        let rawDuration = Double(value(5)) ?? 0
        let volume = Int(Double(value(6)) ?? -1)

        return TrackInfo(
            name: components[0],
            artist: components[1],
            isPlaying: components.count > 3 ? value(3) == "true" : true,
            // Local files report no artwork, so the field can be empty.
            artworkURL: components.count > 2 ? URL(string: value(2)) : nil,
            sourceName: appName,
            sourceBundleIdentifier: bundleIdentifier,
            position: Double(value(4)) ?? 0,
            duration: reportsDurationInMilliseconds ? rawDuration / 1000 : rawDuration,
            volume: volume >= 0 ? volume : nil,
            isShuffling: value(7) == "true",
            album: value(8)
        )
    }

    func control(_ action: MediaAction) throws {
        _ = try execute(script(for: action))
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw MediaError.scriptExecutionFailed("Unable to initialize AppleScript source.")
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
            throw MediaError.scriptExecutionFailed(message.isEmpty ? "Unknown AppleScript error." : message)
        }

        return result
    }
}
