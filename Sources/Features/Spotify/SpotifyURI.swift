import Foundation

/// Spotify shares links, not URIs, so accept either and hand back a URI that
/// `play track` understands.
enum SpotifyURI {
    private static let kinds = ["playlist", "album", "track", "artist", "show", "episode"]

    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if trimmed.hasPrefix("spotify:") {
            return trimmed
        }

        // Links arrive as https://open.spotify.com/playlist/<id>?si=… and sometimes
        // carry a locale segment: /intl-de/playlist/<id>.
        let withScheme = trimmed.hasPrefix("http") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              url.host?.contains("spotify.com") == true else {
            return trimmed
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { kinds.contains($0) }),
              parts.count > index + 1 else {
            return nil
        }
        return "spotify:\(parts[index]):\(parts[index + 1])"
    }
}
