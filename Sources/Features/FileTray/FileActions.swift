import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Things to do with files dropped on the notch or sitting on the shelf. Every one runs
/// on the Mac with what macOS already has — ImageIO, Vision, PDFKit, AVFoundation and
/// `ditto` — so nothing is uploaded anywhere.
///
/// New files go next to the originals ("Photo.jpg" beside "Photo.heic"), or to Downloads
/// when that folder can't be written, and land on the shelf. Originals are never changed.
enum FileAction: Equatable, CaseIterable {
    case toJPEG, toPNG, resize, compress, removeBackground, stripLocation
    case copyText, makePDF, toMP4, zip

    var title: String {
        switch self {
        case .toJPEG: return "Convert to JPEG"
        case .toPNG: return "Convert to PNG"
        case .resize: return "Resize to half"
        case .compress: return "Compress"
        case .removeBackground: return "Remove background"
        case .stripLocation: return "Remove location"
        case .copyText: return "Copy text"
        case .makePDF: return "Make PDF"
        case .toMP4: return "Convert to MP4"
        case .zip: return "Zip"
        }
    }

    /// Short, for the drop zones.
    var shortTitle: String {
        switch self {
        case .toJPEG: return "To JPEG"
        case .toPNG: return "To PNG"
        case .toMP4: return "To MP4"
        case .copyText: return "Copy text"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .toJPEG, .toPNG, .toMP4: return "arrow.triangle.2.circlepath"
        case .resize: return "arrow.down.right.and.arrow.up.left"
        case .compress: return "arrow.down.circle"
        case .removeBackground: return "person.crop.rectangle"
        case .stripLocation: return "location.slash"
        case .copyText: return "text.viewfinder"
        case .makePDF: return "doc.richtext"
        case .zip: return "doc.zipper"
        }
    }

    // MARK: - What fits

    enum Kind { case image, pdf, video, other }

