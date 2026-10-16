import CryptoKit
import Foundation

/// A song's lyrics with a time for each line, as LRC files give them.
struct SyncedLyrics: Equatable {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    let lines: [Line]

    /// Parses LRC: `[mm:ss.xx] words`, sometimes several stamps on one line for a
    /// repeated chorus. Tags like `[ar: …]` have no time and are skipped.
    init(lrc: String) {
        var lines: [Line] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { break }
                times.append(minutes * 60 + seconds)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Line(time: $0, text: text) }
        }
        self.lines = lines.sorted { $0.time < $1.time }
    }

    /// The line being sung at `position`; nil before the first one. A gap between
    /// verses comes back as an empty string.
    func line(at position: Double) -> String? {
        // Show a line a moment early: the poller is never quite on time, and reading
        // starts before the singing does.
        let target = position + 0.3
        guard let index = lines.lastIndex(where: { $0.time <= target }) else { return nil }
        return lines[index].text
    }
}

/// Synced lyrics, for anyone who turns them on. They are the one thing in NotchHover
/// that uses the internet, so they are off until switched on in Settings, and then:
///
/// - only the track's title, artist, album and length are sent, to lrclib.net — a free,
///   open lyrics database — with no account, cookie or identifier;
/// - each song is asked about once: the answer, lyrics or "none", is kept on disk;
/// - only Spotify and Music tracks are looked up, never what a browser is playing.
///
/// The current line is worked out between poller ticks from where the track was at the
/// last tick, so it moves with the song rather than every two seconds.
final class LyricsService {
    static let shared = LyricsService()

