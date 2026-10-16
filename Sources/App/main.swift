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

let appDelegate = AppDelegate()

app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
