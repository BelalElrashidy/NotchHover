import AppKit

/// A track from whichever media app is currently active.
struct TrackInfo: Equatable {
    let name: String
    let artist: String
    let isPlaying: Bool
    let artworkURL: URL?
    let sourceName: String
    let sourceBundleIdentifier: String
    /// Seconds elapsed, and total track length. Zero when the player will not say.
    let position: Double
    let duration: Double
    /// The player's own volume, 0-100, or nil if unavailable.
    let volume: Int?
    let isShuffling: Bool

    var menuBarText: String {
        artist.isEmpty ? name : "\(name) - \(artist)"
    }
}

enum MediaAction {
    case playPause
    case nextTrack
    case previousTrack
    case toggleShuffle
    /// Player volume, 0-100.
    case setVolume(Int)
    case seek(Double)
    /// Play a Spotify URI: track, album, or playlist.
    case play(uri: String)
}

enum MediaError: LocalizedError {
    /// None of the supported players are installed.
    case noPlayerInstalled
    /// Players are installed, but none are running. Carries the best one to suggest.
    case noPlayerRunning(String)
    case scriptExecutionFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noPlayerInstalled:
            return "No supported media app is installed."
        case .noPlayerRunning(let name):
            return "\(name) is not running."
        case .scriptExecutionFailed(let detail):
            return "Media script failed: \(detail)"
        case .invalidResponse:
            return "The media app returned an invalid response."
        }
    }

    /// What the notch says. A player that isn't open is not something to fix — it just
    /// means nothing is playing — so only a real failure gets its own wording.
    var shortDisplayText: String {
        switch self {
        case .noPlayerInstalled, .noPlayerRunning, .invalidResponse:
            return "Nothing playing"
        case .scriptExecutionFailed:
            return "Playback error"
        }
    }
}

protocol MediaControlling {
    func fetchNowPlaying(completion: @escaping (Result<TrackInfo?, MediaError>) -> Void)
    func control(_ action: MediaAction, completion: @escaping (Result<Void, MediaError>) -> Void)
}

/// What the panel should display for the media section.
enum NowPlayingState {
    case track(TrackInfo)
    /// Something is playing that we can neither name nor control — a video in a
    /// browser, a call, a game. All we have is the app it is coming out of.
    case external(AudioSource)
    case message(String)
}