    static func kind(of url: URL) -> Kind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return .other
    }

    /// Every action that makes sense for all of these files together, most useful first.
    static func actions(for urls: [URL]) -> [FileAction] {
        guard urls.isEmpty == false else { return [] }
        let kinds = Set(urls.map(kind(of:)))
        var actions: [FileAction] = []
        if kinds == [.image] {
            let allJPEG = urls.allSatisfy { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            actions += [allJPEG ? .toPNG : .toJPEG, .resize, .compress, .copyText, .removeBackground, .makePDF, .stripLocation]
        } else if kinds == [.pdf] {
            actions += [.copyText] + (urls.count > 1 ? [.makePDF] : [])
        } else if kinds.isSubset(of: [.image, .pdf]) {
            actions += [.makePDF, .copyText]
        } else if kinds == [.video] {
            actions += [.toMP4]
        }
        actions.append(.zip)
        return actions
    }

    /// The conversion a "Convert" drop zone means for these files, if any.
    static func conversion(for urls: [URL]) -> FileAction? {
        actions(for: urls).first { [.toJPEG, .toPNG, .toMP4].contains($0) }
    }

    // MARK: - Doing it

    enum Outcome {
        /// New files, for the shelf.
        case files([URL])
        /// Text put on the clipboard.
        case copied(characters: Int)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Runs off the main thread; the completion comes back on it.
    func perform(on urls: [URL], completion: @escaping (Result<Outcome, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let finish = { (result: Result<Outcome, Error>) in DispatchQueue.main.async { completion(result) } }
            switch self {
            case .toMP4:
                Self.exportVideos(urls, finish: finish)
            default:
                finish(Result { try self.run(on: urls) })
            }
        }
    }

    private func run(on urls: [URL]) throws -> Outcome {
        switch self {
        case .toJPEG:
            return .files(try urls.map { try Self.writeImage(from: $0, as: .jpeg, quality: 0.9) })
        case .toPNG:
            return .files(try urls.map { try Self.writeImage(from: $0, as: .png) })
        case .resize:
            return .files(try urls.map { try Self.writeImage(from: $0, as: nil, scale: 0.5, suffix: "half") })
        case .compress:
            return .files(try urls.map { try Self.writeImage(from: $0, as: .jpeg, quality: 0.6, suffix: "compressed") })
        case .stripLocation:
            return .files(try urls.map { try Self.writeImage(from: $0, as: nil, stripMetadata: true, suffix: "no location") })
        case .removeBackground:
            return .files(try urls.map(Self.removeBackground))
        case .copyText:
            let text = try urls.map(Self.recognizeText).filter { $0.isEmpty == false }.joined(separator: "\n\n")
            guard text.isEmpty == false else { throw Failure(message: "No text found") }
            DispatchQueue.main.sync {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return .copied(characters: text.count)
        case .makePDF:
            return .files([try Self.makePDF(from: urls)])
        case .zip:
            return .files([try Self.zip(urls)])
        case .toMP4:
            throw Failure(message: "Video runs separately")
        }
    }

    // MARK: Where new files go

    /// Beside the first original, or in Downloads; never over an existing file.
    static func destination(for source: URL, name: String, extension ext: String) -> URL {
        var folder = source.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: folder.path) == false {
            folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    // MARK: Images

    private static func writeImage(from url: URL, as type: UTType?, quality: Double? = nil, scale: CGFloat = 1,
                                   stripMetadata: Bool = false, suffix: String? = nil) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else { throw Failure(message: "Couldn't read \(url.lastPathComponent)") }
        let outputType = type ?? UTType(sourceType as String) ?? .png
        let base = url.deletingPathExtension().lastPathComponent
        let output = destination(for: url, name: suffix.map { "\(base) (\($0))" } ?? base,
                                 extension: outputType == .jpeg ? "jpg" : (outputType.preferredFilenameExtension ?? "png"))
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, outputType.identifier as CFString, 1, nil) else {
            throw Failure(message: "Can't write \(outputType.preferredFilenameExtension ?? "that format")")
        }

        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        if stripMetadata {
            // Location, camera and editing details go; the picture stays as it was.
            options[kCGImagePropertyGPSDictionary] = kCFNull
            options[kCGImagePropertyExifDictionary] = kCFNull
            options[kCGImagePropertyIPTCDictionary] = kCFNull
            options[kCGImagePropertyMakerAppleDictionary] = kCFNull
        }

        if scale == 1 {
            CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        } else {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, max(width, height) * scale)
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                throw Failure(message: "Couldn't resize \(url.lastPathComponent)")
            }
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't save \(output.lastPathComponent)") }
        return output
    }

    private static func cgImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary)
    }

    private static func removeBackground(_ url: URL) throws -> URL {
        guard let image = cgImage(at: url) else { throw Failure(message: "Couldn't read \(url.lastPathComponent)") }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first else { throw Failure(message: "No subject found in \(url.lastPathComponent)") }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let masked = context.createCGImage(ciImage, from: ciImage.extent) else { throw Failure(message: "Couldn't cut out the subject") }
        let output = destination(for: url, name: "\(url.deletingPathExtension().lastPathComponent) (cut out)", extension: "png")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(message: "Can't write PNG")
        }
        CGImageDestinationAddImage(destination, masked, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't save \(output.lastPathComponent)") }
        return output
    }

    // MARK: Text

    /// A PDF's own text when it has some; otherwise the words read off the page or image.
    static func recognizeText(in url: URL) throws -> String {
        if kind(of: url) == .pdf, let document = PDFDocument(url: url) {
            if let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false { return text }
            return try (0..<document.pageCount).compactMap { index -> String? in
                guard let page = document.page(at: index) else { return nil }
                let thumbnail = page.thumbnail(of: page.bounds(for: .mediaBox).size.applying(.init(scaleX: 2, y: 2)), for: .mediaBox)
                guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                return try recognizeText(in: image)
            }.joined(separator: "\n\n")
        }
        guard let image = cgImage(at: url) else { throw Failure(message: "Couldn't read \(url.lastPathComponent)") }
        return try recognizeText(in: image)
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: PDF

    private static func makePDF(from urls: [URL]) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            if kind(of: url) == .pdf, let source = PDFDocument(url: url) {
                for index in 0..<source.pageCount {
                    if let page = source.page(at: index) { document.insert(page, at: document.pageCount) }
                }
            } else if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                document.insert(page, at: document.pageCount)
            }
        }
        guard document.pageCount > 0, let first = urls.first else { throw Failure(message: "Nothing to put in a PDF") }
        let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Combined"
        let output = destination(for: first, name: name, extension: "pdf")
        guard document.write(to: output) else { throw Failure(message: "Couldn't save \(output.lastPathComponent)") }
        return output
    }

    // MARK: Zip

    /// `ditto`, like Finder's Compress: it keeps resource forks and bundles intact.
    private static func zip(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw Failure(message: "Nothing to zip") }
        let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let output = destination(for: first, name: name, extension: "zip")

        var source = first
        var staging: URL?
        if urls.count > 1 {
            // Several files go into one folder first, so the archive opens as that folder.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in urls {
                try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            }
            source = folder
            staging = folder.deletingLastPathComponent()
        }
        defer { staging.map { try? FileManager.default.removeItem(at: $0) } }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, output.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(message: "Couldn't zip") }
        return output
    }

    // MARK: Video

    private static func exportVideos(_ urls: [URL], finish: @escaping (Result<Outcome, Error>) -> Void) {
        var outputs: [URL] = []
        var failure: Error?
        let lock = NSLock()
        let group = DispatchGroup()
        for url in urls {
            group.enter()
            let asset = AVURLAsset(url: url)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
                failure = Failure(message: "Can't convert \(url.lastPathComponent)")
                group.leave()
                continue
            }
            let output = destination(for: url, name: url.deletingPathExtension().lastPathComponent, extension: "mp4")
            session.outputURL = output
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            session.exportAsynchronously {
                lock.lock()
                defer { lock.unlock() }
                if session.status == .completed {
                    outputs.append(output)
                } else {
                    failure = session.error ?? Failure(message: "Couldn't convert \(url.lastPathComponent)")
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if outputs.isEmpty, let failure {
                finish(.failure(failure))
            } else {
                finish(.success(.files(outputs)))
            }
        }
    }
}

/// Runs an action and reports how it went: new files onto the shelf, a line in the notch.
enum FileActionRunner {
    /// Wired to the resting bar's activities: a symbol and a few words.
    static var onReport: ((String, String) -> Void)?

    static func run(_ action: FileAction, on urls: [URL]) {
        Log.system.notice("File action: \(action.title, privacy: .public) on \(urls.count, privacy: .public) file(s)")
        onReport?("hourglass", "\(action.title)…")
        action.perform(on: urls) { result in
            switch result {
            case .success(.files(let made)):
                FileTray.shared.add(made)
                onReport?("checkmark.circle.fill", made.count == 1 ? made[0].lastPathComponent : "\(made.count) files on the shelf")
            case .success(.copied(let characters)):
                onReport?("doc.on.clipboard.fill", "Copied \(characters) characters")
            case .failure(let error):
                Log.system.error("File action failed: \(error.localizedDescription, privacy: .public)")
                onReport?("exclamationmark.triangle.fill", error.localizedDescription)
            }
        }
    }
}
