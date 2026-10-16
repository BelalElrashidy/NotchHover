import AppKit
import Compression

/// The page a browser is playing: what the tab is called, where it is, and the
/// favicon the browser already has on disk.
struct BrowserPage: Equatable {
    let title: String
    let host: String
    /// PNG or ICO bytes lifted straight out of the browser's own session file, so
    /// showing a site's icon never means fetching anything.
    let iconData: Data?

    var icon: NSImage? {
        iconData.flatMap(NSImage.init(data:))
    }

    /// "www.youtube.com" reads better as "youtube.com" and fits a narrow panel.
    var shortHost: String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Works out which page a browser is playing.
///
/// Firefox-family browsers are read from the session file they already keep on disk.
/// Nothing there needs a permission — the file lives in Application Support, which is
/// not TCC-protected — and the favicon arrives inside it as a `data:` URI. It is written
/// every few seconds, which is close enough for something playing.
///
/// Safari is asked over AppleScript, which means a one-time Automation prompt. It
/// gives back titles and addresses but no icons: Safari's favicon cache sits behind
/// Full Disk Access, so a Safari page shows Safari's own icon.
///
/// Chrome would need AppleScript for the tab plus its own favicon database, and is not
/// handled yet.
final class BrowserPageReader {
    static let shared = BrowserPageReader()

    /// Browsers that keep a Firefox-style profile, and the folder they keep it in.
    private static let profileFolders: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
        "org.mozilla.nightly": "Firefox",
        "app.zen-browser.zen": "zen",
        "io.gitlab.librewolf": "LibreWolf",
        "net.waterfox.waterfox": "Waterfox",
        "one.ablaze.floorp": "Floorp"
    ]

    /// Sites worth believing over whichever tab happens to have been touched last: if
    /// one of these is open, it is almost certainly what you are hearing, even though
    /// you have since clicked away to something else.
    private static let mediaHosts = [
        "youtube.com", "youtu.be", "soundcloud.com", "spotify.com", "netflix.com",
        "twitch.tv", "vimeo.com", "music.apple.com", "deezer.com", "bandcamp.com",
        "mixcloud.com", "primevideo.com", "disneyplus.com", "hulu.com", "max.com",
        "crunchyroll.com", "tidal.com", "audible.com", "pocketcasts.com", "dailymotion.com"
    ]

    /// A tab nobody has touched in half an hour is not what just started playing.
    private static let staleAfter: TimeInterval = 30 * 60

