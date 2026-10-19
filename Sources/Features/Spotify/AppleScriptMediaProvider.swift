import AppKit

/// Drives one media app over AppleScript. Spotify, Music and TV share the same verbs
/// (`playpause`, `next track`, `player state`), so one provider covers all three.
final class AppleScriptMediaProvider: MediaProvider {
    let appName: String
    let bundleIdentifier: String
    /// Spotify exposes `artwork url`; Music and TV only have the picture itself.
    private let supportsArtworkURL: Bool
    /// Spotify reports track length in milliseconds; Music reports seconds.
    private let reportsDurationInMilliseconds: Bool

    init(appName: String, bundleIdentifier: String, supportsArtworkURL: Bool, reportsDurationInMilliseconds: Bool = false) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.supportsArtworkURL = supportsArtworkURL
        self.reportsDurationInMilliseconds = reportsDurationInMilliseconds
    }

    /// Music and TV: the same dictionary, with radio streams and embedded artwork.
    private var isAppleMediaApp: Bool {
        bundleIdentifier == "com.apple.Music" || bundleIdentifier == "com.apple.TV"
    }

    private var isTV: Bool { bundleIdentifier == "com.apple.TV" }

    // MARK: - Scripts

    /// Spotify calls it `shuffling`; Music calls it `shuffle enabled`.
    private var shuffleProperty: String {
        bundleIdentifier == "com.apple.Music" ? "shuffle enabled" : "shuffling"
    }

    private var currentTrackScript: String {
        // "playing" on its own is a reserved player state constant, so the variable
        // holding the comparison result needs a different name.
        let artworkLookup = supportsArtworkURL ? """
                try
                    set artURL to artwork url of current track
                end try
        """ : ""

        // A radio station's track is the station; what's on is in the stream title, as
        // "Artist - Song". A TV episode has a show where a song has an artist.
        let appleExtras = isAppleMediaApp ? """
                set streamTitle to ""
                try
                    set streamTitle to current stream title
                end try
                if streamTitle is missing value then set streamTitle to ""
                if streamTitle is not "" then
                    set trackName to streamTitle
                    set trackArtist to ""
                end if
        """ + (isTV ? "\n" + """
                if trackArtist is "" then
                    try
                        set trackArtist to show of current track
                    end try
                end if
        """ : "") : ""

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
                set shuf to (\(shuffleProperty) as text)
            end try
            set alb to ""
            try
                set alb to album of current track
            end try
            set trackName to ""
            try
                set trackName to name of current track
            end try
            set trackArtist to ""
            try
                set trackArtist to artist of current track
            end try
        \(appleExtras)
            return trackName & "||" & trackArtist & "||" & artURL & "||" & isPlayingText & "||" & pos & "||" & dur & "||" & vol & "||" & shuf & "||" & alb
        end tell
        """
    }

    private func script(for action: MediaAction) -> String {
        switch action {
        case .toggleShuffle where isTV:
            return ""
        case .playPause:
            return "tell application \"\(appName)\" to playpause"
        case .nextTrack:
            return "tell application \"\(appName)\" to next track"
        case .previousTrack:
            return "tell application \"\(appName)\" to previous track"
        case .toggleShuffle:
            return "tell application \"\(appName)\" to set \(shuffleProperty) to not \(shuffleProperty)"
        case .setVolume(let percent):
            return "tell application \"\(appName)\" to set sound volume to \(max(0, min(100, percent)))"
        case .seek(let seconds):
            return "tell application \"\(appName)\" to set player position to \(max(0, seconds))"
        case .play(let uri):
            // `play track` takes any Spotify URI, playlists and albums included.
            return "tell application \"\(appName)\" to play track \"\(uri)\""
        }
    }

    /// Every script this provider runs, for --media-selftest to compile.
    var selfTestScripts: [String] {
        [currentTrackScript, script(for: .playPause), script(for: .toggleShuffle), script(for: .seek(1)), script(for: .setVolume(50))]
            .filter { $0.isEmpty == false }
    }

    // MARK: - Operations (callers must be on the media queue)

    /// Returns nil when the player is running but stopped.
    func fetchTrack() throws -> TrackInfo? {
        let response = try AppleScript.run(currentTrackScript).stringValue ?? ""
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

        var name = components[0]
        var artist = components[1]
        // "Artist - Song", from a radio stream.
        if isAppleMediaApp, artist.isEmpty, let dash = name.range(of: " - ") {
            artist = String(name[..<dash.lowerBound])
            name = String(name[dash.upperBound...])
        }
        guard name.isEmpty == false else { return nil }

        let rawDuration = Double(value(5)) ?? 0
        let volume = Int(Double(value(6)) ?? -1)
        let artworkURL = supportsArtworkURL ? URL(string: value(2)) : artworkFile(name: name, artist: artist, album: value(8))

        return TrackInfo(
            name: name,
            artist: artist,
            isPlaying: components.count > 3 ? value(3) == "true" : true,
            // Local files report no artwork, so the field can be empty.
            artworkURL: artworkURL,
            sourceName: appName,
            sourceBundleIdentifier: bundleIdentifier,
            position: Double(value(4)) ?? 0,
            duration: reportsDurationInMilliseconds ? rawDuration / 1000 : rawDuration,
            volume: volume >= 0 ? volume : nil,
            isShuffling: value(7) == "true",
            album: value(8),
            supportsShuffle: isTV == false
        )
    }

    // MARK: - Embedded artwork

    /// Music and TV hand over the picture itself rather than an address, so it is
    /// written once per track to a file the rest of the app can load like any other.
    private var artworkCache: (key: String, url: URL?)?

    private func artworkFile(name: String, artist: String, album: String) -> URL? {
        let key = [name, artist, album].joined(separator: "|")
        if let cache = artworkCache, cache.key == key { return cache.url }

        var url: URL?
        let source = """
        tell application id "\(bundleIdentifier)"
            if (count of artworks of current track) is 0 then return ""
            return raw data of artwork 1 of current track
        end tell
        """
        if let data = try? AppleScript.run(source).data, data.count > 64, NSImage(data: data) != nil {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchHoverArtwork", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // One file per app, replaced each track: the loader caches by address, so
            // the name carries the track too.
            if let previous = artworkCache?.url { try? FileManager.default.removeItem(at: previous) }
            let file = folder.appendingPathComponent("\(bundleIdentifier)-\(UInt(bitPattern: key.hashValue)).img")
            if (try? data.write(to: file)) != nil { url = file }
        }
        artworkCache = (key, url)
        return url
    }

    func control(_ action: MediaAction) throws {
        let source = script(for: action)
        guard source.isEmpty == false else { return }
        _ = try AppleScript.run(source)
    }
}
