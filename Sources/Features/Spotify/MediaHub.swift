import AppKit

/// Picks whichever supported player is actually playing and routes commands to it,
/// so the panel follows the music instead of being tied to one app.
final class MediaHub: MediaControlling {
    private let providers: [AppleScriptMediaProvider]
    private let queue = DispatchQueue(label: "com.notchhover.media.apple-script", qos: .userInitiated)
    /// Remembered so transport buttons keep addressing the app that was playing,
    /// even once it is paused and another player is also running.
    private var lastActiveProvider: AppleScriptMediaProvider?

    init(providers: [AppleScriptMediaProvider] = MediaHub.defaultProviders) {
        self.providers = providers
    }

    static var defaultProviders: [AppleScriptMediaProvider] {
        [
            AppleScriptMediaProvider(
                appName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                supportsArtworkURL: true,
                reportsDurationInMilliseconds: true
            ),
            AppleScriptMediaProvider(appName: "Music", bundleIdentifier: "com.apple.Music", supportsArtworkURL: false)
        ]
    }

    func fetchNowPlaying(completion: @escaping (Result<TrackInfo?, MediaError>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let outcome = self.resolveNowPlaying()
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    func control(_ action: MediaAction, completion: @escaping (Result<Void, MediaError>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }

            let target = self.lastActiveProvider.flatMap { $0.isRunning ? $0 : nil }
                ?? self.providers.first(where: \.isRunning)

            guard let target else {
                let outcome = self.noRunningPlayerError()
                DispatchQueue.main.async { completion(.failure(outcome)) }
                return
            }

            do {
                try target.control(action)
                DispatchQueue.main.async { completion(.success(())) }
            } catch let error as MediaError {
                DispatchQueue.main.async { completion(.failure(error)) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.scriptExecutionFailed(error.localizedDescription)))
                }
            }
        }
    }

    private func resolveNowPlaying() -> Result<TrackInfo?, MediaError> {
        let running = providers.filter(\.isRunning)
        guard running.isEmpty == false else {
            return .failure(noRunningPlayerError())
        }

        var firstTrack: (provider: AppleScriptMediaProvider, track: TrackInfo)?
        var lastError: MediaError?

        for provider in running {
            do {
                guard let track = try provider.fetchTrack() else { continue }
                // A playing app always wins; otherwise keep the first paused track around.
                if track.isPlaying {
                    lastActiveProvider = provider
                    return .success(track)
                }
                if firstTrack == nil {
                    firstTrack = (provider, track)
                }
            } catch let error as MediaError {
                lastError = error
                Log.media.error("\(provider.appName, privacy: .public) fetch failed: \(error.localizedDescription, privacy: .public)")
            } catch {
                lastError = .scriptExecutionFailed(error.localizedDescription)
            }
        }

        if let firstTrack {
            lastActiveProvider = firstTrack.provider
            return .success(firstTrack.track)
        }

        // Nothing playing anywhere is only an error if every player also failed.
        if let lastError, running.count == 1 {
            return .failure(lastError)
        }
        return .success(nil)
    }

    private func noRunningPlayerError() -> MediaError {
        guard let installed = providers.first(where: \.isInstalled) else {
            return .noPlayerInstalled
        }
        return .noPlayerRunning(installed.appName)
    }
}
