import AppKit

let app = NSApplication.shared

// Offscreen layout preview: NotchHover.app/Contents/MacOS/NotchHover --render-preview <dir>
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
   CommandLine.arguments.count > index + 1 {
    app.setActivationPolicy(.prohibited)
    PreviewRenderer.render(to: CommandLine.arguments[index + 1])
    exit(0)
}

let appDelegate = AppDelegate()

app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
