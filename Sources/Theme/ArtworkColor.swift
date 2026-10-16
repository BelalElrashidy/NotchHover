import AppKit
import CoreImage

extension NSColor {
    /// A lighter, more saturated relative of this colour, for accents on top of it.
    var notchAccentVariant: NSColor {
        guard let converted = usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(1, saturation + 0.2), brightness: min(1, brightness + 0.55), alpha: 1)
    }
}

/// Pulls a panel colour out of album art.
enum ArtworkColor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    private static var cache: [String: NSColor] = [:]

    /// Averages the image, then forces it dark and saturated enough that white text
    /// stays readable whatever the cover looks like.
    static func panelColor(from image: NSImage, key: String) -> NSColor? {
        if let cached = cache[key] { return cached }

        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }

        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent)
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let average = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let panel = NSColor(
            hue: hue,
            saturation: min(0.62, max(0.28, saturation)),
            // Dark enough that white text clears contrast on any cover.
            brightness: min(0.26, max(0.14, brightness * 0.4)),
            alpha: 1
        )

        cache[key] = panel
        if cache.count > 40 { cache.removeAll() }
        return panel
    }
}
