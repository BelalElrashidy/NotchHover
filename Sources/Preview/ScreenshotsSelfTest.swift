import AppKit

/// Telling screenshots from other pictures, without taking one: --screenshots-selftest
enum ScreenshotsSelfTest {
    static func run() {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhover-shots-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func write(_ name: String, marked: Bool, age: TimeInterval) -> URL {
            let url = folder.appendingPathComponent(name)
            let image = NSImage(size: NSSize(width: 40, height: 30))
            image.lockFocus(); NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 40, height: 30).fill(); image.unlockFocus()
            try? image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])?.write(to: url)
            if marked {
                // What macOS writes on every screenshot: a binary plist `true`.
                let value = try! PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
                _ = value.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, value.count, 0, 0) }
            }
            try? FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }

        let older = write("Screenshot older.png", marked: true, age: 600)
        let newer = write("Bildschirmfoto neuer.png", marked: true, age: 10)
        let photo = write("Holiday.png", marked: false, age: 5)

        expect("a screenshot is recognised by its marker, in any language", ScreenshotStore.isScreenshot(newer))
        expect("an ordinary picture is not", ScreenshotStore.isScreenshot(photo) == false)
        expect("newest first, pictures left out", ScreenshotStore.scan([folder]).map(\.lastPathComponent) == [newer, older].map(\.lastPathComponent))
        expect("the screenshots folder exists (\(ScreenshotStore.folder.path))", FileManager.default.fileExists(atPath: ScreenshotStore.folder.path))

        let failed = results.filter { $0.hasPrefix("✗") }.count
        FileHandle.standardError.write(Data(("screenshots: " + results.joined(separator: "  ") + "\n").utf8))
        exit(failed == 0 ? 0 : 1)
    }
}
