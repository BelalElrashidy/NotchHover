import AppKit

/// The playlists, albums and songs pinned to the notch's Playlists card, from any of
/// three places: a Spotify link, a playlist in your Music library, or an Apple Music
/// link. Saved as "Name|link" lines, as they always were.
enum PinnedPlaylists {
    static let defaultsKey = PlaylistsPaneView.defaultsKey

    struct Entry: Equatable {
        var name: String
        /// `spotify:…`, `applemusic:playlist:<persistent ID>`, or an
        /// https://music.apple.com link.
        var link: String

        var service: Service { Service(link: link) }
    }

    enum Service {
        case spotify, musicLibrary, appleMusicLink, unknown

        init(link: String) {
            if link.hasPrefix("spotify:") { self = .spotify }
            else if link.hasPrefix(PinnedPlaylists.libraryPrefix) { self = .musicLibrary }
            else if PinnedPlaylists.isAppleMusicLink(link) { self = .appleMusicLink }
            else { self = .unknown }
        }

        var title: String {
            switch self {
            case .spotify: return "Spotify"
            case .musicLibrary: return "Music library"
            case .appleMusicLink: return "Apple Music — opens in Music"
            case .unknown: return "Not a Spotify or Apple Music link"
            }
        }
    }

    static let libraryPrefix = "applemusic:playlist:"

    static var entries: [Entry] {
        get {
            (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []).compactMap { line in
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                return parts.count == 2 ? Entry(name: parts[0], link: parts[1]) : nil
            }
        }
        set {
            UserDefaults.standard.set(newValue.map { "\($0.name.replacingOccurrences(of: "|", with: "/"))|\($0.link)" }, forKey: defaultsKey)
        }
    }

    // MARK: - Links

    static func isAppleMusicLink(_ link: String) -> Bool {
        guard let host = URL(string: link)?.host else { return false }
        return host == "music.apple.com" || host.hasSuffix(".music.apple.com")
    }

    /// The link as it's kept: a Spotify URI for anything Spotify, the https link for
    /// Apple Music, nil for anything else.
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(libraryPrefix) { return trimmed }
        let withScheme = trimmed.contains("://") || trimmed.hasPrefix("spotify:") ? trimmed : "https://" + trimmed
        if isAppleMusicLink(withScheme) {
            // Sharing links carry tracking; the page is the same without it.
            var components = URLComponents(string: withScheme)
            components?.query = nil
            return components?.url?.absoluteString
        }
        guard let uri = SpotifyURI.normalize(trimmed), uri.hasPrefix("spotify:") else { return nil }
        return uri
    }

    /// A name for a shared link, from what the share said it was, or failing that the
    /// link itself — Apple Music's links carry the name, Spotify's only an id.
    static func name(for link: String, sharedTitle: String?) -> String {
        if var title = sharedTitle?.trimmingCharacters(in: .whitespacesAndNewlines), title.isEmpty == false, title != link {
            // "‎Chill Mix - Playlist - Apple Music", "Chill Mix - playlist by Spotify | Spotify"
            title = title.replacingOccurrences(of: "\u{200E}", with: "")
            for tail in [" | Spotify", " - Apple Music", " – Apple Music", " on Apple Music"] {
                if let range = title.range(of: tail, options: [.backwards, .caseInsensitive]) { title = String(title[..<range.lowerBound]) }
            }
            for kind in [" - playlist by ", " - Playlist", " - Album by ", " - Album", " - song and lyrics by ", " - Single by ", " - Song by "] {
                if let range = title.range(of: kind, options: .caseInsensitive) { title = String(title[..<range.lowerBound]) }
            }
            if title.isEmpty == false { return title }
        }
        if isAppleMusicLink(link), let url = URL(string: link) {
            let parts = url.pathComponents
            if let kind = parts.firstIndex(where: { ["playlist", "album", "song", "station"].contains($0) }), parts.count > kind + 2 {
                return parts[kind + 1].removingPercentEncoding?
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized ?? parts[kind + 1]
            }
        }
        if link.hasPrefix("spotify:") {
            let kind = link.split(separator: ":").dropFirst().first.map(String.init) ?? "playlist"
            return "Spotify \(kind)"
        }
        return "Playlist"
    }

    /// Adds a shared link, or renames it if it's already pinned. Nil when the link
    /// isn't one NotchHover can play.
    @discardableResult
    static func add(link raw: String, title: String?) -> Entry? {
        guard let link = normalize(raw) else { return nil }
        let entry = Entry(name: name(for: link, sharedTitle: title), link: link)
        var all = entries
        if let index = all.firstIndex(where: { $0.link == link }) {
            all[index].name = entry.name
        } else {
            all.append(entry)
        }
        entries = all
        return entry
    }

    // MARK: - Music library

    /// Your own playlists in Music, by name and persistent ID. Asks Music, so it opens
    /// Music if it isn't running — only call it when asked to.
    static func musicLibraryPlaylists() -> [Entry] {
        let source = """
        set sep to character id 9
        set output to ""
        tell application "Music"
            repeat with aPlaylist in (every user playlist whose special kind is none)
                try
                    set output to output & (persistent ID of aPlaylist) & sep & (name of aPlaylist) & linefeed
                end try
            end repeat
        end tell
        return output
        """
        let reply = (try? AppleScript.run(source).stringValue) ?? ""
        return reply.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2, parts[0].isEmpty == false else { return nil }
            return Entry(name: parts[1...].joined(separator: "\t"), link: libraryPrefix + parts[0])
        }
    }
}
