import Foundation

/// One timer, one AppleScript call per tick, fanned out to everything that shows
/// now-playing state. The menu bar and the notch used to poll independently.
final class NowPlayingPoller {
    private let mediaController: MediaControlling
    private var observers: [UUID: (Result<TrackInfo?, MediaError>) -> Void] = [:]
    private var timer: Timer?

    /// Faster while the panel is open, slower when it is only feeding the idle bar.
    var interval: TimeInterval = 2 {
        didSet {
            guard interval != oldValue, timer != nil else { return }
            start()
        }
    }

    init(mediaController: MediaControlling) {
        self.mediaController = mediaController
    }

    @discardableResult
    func addObserver(_ handler: @escaping (Result<TrackInfo?, MediaError>) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func start() {
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-read after a transport command, once the player has settled.
    func refreshSoon(after delay: TimeInterval = 0.35) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        mediaController.fetchNowPlaying { [weak self] result in
            self?.observers.values.forEach { $0(result) }
        }
    }
}
