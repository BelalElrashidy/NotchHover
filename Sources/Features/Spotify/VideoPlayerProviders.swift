import AppKit

/// VLC over AppleScript: the item's name, where it is, play/pause, next and previous.
/// VLC doesn't say who the artist is.
final class VLCProvider: MediaProvider {
    let appName = "VLC"
    let bundleIdentifier = "org.videolan.vlc"

    var selfTestScripts: [String] { [fetchScript] }

    private var fetchScript: String {
        """
        tell application id "\(bundleIdentifier)"
            set itemName to ""
            try
                set itemName to name of current item
            end try
            if itemName is missing value or itemName is "" then return ""
            set pos to 0
            try
                set pos to current time
            end try
            set dur to 0
            try
                set dur to duration of current item
            end try
            set vol to -1
            try
                set vol to audio volume
            end try
            return itemName & "||" & (playing as text) & "||" & pos & "||" & dur & "||" & vol
        end tell
        """
    }

    func fetchTrack() throws -> TrackInfo? {
        let parts = (try AppleScript.run(fetchScript).stringValue ?? "").components(separatedBy: "||")
        guard parts.count >= 5, parts[0].isEmpty == false else { return nil }
        let isPlaying = parts[1] == "true"
        let position = Double(parts[2]) ?? 0
        // Something opened and never played isn't worth a place on the bar.
        guard isPlaying || position > 0 else { return nil }
        // VLC's volume runs to 512, with 256 as 100%.
        let volume = Double(parts[4]).map { Int(min(100, max(0, $0 / 2.56))) }
        return TrackInfo(
            name: (parts[0] as NSString).deletingPathExtension,
            artist: "",
            isPlaying: isPlaying,
            artworkURL: nil,
            sourceName: appName,
            sourceBundleIdentifier: bundleIdentifier,
            position: position,
            duration: Double(parts[3]) ?? 0,
            volume: (volume ?? -1) >= 0 ? volume : nil,
            isShuffling: false,
            supportsShuffle: false
        )
    }

    func control(_ action: MediaAction) throws {
        let command: String
        switch action {
        // `play` toggles in VLC.
        case .playPause: command = "play"
        case .nextTrack: command = "next"
        case .previousTrack: command = "previous"
        case .seek(let seconds): command = "set current time to \(Int(max(0, seconds)))"
        case .setVolume(let percent): command = "set audio volume to \(Int(Double(max(0, min(100, percent))) * 2.56))"
        case .toggleShuffle, .play: return
        }
        _ = try AppleScript.run("tell application id \"\(bundleIdentifier)\" to \(command)")
    }
}

/// QuickTime Player: whichever open movie is playing, or the front one left part way.
final class QuickTimeProvider: MediaProvider {
    let appName = "QuickTime Player"
    let bundleIdentifier = "com.apple.QuickTimePlayerX"

    /// The document's position in the list when last read.
    private var documentIndex = 1

    var selfTestScripts: [String] { [fetchScript] }

    private var fetchScript: String {
        """
        tell application id "\(bundleIdentifier)"
            set chosen to 0
            set docIndex to 0
            repeat with aDocument in documents
                set docIndex to docIndex + 1
                try
                    if playing of aDocument then
                        set chosen to docIndex
                        exit repeat
                    end if
                end try
            end repeat
            if chosen is 0 then
                if (count of documents) is 0 then return ""
                set chosen to 1
            end if
            set theDocument to document chosen
            set pos to 0
            try
                set pos to current time of theDocument
            end try
            set dur to 0
            try
                set dur to duration of theDocument
            end try
            set vol to -1
            try
                set vol to audio volume of theDocument
            end try
            return (chosen as text) & "||" & (name of theDocument) & "||" & ((playing of theDocument) as text) & "||" & pos & "||" & dur & "||" & vol
        end tell
        """
    }

    func fetchTrack() throws -> TrackInfo? {
        let parts = (try AppleScript.run(fetchScript).stringValue ?? "").components(separatedBy: "||")
        guard parts.count >= 6, parts[1].isEmpty == false else { return nil }
        let isPlaying = parts[2] == "true"
        let position = Double(parts[3]) ?? 0
        let duration = Double(parts[4]) ?? 0
        // A recording window or a movie never started isn't something playing.
        guard isPlaying || position > 0, duration > 0 else { return nil }
        documentIndex = Int(parts[0]) ?? 1
        let volume = Double(parts[5]).map { Int(min(100, max(0, $0 * 100))) }
        return TrackInfo(
            name: (parts[1] as NSString).deletingPathExtension,
            artist: "",
            isPlaying: isPlaying,
            artworkURL: nil,
            sourceName: appName,
            sourceBundleIdentifier: bundleIdentifier,
            position: position,
            duration: duration,
            volume: (volume ?? -1) >= 0 ? volume : nil,
            isShuffling: false,
            supportsShuffle: false
        )
    }

    func control(_ action: MediaAction) throws {
        let document = "document \(documentIndex)"
        let command: String
        switch action {
        case .playPause: command = "if playing of \(document) then\npause \(document)\nelse\nplay \(document)\nend if"
        // No playlist: previous goes back to the start, next has nowhere to go.
        case .previousTrack: command = "set current time of \(document) to 0"
        case .seek(let seconds): command = "set current time of \(document) to \(max(0, seconds))"
        case .setVolume(let percent): command = "set audio volume of \(document) to \(Double(max(0, min(100, percent))) / 100)"
        case .nextTrack, .toggleShuffle, .play: return
        }
        _ = try AppleScript.run("tell application id \"\(bundleIdentifier)\"\n\(command)\nend tell")
    }
}
