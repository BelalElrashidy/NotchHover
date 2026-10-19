import AppKit

let app = NSApplication.shared

// Offscreen layout preview: NotchHover.app/Contents/MacOS/NotchHover --render-preview <dir>
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
   CommandLine.arguments.count > index + 1 {
    app.setActivationPolicy(.prohibited)
    PreviewRenderer.render(to: CommandLine.arguments[index + 1])
    exit(0)
}

// Swipe recognition against synthetic trackpad events: --gesture-selftest
if CommandLine.arguments.contains("--gesture-selftest") {
    app.setActivationPolicy(.prohibited)
    GestureSelfTest.run()
}

// What Safari's tab script really returns, under this app's own permissions.
if CommandLine.arguments.contains("--safari-selftest") {
    app.setActivationPolicy(.prohibited)
    FileHandle.standardError.write(Data(("safari, main thread: " + BrowserPageReader.diagnoseSafari() + "\n").utf8))
    // The app runs the lookup on a background queue; check that path gets the same answer.
    let done = DispatchSemaphore(value: 0)
    DispatchQueue(label: "safari-selftest", qos: .utility).async {
        FileHandle.standardError.write(Data(("safari, background queue: " + BrowserPageReader.diagnoseSafari() + "\n").utf8))
        done.signal()
    }
    done.wait()
    exit(0)
}

// Meeting links found in invitation text: --calendar-selftest
if CommandLine.arguments.contains("--calendar-selftest") {
    app.setActivationPolicy(.prohibited)
    CalendarSelfTest.run()
}

// Accessory battery parsing and announcements: --devices-selftest
if CommandLine.arguments.contains("--devices-selftest") {
    app.setActivationPolicy(.prohibited)
    DevicesSelfTest.run()
}

// Lyrics parsing and timing: --lyrics-selftest [live]
if let index = CommandLine.arguments.firstIndex(of: "--lyrics-selftest") {
    app.setActivationPolicy(.prohibited)
    LyricsSelfTest.run(live: CommandLine.arguments.dropFirst(index + 1).first == "live")
}

// The lock screen's space, tried with an invisible window — nothing is locked.
if CommandLine.arguments.contains("--lockscreen-selftest") {
    app.setActivationPolicy(.prohibited)
    let (available, added) = LockScreenMusic.probe()
    FileHandle.standardError.write(Data("lock screen: SkyLight functions \(available ? "found" : "missing"), window moved to the lock screen space: \(added)\n".utf8))
    exit(available && added ? 0 : 1)
}

// Meeting controls: what call is on right now, and whether the Meet script compiles
// for each installed browser. Reads only; presses nothing.
if CommandLine.arguments.contains("--meeting-selftest") {
    app.setActivationPolicy(.prohibited)
    let recording = AudioSourceProbe.recordingApplications().compactMap(\.localizedName)
    var lines = ["microphone in use by: " + (recording.isEmpty ? "nothing" : recording.joined(separator: ", "))]
    for browser in MeetingControls.browsers.sorted() {
        guard let compiles = MeetingControls.meetScriptCompiles(browser: browser) else { continue }
        lines.append("Meet script for \(browser): \(compiles ? "compiles" : "does NOT compile")")
    }
    FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    exit(lines.contains { $0.contains("NOT") } ? 1 : 0)
}

// Claude Code sessions and usage from this Mac's transcripts — metadata only.
if CommandLine.arguments.contains("--claude-selftest") {
    app.setActivationPolicy(.prohibited)
    let monitor = ClaudeSessionMonitor()
    var started = Date()
    var (sessions, usage) = monitor.scanNow()
    let first = Date().timeIntervalSince(started)
    started = Date()
    (sessions, usage) = monitor.scanNow()
    let second = Date().timeIntervalSince(started)
    var lines = ["first read \(Int(first * 1000))ms, next \(Int(second * 1000))ms"]
    lines += sessions.map { "session \($0.project) · \($0.branch ?? "-") — \($0.state.label)" }
    lines.append("today \(ClaudePaneView.tokens(usage.today)) (output \(ClaudePaneView.tokens(usage.todayOutput))), last 5h \(ClaudePaneView.tokens(usage.lastFiveHours))")
    FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    exit(0)
}

let appDelegate = AppDelegate()

app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