    static let defaultsKey = "SyncedLyrics"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            shared.enabledDidChange()
        }
    }

    /// The line to show now, or nil when there is nothing to show.
    private(set) var currentLine: String?

    private var observers: [UUID: (String?) -> Void] = [:]
    private var track: TrackInfo?
    private var songKey: String?
    private var lyrics: SyncedLyrics?
    /// Where the track was, and when that was true.
    private var anchor = (position: 0.0, date: Date(), isPlaying: false)
    private var timer: Timer?
    /// Songs the server couldn't answer for this time round — tried again next launch,
    /// not every tick.
    private var failed = Set<String>()
    private var inFlight: String?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        return URLSession(configuration: configuration)
    }()

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "NotchHover/\(version) (https://github.com/BelalElrashidy/NotchHover)"
    }

    @discardableResult
    func addObserver(_ handler: @escaping (String?) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    /// Called with every poller reading.
    func update(_ track: TrackInfo?) {
        self.track = track
        guard Self.isEnabled, let track, Self.isLookupAllowed(for: track) else {
            reset()
            return
        }

        anchor = (track.position, Date(), track.isPlaying)
        let key = Self.key(for: track)
        if key != songKey {
            songKey = key
            lyrics = nil
            load(track, key: key)
        }
        tick()
        updateTimer()
    }

    private func enabledDidChange() {
        update(track)
    }

    private func reset() {
        songKey = nil
        lyrics = nil
        timer?.invalidate()
        timer = nil
        setLine(nil)
    }

    private func updateTimer() {
        let needsTimer = lyrics != nil && anchor.isPlaying
        if needsTimer, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        } else if needsTimer == false {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        guard let lyrics else {
            setLine(nil)
            return
        }
        let elapsed = anchor.isPlaying ? Date().timeIntervalSince(anchor.date) : 0
        // A gap between verses shows a note rather than dropping back to the artist,
        // which would make the line flicker between two kinds of thing.
        setLine(lyrics.line(at: anchor.position + elapsed).map { $0.isEmpty ? "♪" : $0 })
    }

    private func setLine(_ line: String?) {
        guard line != currentLine else { return }
        currentLine = line
        observers.values.forEach { $0(line) }
    }

    /// Preview hook: a line as if the song had reached it.
    func showLineForPreview(_ line: String?) {
        setLine(line)
    }

    // MARK: - Finding them

    /// Spotify and Music, with a length — a radio stream has none and no lyrics either.
    static func isLookupAllowed(for track: TrackInfo) -> Bool {
        ["com.spotify.client", "com.apple.Music"].contains(track.sourceBundleIdentifier)
            && track.duration > 0
            && track.name.isEmpty == false
    }

    private static func key(for track: TrackInfo) -> String {
        [track.name, track.artist, track.album, String(Int(track.duration.rounded()))]
            .joined(separator: "\u{1F}")
    }

    private func load(_ track: TrackInfo, key: String) {
        if case .some(let cached) = Self.readCache(key) {
            lyrics = cached
            return
        }
        guard failed.contains(key) == false, inFlight != key, let request = Self.request(for: track) else { return }
        inFlight = key

        session.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let found = Self.parse(data, status: status, duration: track.duration, isSearch: track.album.isEmpty)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = nil
                switch found {
                case .some(let result):
                    Self.writeCache(key, lyrics: result)
                    Log.media.notice("Lyrics: \(result == nil ? "none" : "\(result!.lines.count) lines", privacy: .public) from lrclib.net")
                    guard key == self.songKey else { return }
                    self.lyrics = result
                    self.tick()
                    self.updateTimer()
                case .none:
                    // Busy, offline or broken: not an answer about the song, so not kept.
                    self.failed.insert(key)
                    Log.media.notice("Lyrics: lookup failed (\(status), \(error?.localizedDescription ?? "no error", privacy: .public))")
                }
            }
        }.resume()
    }

    /// `/api/get` wants all four fields; without an album, search and pick the result
    /// whose length matches.
    static func request(for track: TrackInfo) -> URLRequest? {
        var components = URLComponents(string: "https://lrclib.net")!
        if track.album.isEmpty {
            components.path = "/api/search"
            components.queryItems = [
                URLQueryItem(name: "track_name", value: track.name),
                URLQueryItem(name: "artist_name", value: track.artist)
            ]
        } else {
            components.path = "/api/get"
            components.queryItems = [
                URLQueryItem(name: "track_name", value: track.name),
                URLQueryItem(name: "artist_name", value: track.artist),
                URLQueryItem(name: "album_name", value: track.album),
                URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
            ]
        }
        return components.url.map { URLRequest(url: $0) }
    }

    /// `.some(lyrics)` is an answer worth keeping — `.some(nil)` meaning the song has
    /// none, or is instrumental. `.none` means ask again another time.
    static func parse(_ data: Data?, status: Int, duration: Double, isSearch: Bool) -> SyncedLyrics?? {
        if status == 404 { return .some(nil) }
        guard status == 200, let data, let json = try? JSONSerialization.jsonObject(with: data) else { return .none }

        let record: [String: Any]?
        if isSearch {
            record = (json as? [[String: Any]])?.first { entry in
                guard let length = entry["duration"] as? Double, entry["syncedLyrics"] is String else { return false }
                return abs(length - duration) <= 2
            }
        } else {
            record = json as? [String: Any]
        }
        guard let lrc = record?["syncedLyrics"] as? String else { return .some(nil) }
        let lyrics = SyncedLyrics(lrc: lrc)
        return .some(lyrics.lines.isEmpty ? nil : lyrics)
    }

    // MARK: - Cache

    static var cacheFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchHover/Lyrics", isDirectory: true)
    }

    private static func cacheFile(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheFolder.appendingPathComponent(digest + ".lrc")
    }

    /// An empty file means "this song has none".
    private static func readCache(_ key: String) -> SyncedLyrics?? {
        guard let text = try? String(contentsOf: cacheFile(key), encoding: .utf8) else { return .none }
        let lyrics = SyncedLyrics(lrc: text)
        return .some(lyrics.lines.isEmpty ? nil : lyrics)
    }

    private static func writeCache(_ key: String, lyrics: SyncedLyrics?) {
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        let text = lyrics?.lines.map { line in
            String(format: "[%02d:%05.2f] %@", Int(line.time) / 60, line.time.truncatingRemainder(dividingBy: 60), line.text)
        }.joined(separator: "\n") ?? ""
        try? text.write(to: cacheFile(key), atomically: true, encoding: .utf8)
    }

    /// Forgets every cached answer.
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheFolder)
    }
}
