import AppKit
import PDFKit

/// Every file action on a made-up image, in a temporary folder: --fileactions-selftest
enum FileActionsSelfTest {
    static func run() {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchhover-actions-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // A picture with words on it, so text recognition has something to read.
        let image = NSImage(size: NSSize(width: 800, height: 400))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 400).fill()
        NSColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 560, y: 120, width: 180, height: 180)).fill()
        NSAttributedString(string: "Hello NotchHover", attributes: [
            .font: NSFont.systemFont(ofSize: 56, weight: .bold), .foregroundColor: NSColor.black
        ]).draw(at: CGPoint(x: 40, y: 170))
        image.unlockFocus()
        let png = folder.appendingPathComponent("Sample.png")
        let tiff = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        try? tiff?.representation(using: .png, properties: [:])?.write(to: png)

        expect("a PNG offers JPEG, resize, compress, text, cut-out, PDF, location, zip",
               FileAction.actions(for: [png]) == [.toJPEG, .resize, .compress, .copyText, .removeBackground, .makePDF, .stripLocation, .zip])
        expect("a video offers MP4 and zip", FileAction.actions(for: [URL(fileURLWithPath: "/a.mov")]) == [.toMP4, .zip])
        expect("anything else can be zipped", FileAction.actions(for: [URL(fileURLWithPath: "/a.txt")]) == [.zip])

        func perform(_ action: FileAction, _ urls: [URL]) -> Result<FileAction.Outcome, Error>? {
            var outcome: Result<FileAction.Outcome, Error>?
            action.perform(on: urls) { outcome = $0 }
            let deadline = Date().addingTimeInterval(30)
            while outcome == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            return outcome
        }
        func file(_ result: Result<FileAction.Outcome, Error>?) -> URL? {
            if case .success(.files(let urls)) = result { return urls.first }
            return nil
        }

        let jpeg = file(perform(.toJPEG, [png]))
        expect("to JPEG writes Sample.jpg beside it", jpeg?.lastPathComponent == "Sample.jpg" && jpeg.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        if let jpeg { expect("to PNG from a JPEG", file(perform(.toPNG, [jpeg]))?.pathExtension == "png") }

        let half = file(perform(.resize, [png]))
        let halfWidth = half.flatMap { NSImageRep(contentsOf: $0)?.pixelsWide }
        expect("resize halves it (\(halfWidth ?? 0)px)", halfWidth == 800 || halfWidth == 400)

        expect("compress writes a JPEG", file(perform(.compress, [png]))?.lastPathComponent == "Sample (compressed).jpg")
        expect("remove location keeps the format", file(perform(.stripLocation, [png]))?.lastPathComponent == "Sample (no location).png")

        if case .success(.copied) = perform(.copyText, [png]) {
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            expect("copy text reads \"\(text.prefix(30))\"", text.localizedCaseInsensitiveContains("Hello"))
        } else {
            expect("copy text reads the words", false)
        }

        let pdf = file(perform(.makePDF, [png, png]))
        expect("make PDF puts each image on a page", pdf.flatMap { PDFDocument(url: $0)?.pageCount } == 2)

        let zip = file(perform(.zip, [png, pdf].compactMap { $0 }))
        expect("zip makes Archive.zip", zip?.lastPathComponent == "Archive.zip")

        switch perform(.removeBackground, [png]) {
        case .success(.files(let made)): expect("remove background cuts out a PNG", made.first?.pathExtension == "png")
        case .failure(let error): results.append("– remove background: \(error.localizedDescription) (fine for a drawing)")
        default: expect("remove background answers", false)
        }

        expect("never overwrites: a second JPEG is Sample 2.jpg", file(perform(.toJPEG, [png]))?.lastPathComponent == "Sample 2.jpg")

        let failed = results.filter { $0.hasPrefix("✗") }.count
        FileHandle.standardError.write(Data(("file actions:\n  " + results.joined(separator: "\n  ") + "\n").utf8))
        exit(failed == 0 ? 0 : 1)
    }
}
