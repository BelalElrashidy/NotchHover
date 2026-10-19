import AppKit

/// What's playing in a browser tab, read by a few lines of JavaScript the browser runs
/// for us over AppleScript: the page's own Now Playing details (`navigator.mediaSession`,
/// which YouTube, Spotify, SoundCloud and most players fill in), else the video or audio
/// element and the tab's title. Play, pause, seek and volume go to that element; next and
/// previous press the site's own buttons where we know them.
///
/// Nothing leaves the Mac: the script runs in the tab and only answers us. The browser
/// has to allow it once — Safari and Chrome both call it "Allow JavaScript from Apple
/// Events" — and until it does, the tab's title is all NotchHover shows.
final class BrowserMediaProvider: MediaProvider {
    enum Family {
        /// `do JavaScript … in tab`, tabs by position.
        case safari
        /// `execute tab javascript …`, tabs by id: Chrome, Arc, Brave, Edge, Vivaldi.
        case chromium
    }

    /// Whether the browser runs our JavaScript, as last found.
    enum Access: Equatable {
        case unknown, allowed, blocked
    }

    let appName: String
    let bundleIdentifier: String
    let family: Family

    init(appName: String, bundleIdentifier: String, family: Family) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.family = family
    }

    static let all: [BrowserMediaProvider] = [
        BrowserMediaProvider(appName: "Safari", bundleIdentifier: "com.apple.Safari", family: .safari),
        BrowserMediaProvider(appName: "Safari Technology Preview", bundleIdentifier: "com.apple.SafariTechnologyPreview", family: .safari),
        BrowserMediaProvider(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", family: .chromium),
        BrowserMediaProvider(appName: "Arc", bundleIdentifier: "company.thebrowser.Browser", family: .chromium),
        BrowserMediaProvider(appName: "Brave", bundleIdentifier: "com.brave.Browser", family: .chromium),
        BrowserMediaProvider(appName: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac", family: .chromium),
        BrowserMediaProvider(appName: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi", family: .chromium),
        BrowserMediaProvider(appName: "Chromium", bundleIdentifier: "org.chromium.Chromium", family: .chromium)
    ]

    static func provider(for bundleIdentifier: String) -> BrowserMediaProvider? {
        all.first { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Where the setting lives, in the browser's own words.
    var allowInstructions: String {
        switch family {
        case .safari:
            return "In Safari, turn on Settings › Advanced › Show features for web developers, then Develop › Allow JavaScript from Apple Events."
        case .chromium where bundleIdentifier == "company.thebrowser.Browser":
            // Arc has the switch in some versions and not others, and it isn't documented.
            return "If Arc's menus have Allow JavaScript from Apple Events, turn it on. Some versions of Arc don't offer it."
        case .chromium where bundleIdentifier == "com.vivaldi.Vivaldi":
            return "In Vivaldi, turn on Allow JavaScript from Apple Events in the Tools menu."
        case .chromium:
            return "In \(appName), choose View › Developer › Allow JavaScript from Apple Events."
        }
    }

    // MARK: - State (media queue only, except `access`)

    private let lock = NSLock()
    private var _access: Access = .unknown
    /// Read from Settings on the main thread.
    var access: Access {
        lock.lock(); defer { lock.unlock() }
        return _access
    }

    private func setAccess(_ access: Access) {
        lock.lock()
        let changed = _access != access
        _access = access
        lock.unlock()
        if changed {
            Log.media.notice("\(self.appName, privacy: .public) JavaScript: \(String(describing: access), privacy: .public)")
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.accessDidChange, object: self) }
        }
    }

    static let accessDidChange = Notification.Name("NotchHoverBrowserAccessDidChange")

    /// The tab last found playing, and the address it was on.
    private struct TabReference: Equatable {
        let window: String
        let tab: String
        let address: String
    }

    private var playingTab: TabReference?
    /// When the remembered tab last played. A video left paused stops being "what's
    /// playing" after a while, as a paused player does when it's closed.
    private var lastHeard = Date.distantPast
    private var lastScan = Date.distantPast
    private var lastRefusal = Date.distantPast

    private static let pausedFor: TimeInterval = 10 * 60
    private static let scanInterval: TimeInterval = 3
    private static let emptyScanBackoff: TimeInterval = 12
    /// A refused browser is asked again after this long, in case it was switched on.
    private static let refusalInterval: TimeInterval = 20

    // MARK: - MediaProvider

    func fetchTrack() throws -> TrackInfo? {
        let isMakingSound = AudioSourceProbe.outputProcessObjects(of: bundleIdentifier).isEmpty == false

        if access == .blocked {
            guard isMakingSound, Date().timeIntervalSince(lastRefusal) > Self.refusalInterval else { return nil }
        }

        // The tab we know about first: one script, one tab.
        if let reference = playingTab {
            if let state = read(reference) {
                if state.isPlaying { lastHeard = Date() }
                if state.isPlaying || Date().timeIntervalSince(lastHeard) < Self.pausedFor {
                    // Something else in the same browser may have started instead.
                    if state.isPlaying || isMakingSound == false {
                        return track(from: state)
                    }
                } else {
                    playingTab = nil
                }
            } else {
                playingTab = nil
            }
        }

        // Then, only while the browser is actually making sound, every tab.
        guard isMakingSound, Date().timeIntervalSince(lastScan) > Self.scanInterval else {
            return nil
        }
        lastScan = Date()
        guard let (reference, state) = try scan() else {
            // Sound with no tab to show for it — an embedded player in another site's
            // frame, say. Looking again every few seconds would only cost the poll.
            lastScan = Date().addingTimeInterval(Self.emptyScanBackoff)
            return nil
        }
        playingTab = reference
        lastHeard = Date()
        return track(from: state)
    }

    func control(_ action: MediaAction) throws {
        guard let reference = playingTab else { return }
        let command: String
        switch action {
        case .playPause: command = "toggle"
        case .nextTrack: command = "next"
        case .previousTrack: command = "previous"
        case .seek(let seconds): command = "seek:\(max(0, seconds))"
        case .setVolume(let percent): command = "volume:\(max(0, min(100, percent)))"
        case .toggleShuffle, .play: return
        }
        _ = try? run(Self.controlScript(command), in: reference)
    }

    // MARK: - Reading

    /// What the page script answers with.
    private struct PageState: Decodable {
        let p: Bool          // playing
        let t: String        // title
        let a: String        // artist
        let al: String       // album
        let art: String      // artwork address
        let pos: Double
        let dur: Double
        let v: Int           // volume, or -1
        let d: String        // the document's title
        let h: String        // host

        var isPlaying: Bool { p }
    }

    private func track(from state: PageState) -> TrackInfo {
        let host = state.h.hasPrefix("www.") ? String(state.h.dropFirst(4)) : state.h
        let title = state.t.isEmpty ? Self.cleanTitle(state.d, host: host) : state.t
        let artwork = URL(string: state.art).flatMap { ["https", "http", "data"].contains($0.scheme ?? "") ? $0 : nil }
        return TrackInfo(
            name: title.isEmpty ? host : title,
            artist: state.a,
            isPlaying: state.p,
            artworkURL: artwork,
            sourceName: host.isEmpty ? appName : host,
            sourceBundleIdentifier: bundleIdentifier,
            position: state.pos,
            duration: state.dur,
            volume: state.v >= 0 ? state.v : nil,
            isShuffling: false,
            album: state.al,
            supportsShuffle: false
        )
    }

    /// "(3) Some video - YouTube" reads as "Some video".
    static func cleanTitle(_ title: String, host: String) -> String {
        var title = title.trimmingCharacters(in: .whitespaces)
        if let match = title.range(of: #"^\(\d+\+?\)\s*"#, options: .regularExpression) {
            title.removeSubrange(match)
        }
        let site = host.components(separatedBy: ".").dropLast().last ?? host
        for separator in [" - ", " – ", " | ", " · "] {
            if let range = title.range(of: separator, options: .backwards),
               title[range.upperBound...].lowercased().replacingOccurrences(of: " ", with: "").contains(site.lowercased()) {
                title = String(title[..<range.lowerBound])
                break
            }
        }
        return title
    }

    private func decode(_ reply: String?) -> PageState? {
        guard let reply, reply.isEmpty == false, let data = reply.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PageState.self, from: data)
    }

    /// The remembered tab, if it is still there, on the same page, with media in it.
    private func read(_ reference: TabReference) -> PageState? {
        guard let reply = try? run(Self.readScript, in: reference) else { return nil }
        return decode(reply)
    }

    /// Runs page script in one tab, checking first that the tab is still on the page
    /// we remembered — Safari's tabs are known only by position, which moves.
    private func run(_ javascript: String, in reference: TabReference) throws -> String? {
        try AppleScript.run(tabScript(javascript, in: reference)).stringValue
    }

    /// `timeout` is short on purpose: a tab the browser has put to sleep doesn't refuse
    /// a script, it waits — Arc's did, for as long as it was given.
    private func tabScript(_ javascript: String, in reference: TabReference, timeout: Int = 2) -> String {
        let tabSpecifier: String
        let runCommand: String
        switch family {
        case .safari:
            tabSpecifier = "tab \(reference.tab) of window id \(reference.window)"
            runCommand = "do JavaScript \(AppleScript.quoted(javascript)) in theTab"
        case .chromium:
            tabSpecifier = "tab id \(Self.literal(reference.tab)) of window id \(Self.literal(reference.window))"
            runCommand = "execute theTab javascript \(AppleScript.quoted(javascript))"
        }
        return """
        if application id "\(bundleIdentifier)" is not running then return ""
        with timeout of \(timeout) seconds
            tell application id "\(bundleIdentifier)"
                set theTab to \(tabSpecifier)
                if (URL of theTab) is not \(AppleScript.quoted(reference.address)) then return ""
                set reply to \(runCommand)
                if reply is missing value then return ""
                return reply
            end tell
        end timeout
        """
    }

    /// Every tab's place and address, and whether it's the one in front of its window.
    /// No page script, so it's quick and never waits on a sleeping tab. Arc can have no
    /// tab in front at all, so that's asked inside a `try`.
    private var listScript: String {
        let isSafari = family == .safari
        let frontTab = isSafari ? "current tab" : "active tab"
        let tabKey = isSafari ? "tabIndex" : "(id of aTab)"
        // `tab` inside a browser's tell block is its tab class, not the character.
        return """
        if application id "\(bundleIdentifier)" is not running then return ""
        set sep to character id 9
        set output to ""
        with timeout of 4 seconds
            tell application id "\(bundleIdentifier)"
                repeat with aWindow in windows
                    set windowID to id of aWindow
                    set frontAddress to ""
                    try
                        set frontAddress to URL of \(frontTab) of aWindow
                    end try
                    set tabIndex to 0
                    repeat with aTab in tabs of aWindow
                        set tabIndex to tabIndex + 1
                        try
                            set tabAddress to URL of aTab
                            set output to output & windowID & sep & \(tabKey) & sep & ((tabAddress is frontAddress) as text) & sep & tabAddress & linefeed
                        end try
                    end repeat
                end repeat
            end tell
        end timeout
        return output
        """
    }

    /// Tabs that didn't answer — asleep — skipped for a while rather than waited on again.
    private var unresponsive: [String: Date] = [:]
    private static let maxProbes = 12
    private static let scanBudget: TimeInterval = 4

    /// Finds the tab making the sound: media sites first, then each window's front tab,
    /// then — in browsers that don't leave tabs asleep — the rest. Stops at the first one
    /// playing; failing that, the first with something paused part way.
    private func scan() throws -> (TabReference, PageState)? {
        let listing: String
        do {
            listing = try AppleScript.runReportingFailure(listScript).stringValue ?? ""
        } catch let failure as AppleScript.Failure {
            // -1743: Automation refused. Nothing to read, and nothing to say twice.
            Log.media.error("\(self.appName, privacy: .public) tabs: \(failure.number, privacy: .public) \(failure.message, privacy: .public)")
            return nil
        }

        struct Candidate {
            let reference: TabReference
            let isFront: Bool
            let isMedia: Bool
            var key: String { reference.window + "/" + reference.tab }
        }
        let candidates: [Candidate] = listing.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { return nil }
            let address = parts[3...].joined(separator: "\t")
            let host = URL(string: address)?.host ?? ""
            return Candidate(reference: TabReference(window: parts[0], tab: parts[1], address: address),
                             isFront: parts[2] == "true", isMedia: BrowserPageReader.isMediaHost(host))
        }

        let now = Date()
        unresponsive = unresponsive.filter { now.timeIntervalSince($0.value) < 5 * 60 }
        let media = candidates.filter(\.isMedia)
        let front = candidates.filter { $0.isFront && $0.isMedia == false }
        // Arc keeps background tabs asleep, and a sleeping tab only times out.
        let rest = bundleIdentifier == "company.thebrowser.Browser" ? [] : candidates.filter { $0.isFront == false && $0.isMedia == false }
        let ordered = (media + front + rest).filter { unresponsive[$0.key] == nil }.prefix(Self.maxProbes)

        var paused: (TabReference, PageState)?
        var probed = 0
        for candidate in ordered {
            guard Date().timeIntervalSince(now) < Self.scanBudget else { break }
            probed += 1
            do {
                let reply = try AppleScript.runReportingFailure(tabScript(Self.readScript, in: candidate.reference, timeout: 1)).stringValue
                setAccess(.allowed)
                guard let state = decode(reply) else { continue }
                if state.isPlaying {
                    Log.media.notice("\(self.appName, privacy: .public): playing tab found after \(probed, privacy: .public) of \(candidates.count, privacy: .public)")
                    return (candidate.reference, state)
                }
                if paused == nil { paused = (candidate.reference, state) }
            } catch let failure as AppleScript.Failure {
                if failure.message.localizedCaseInsensitiveContains("JavaScript") {
                    lastRefusal = Date()
                    setAccess(.blocked)
                    return nil
                }
                if failure.number == -1712 { unresponsive[candidate.key] = Date() }
                if failure.number == -1743 { return nil }
            }
        }
        Log.media.notice("\(self.appName, privacy: .public): \(probed, privacy: .public) of \(candidates.count, privacy: .public) tab(s) asked, none playing")
        return paused
    }

    /// A scan whether or not anything is playing, timed — for --media-selftest.
    func scanForSelfTest() -> String {
        let start = Date()
        let found = try? scan()
        let took = String(format: "%.1fs", Date().timeIntervalSince(start))
        guard let (_, state) = found else { return "nothing found in \(took), JavaScript \(access)" }
        return "\(state.isPlaying ? "playing" : "paused") on \(state.h) in \(took)"
    }

    /// Every script this provider runs, for --media-selftest to compile.
    var selfTestScripts: [String] {
        let reference = TabReference(window: "1", tab: family == .safari ? "1" : "7", address: "https://example.com/")
        return [listScript, tabScript(Self.readScript, in: reference), tabScript(Self.controlScript("toggle"), in: reference)]
    }

    /// Chrome's ids are numbers, Arc's are text.
    private static func literal(_ id: String) -> String {
        Int(id) != nil ? id : AppleScript.quoted(id)
    }

    // MARK: - Page script

    /// Picks the element making the sound — playing, not muted, longest first — or the
    /// one left paused part way through, and reports it with the page's Now Playing
    /// details. Muted autoplay (ads, banners) is never "playing". An empty answer means
    /// no media on the page.
    private static let pickElement = """
    var L=[].slice.call(document.querySelectorAll('video,audio'));\
    var len=function(e){return isFinite(e.duration)?e.duration:0};\
    var live=L.filter(function(e){return !e.paused&&!e.ended&&!e.muted&&e.volume>0}).sort(function(a,b){return len(b)-len(a)});\
    var held=L.filter(function(e){return e.paused&&!e.ended&&e.currentTime>0}).sort(function(a,b){return len(b)-len(a)});\
    var e=live[0]||held[0]||null;\
    var s=navigator.mediaSession,m=s&&s.metadata,ss=s?s.playbackState:'none';
    """

    static let readScript = """
    (function(){\(pickElement)\
    if(!e&&!(m&&(ss==='playing'||ss==='paused')))return '';\
    var art='';\
    if(m&&m.artwork&&m.artwork.length){var best=m.artwork[0],size=0;\
    for(var i=0;i<m.artwork.length;i++){var w=parseInt((m.artwork[i].sizes||'0').split('x')[0])||0;if(w>=size){size=w;best=m.artwork[i]}}\
    try{art=new URL(best.src,location.href).href}catch(x){}}\
    return JSON.stringify({p:live.length>0||ss==='playing',t:m&&m.title||'',a:m&&m.artist||'',al:m&&m.album||'',art:art,\
    pos:e?e.currentTime:0,dur:e?len(e):0,v:e?Math.round(e.volume*100):-1,d:document.title||'',h:location.hostname||''})})()
    """

    /// Next and previous press the site's own buttons; play, pause, seek and volume act
    /// on the element directly, which every site honours.
    static func controlScript(_ command: String) -> String {
        """
        (function(c){\(pickElement)\
        var press=function(q){for(var i=0;i<q.length;i++){var b=document.querySelector(q[i]);if(b){b.click();return 'ok'}}return ''};\
        if(c==='toggle'){if(e){if(e.paused){e.play()}else{e.pause()}return 'ok'}\
        return press(['[data-testid=control-button-playpause]','.playControl','ytmusic-player-bar #play-pause-button'])}\
        if(c==='next')return press(['.ytp-next-button','ytmusic-player-bar .next-button','[data-testid=control-button-skip-forward]','.skipControl__next','.next-button']);\
        if(c==='previous'){var r=press(['.ytp-prev-button:not([aria-disabled=true])','ytmusic-player-bar .previous-button','[data-testid=control-button-skip-back]','.skipControl__previous']);\
        if(!r&&e){e.currentTime=0;r='ok'}return r}\
        var n=parseFloat(c.split(':')[1]);\
        if(e&&c.indexOf('seek:')===0){e.currentTime=n;return 'ok'}\
        if(e&&c.indexOf('volume:')===0){e.volume=Math.max(0,Math.min(1,n/100));return 'ok'}\
        return ''})('\(command)')
        """
    }

    /// Asks the front tab for a trivial answer, to find out whether JavaScript is
    /// allowed — from Settings, so the switch can be checked without playing anything.
    func checkAccess() {
        guard isRunning else { return }
        let frontTab = family == .safari ? "current tab" : "active tab"
        let probe = family == .safari ? "do JavaScript \"1\" in theTab" : "execute theTab javascript \"1\""
        let source = """
        with timeout of 3 seconds
            tell application id "\(bundleIdentifier)"
                if (count of windows) is 0 then return ""
                try
                    set theTab to \(frontTab) of front window
                on error
                    set theTab to tab 1 of front window
                end try
                \(probe)
            end tell
        end timeout
        """
        do {
            _ = try AppleScript.runReportingFailure(source)
            setAccess(.allowed)
        } catch let failure as AppleScript.Failure {
            if failure.message.localizedCaseInsensitiveContains("JavaScript") { setAccess(.blocked) }
        } catch {}
    }
}
