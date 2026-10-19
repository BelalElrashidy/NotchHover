import AppKit

/// What plays next in Apple Music — read from the Music app over AppleScript, so it
/// stays on the Mac. Music only lets scripts see the playlist or album it is playing
/// from, not its Up Next queue, so this is "next in the playlist": right when playing a
/// playlist or album in order, and hidden when shuffled, because then the order is
/// Music's own. Spotify keeps its queue on its servers; it can't be read without the
/// internet, so Spotify tracks show none.
final class MusicQueue {
    static let shared = MusicQueue()

    struct Entry: Equatable {
        let index: Int
        let title: String
        let artist: String
    }

    private(set) var upNext: [Entry] = []
    private var observers: [UUID: ([Entry]) -> Void] = [:]
    private var trackKey: String?
    private let queue = DispatchQueue(label: "com.notchhover.musicqueue", qos: .utility)

    @discardableResult
    func addObserver(_ handler: @escaping ([Entry]) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    /// Called with each track reading; only a new Music track is looked at again.
    func refresh(for track: TrackInfo?) {
        guard let track, track.sourceBundleIdentifier == "com.apple.Music" else {
            trackKey = nil
            publish([])
            return
        }
        let key = "\(track.name)|\(track.artist)|\(track.album)"
        guard key != trackKey else { return }
        trackKey = key
        queue.async { [weak self] in
            let entries = Self.read()
            DispatchQueue.main.async { self?.publish(entries) }
        }
    }

    func play(_ entry: Entry) {
        queue.async {
            Self.run("tell application \"Music\" to play track \(entry.index) of current playlist")
        }
    }

    private func publish(_ entries: [Entry]) {
        guard entries != upNext else { return }
        upNext = entries
        observers.values.forEach { $0(entries) }
    }

    /// Preview hook.
    func publishForPreview(_ entries: [Entry]) {
        publish(entries)
    }

    private static func read() -> [Entry] {
        let script = """
        tell application "Music"
            if player state is stopped then return ""
            -- Shuffled, the next track is Music's choice, not the playlist's.
            if shuffle enabled then return ""
            set theOutput to ""
            try
                set thePlaylist to current playlist
                set thePosition to index of current track
                set theTotal to count of tracks of thePlaylist
                repeat with i from (thePosition + 1) to (thePosition + 3)
                    if i > theTotal then exit repeat
                    set theTrack to track i of thePlaylist
                    set theOutput to theOutput & i & "||" & (name of theTrack) & "||" & (artist of theTrack) & linefeed
                end repeat
            end try
            return theOutput
        end tell
        """
        return run(script)?
            .split(separator: "\n")
            .compactMap { line -> Entry? in
                let parts = line.components(separatedBy: "||")
                guard parts.count >= 3, let index = Int(parts[0]) else { return nil }
                return Entry(index: index, title: parts[1], artist: parts[2])
            } ?? []
    }

    @discardableResult
    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { Log.media.error("Music queue: \(error[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public)") }
        return result.stringValue
    }
}