    private static let safariIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview"
    ]

    /// Safari is asked rather than read, so it is asked no more often than this.
    private static let safariInterval: TimeInterval = 4

    static func handles(_ bundleIdentifier: String) -> Bool {
        profileFolders[bundleIdentifier] != nil || safariIdentifiers.contains(bundleIdentifier)
    }

    private let queue = DispatchQueue(label: "com.notchhover.browserpage", qos: .utility)
    /// Guards the cache on its own, rather than the work queue doing it: reading the
    /// last answer from the main thread must never wait behind a parse in flight.
    private let lock = NSLock()
    private var cache: [String: (modified: Date, page: BrowserPage?)] = [:]

    /// What was read last time, if anything. Cheap, and safe on the main thread.
    func cachedPage(for bundleIdentifier: String) -> BrowserPage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[bundleIdentifier]?.page
    }

    /// Re-reads the session file if it has changed since last time, off the main
    /// thread — it is a few megabytes of JSON — and reports back only when the answer
    /// is different from what the caller was already showing.
    func refresh(for bundleIdentifier: String, current: BrowserPage?, completion: @escaping (BrowserPage?) -> Void) {
        guard Self.handles(bundleIdentifier) else { return }

        queue.async { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let cached = self.cache[bundleIdentifier]
            self.lock.unlock()

            let page: BrowserPage?
            if Self.safariIdentifiers.contains(bundleIdentifier) {
                // No file to watch, so the cache is kept by age instead.
                if let cached, Date().timeIntervalSince(cached.modified) < Self.safariInterval {
                    page = cached.page
                } else {
                    page = Self.safariPage(bundleIdentifier: bundleIdentifier)
                    self.store(page, modified: Date(), for: bundleIdentifier)
                }
            } else {
                guard let url = Self.sessionFile(for: bundleIdentifier) else { return }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if let cached, cached.modified == modified {
                    // The browser has not written since the last read, so neither has the
                    // answer changed. This is the usual case: it saves every few seconds.
                    page = cached.page
                } else {
                    page = Self.playingPage(in: url)
                    self.store(page, modified: modified, for: bundleIdentifier)
                }
            }

            guard page != current else { return }
            DispatchQueue.main.async { completion(page) }
        }
    }

    private func store(_ page: BrowserPage?, modified: Date, for bundleIdentifier: String) {
        lock.lock()
        cache[bundleIdentifier] = (modified, page)
        lock.unlock()
    }

    // MARK: - Safari

    /// Every tab's address and title, and which tab is in front. Missing values — an
    /// empty tab, a window still loading — are skipped rather than failing the lot.
    private static func safariScript(_ bundleIdentifier: String) -> String {
        """
        if application id "\(bundleIdentifier)" is not running then return ""
        tell application id "\(bundleIdentifier)"
            set frontAddress to ""
            try
                set frontAddress to URL of current tab of front window
            end try
            set output to frontAddress & linefeed
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    try
                        set output to output & (URL of aTab) & tab & (name of aTab) & linefeed
                    end try
                end repeat
            end repeat
            return output
        end tell
        """
    }

    /// Safari keeps no record of when a tab was last looked at, so a media site wins,
    /// the one in front first; failing that, whatever is in front.
    private static func safariPage(bundleIdentifier: String) -> BrowserPage? {
        guard let script = NSAppleScript(source: safariScript(bundleIdentifier)) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // Automation declined, most likely: the browser's own icon will do.
            Log.system.notice("Safari tabs unavailable: \(error[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public)")
            return nil
        }

        let lines = (result.stringValue ?? "").components(separatedBy: "\n")
        guard let frontAddress = lines.first else { return nil }

        let tabs: [BrowserPage] = lines.dropFirst().compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2,
                  let host = URL(string: parts[0])?.host, host.isEmpty == false else { return nil }
            let title = parts.dropFirst().joined(separator: "\t")
            return BrowserPage(title: title.isEmpty ? host : title, host: host, iconData: nil)
        }

        let frontHost = URL(string: frontAddress)?.host
        let media = tabs.filter { isMediaHost($0.host) }
        let page = media.first { $0.host == frontHost } ?? media.first ?? tabs.first { $0.host == frontHost }
        // Hosts and counts only — enough to see why a page was or wasn't chosen.
        Log.system.notice("Safari: \(tabs.count, privacy: .public) tab(s), \(media.count, privacy: .public) on media sites, front \(frontHost ?? "none", privacy: .public) → \(page?.host ?? "no page", privacy: .public)")
        return page
    }

    /// The newest session file among that browser's profiles — people have more than
    /// one, and only one of them is the window you are looking at.
    private static func sessionFile(for bundleIdentifier: String) -> URL? {
        guard let folder = profileFolders[bundleIdentifier] else { return nil }
        let profiles = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(folder)
            .appendingPathComponent("Profiles")
        guard let profiles,
              let contents = try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil) else {
            return nil
        }

        return contents
            .map { $0.appendingPathComponent("sessionstore-backups/recovery.jsonlz4") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }
    }

    private static func playingPage(in url: URL) -> BrowserPage? {
        guard let json = readSessionStore(at: url),
              let windows = json["windows"] as? [[String: Any]] else { return nil }

        let tabs = windows.flatMap { $0["tabs"] as? [[String: Any]] ?? [] }
        let candidates = tabs.compactMap(tab(from:))

        // A media site wins outright; otherwise the tab touched most recently, as long
        // as that was recent enough to plausibly be what started the sound.
        if let media = candidates
            .filter({ isMediaHost($0.page.host) })
            .max(by: { $0.lastAccessed < $1.lastAccessed }) {
            return media.page
        }

        guard let latest = candidates.max(by: { $0.lastAccessed < $1.lastAccessed }),
              Date().timeIntervalSince(latest.lastAccessed) < staleAfter else { return nil }
        return latest.page
    }

    private static func tab(from tab: [String: Any]) -> (page: BrowserPage, lastAccessed: Date)? {
        let entries = tab["entries"] as? [[String: Any]] ?? []
        guard entries.isEmpty == false else { return nil }

        // `index` is 1-based and points at where the tab sits in its own history.
        let index = min(max(0, (tab["index"] as? Int ?? entries.count) - 1), entries.count - 1)
        let entry = entries[index]

        guard let address = entry["url"] as? String,
              let host = URL(string: address)?.host,
              host.isEmpty == false else { return nil }

        let title = (entry["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? host
        let milliseconds = tab["lastAccessed"] as? Double ?? 0

        return (
            BrowserPage(title: title, host: host, iconData: iconData(from: tab["image"] as? String)),
            Date(timeIntervalSince1970: milliseconds / 1000)
        )
    }

    /// The session file stores a tab's favicon as a `data:` URI most of the time. When
    /// it is a plain URL instead, there is nothing local to show and the caller falls
    /// back to the browser's own icon rather than going and fetching it.
    private static func iconData(from image: String?) -> Data? {
        guard let image, image.hasPrefix("data:"), let comma = image.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(image[image.index(after: comma)...]))
    }

    private static func isMediaHost(_ host: String) -> Bool {
        mediaHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// Mozilla's own container format: the magic, the decompressed size, then a raw
    /// LZ4 block — which the system's Compression framework decodes directly.
    private static func readSessionStore(at url: URL) -> [String: Any]? {
        guard let raw = try? Data(contentsOf: url), raw.count > 12,
              raw.prefix(8) == Data("mozLz40\0".utf8) else { return nil }

        let expected = Int(raw.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        // A corrupt header should not turn into an enormous allocation.
        guard expected > 0, expected < 64 * 1024 * 1024 else { return nil }

        let body = raw.subdata(in: 12..<raw.count)
        var decoded = Data(count: expected)
        let written: Int = decoded.withUnsafeMutableBytes { destination in
            body.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, expected,
                    source.bindMemory(to: UInt8.self).baseAddress!, body.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        guard written > 0 else { return nil }

        return (try? JSONSerialization.jsonObject(with: decoded.prefix(written))) as? [String: Any]
    }
}
