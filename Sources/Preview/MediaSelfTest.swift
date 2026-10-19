import AppKit

/// --media-selftest [dir]: every installed player's and browser's scripts compile,
/// tab titles clean up, and what each running one reports right now. Reads only —
/// nothing is played, paused or skipped. With a directory, the page scripts are written
/// there too, to try in a browser by hand.
enum MediaSelfTest {
    static func run(writeScriptsTo directory: String?) -> Never {
        var lines: [String] = []
        var failed = false

        if let directory {
            let folder = URL(fileURLWithPath: directory)
            try? BrowserMediaProvider.readScript.write(to: folder.appendingPathComponent("read.js"), atomically: true, encoding: .utf8)
            for command in ["toggle", "next", "previous", "seek:30", "volume:50"] {
                try? BrowserMediaProvider.controlScript(command)
                    .write(to: folder.appendingPathComponent("control-\(command.replacingOccurrences(of: ":", with: "-")).js"), atomically: true, encoding: .utf8)
            }
            lines.append("page scripts written to \(directory)")
        }

        let titles: [(String, String, String)] = [
            ("(3) Lo-fi beats to study to - YouTube", "youtube.com", "Lo-fi beats to study to"),
            ("Song Name · Artist | SoundCloud", "soundcloud.com", "Song Name · Artist"),
            ("Just a page", "example.com", "Just a page")
        ]
        for (raw, host, expected) in titles {
            let cleaned = BrowserMediaProvider.cleanTitle(raw, host: host)
            let ok = cleaned == expected
            failed = failed || ok == false
            lines.append("title \(ok ? "ok" : "WRONG"): \"\(raw)\" → \"\(cleaned)\"")
        }

        for provider in MediaHub.defaultProviders where provider.isInstalled {
            let scripts: [String]
            switch provider {
            case let provider as AppleScriptMediaProvider: scripts = provider.selfTestScripts
            case let provider as BrowserMediaProvider: scripts = provider.selfTestScripts
            case let provider as VLCProvider: scripts = provider.selfTestScripts
            case let provider as QuickTimeProvider: scripts = provider.selfTestScripts
            default: scripts = []
            }
            let broken = scripts.enumerated().compactMap { index, source -> String? in
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else { return "script \(index): no source" }
                return script.compileAndReturnError(&error) ? nil : "script \(index): \(error?[NSAppleScript.errorMessage] ?? "?")"
            }
            failed = failed || broken.isEmpty == false
            lines.append("\(provider.appName): \(scripts.count) script(s) \(broken.isEmpty ? "compile" : "DO NOT compile — " + broken.joined(separator: "; "))")

            guard provider.isRunning else { continue }
            do {
                if let track = try provider.fetchTrack() {
                    lines.append("  now: \"\(track.name)\" by \"\(track.artist)\" on \(track.sourceName), \(track.isPlaying ? "playing" : "paused") \(Int(track.position))/\(Int(track.duration))s, artwork \(track.artworkURL?.scheme ?? "none")")
                } else {
                    lines.append("  now: nothing")
                }
            } catch {
                lines.append("  now: error \(error.localizedDescription)")
            }
            if let browser = provider as? BrowserMediaProvider {
                lines.append("  JavaScript from Apple Events: \(browser.access)")
            }
        }

        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        exit(failed ? 1 : 0)
    }
}
