import Foundation

/// Lyrics parsing and timing, offline: --lyrics-selftest
/// Adding `live` also asks lrclib.net about one well-known song, through the same
/// request and parsing the app uses — the only part of the test that goes online.
enum LyricsSelfTest {
    static func run(live: Bool) {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }

        let lrc = """
        [ar: Somebody]
        [00:01.50] First line
        [00:05.00][00:20.00] Chorus
        [00:09.25]
        [00:12.00] Second verse
        """
        let lyrics = SyncedLyrics(lrc: lrc)
        expect("tags skipped, repeated stamps kept", lyrics.lines.count == 5)
        expect("nothing before the first line", lyrics.line(at: 0.5) == nil)
        expect("the line being sung", lyrics.line(at: 3) == "First line")
        expect("shown a moment early", lyrics.line(at: 4.8) == "Chorus")
        expect("a gap is an empty line", lyrics.line(at: 10) == "")
        expect("a repeated chorus comes back", lyrics.line(at: 25) == "Chorus")

        func track(_ bundle: String, duration: Double = 200, album: String = "Album") -> TrackInfo {
            TrackInfo(name: "Song", artist: "Artist", isPlaying: true, artworkURL: nil, sourceName: "", sourceBundleIdentifier: bundle,
                      position: 0, duration: duration, volume: nil, isShuffling: false, album: album)
        }
        expect("Spotify and Music are looked up", LyricsService.isLookupAllowed(for: track("com.spotify.client")) && LyricsService.isLookupAllowed(for: track("com.apple.Music")))
        expect("nothing else is", LyricsService.isLookupAllowed(for: track("com.apple.Safari")) == false)
        expect("a stream with no length isn't", LyricsService.isLookupAllowed(for: track("com.apple.Music", duration: 0)) == false)

        let query = LyricsService.request(for: track("com.spotify.client"))?.url?.query ?? ""
        expect("sends title, artist, album and length — nothing else",
               Set(query.split(separator: "&").map { String($0.split(separator: "=")[0]) }) == ["track_name", "artist_name", "album_name", "duration"])
        expect("no album: search instead", LyricsService.request(for: track("com.spotify.client", album: ""))?.url?.path == "/api/search")

        let found = Data(#"{"syncedLyrics":"[00:01.00] Hello","plainLyrics":"Hello"}"#.utf8)
        let search = Data(#"[{"duration":150,"syncedLyrics":"[00:01.00] Wrong"},{"duration":201,"syncedLyrics":"[00:01.00] Right"}]"#.utf8)
        expect("found", LyricsService.parse(found, status: 200, duration: 200, isSearch: false)??.line(at: 2) == "Hello")
        expect("not found is an answer to keep", { if case .some(.none) = LyricsService.parse(nil, status: 404, duration: 200, isSearch: false) { return true }; return false }())
        expect("instrumental is too", { if case .some(.none) = LyricsService.parse(Data(#"{"instrumental":true,"syncedLyrics":null}"#.utf8), status: 200, duration: 200, isSearch: false) { return true }; return false }())
        expect("a busy server is asked again later", LyricsService.parse(nil, status: 503, duration: 200, isSearch: false) == nil)
        expect("search picks the one whose length matches", LyricsService.parse(search, status: 200, duration: 200, isSearch: true)??.line(at: 2) == "Right")

        if live {
            let song = TrackInfo(name: "Bohemian Rhapsody", artist: "Queen", isPlaying: true, artworkURL: nil, sourceName: "Spotify",
                                 sourceBundleIdentifier: "com.spotify.client", position: 0, duration: 354, volume: nil, isShuffling: false,
                                 album: "A Night at the Opera")
            let done = DispatchSemaphore(value: 0)
            var answer: SyncedLyrics??
            URLSession(configuration: .ephemeral).dataTask(with: LyricsService.request(for: song)!) { data, response, _ in
                answer = LyricsService.parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0, duration: 354, isSearch: false)
                done.signal()
            }.resume()
            done.wait()
            let line = answer??.line(at: 10)
            expect("live: lrclib.net answers with synced lines (\(line ?? "nothing"))", line?.isEmpty == false)
        }

        let failed = results.filter { $0.hasPrefix("✗") }.count
        FileHandle.standardError.write(Data(("lyrics: " + results.joined(separator: "  ") + "\n").utf8))
        exit(failed == 0 ? 0 : 1)
    }
}
