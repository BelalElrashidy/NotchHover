import AppKit

// Rasterises the SVGs and builds a comparison sheet against the original icon.
// Usage: swift render.swift <project root>

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let here = root.appendingPathComponent("Design/icon-enhanced")
let out = here.appendingPathComponent("renders")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func load(_ url: URL) -> NSImage {
    guard let image = NSImage(contentsOf: url) else { fatalError("cannot load \(url.lastPathComponent)") }
    return image
}

func bitmap(_ image: NSImage, size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

let names = ["capstone-refined", "capstone-dimensional", "capstone-dark", "capstone-small",
             "capstone-template-keystone", "capstone-template-open"]
var images: [String: NSImage] = [:]
for name in names {
    let image = load(here.appendingPathComponent("\(name).svg"))
    images[name] = image
    for size in [1024, 512, 256, 128, 64, 32, 16] {
        save(bitmap(image, size: size), "\(name)-\(size).png")
    }
}
print("rendered \(names.count) icons at 7 sizes")

// ---- Comparison sheet -------------------------------------------------------

let original = load(root.appendingPathComponent("icon-1024.png"))
let originalSmall = [32: load(root.appendingPathComponent("icon-32.png")),
                     16: load(root.appendingPathComponent("icon-16.png"))]

let rows: [(String, NSImage, [Int: NSImage]?)] = [
    ("Your original", original, originalSmall),
    ("Refined", images["capstone-refined"]!, nil),
    ("Dimensional", images["capstone-dimensional"]!, nil),
    ("Dark", images["capstone-dark"]!, nil),
    ("Small-size master", images["capstone-small"]!, nil),
]

let sheetWidth = 1560, rowHeight = 300, top = 90
let sheetHeight = top + rows.count * rowHeight + 260
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetWidth, pixelsHigh: sheetHeight,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: sheet)!
NSGraphicsContext.current = context

NSColor(srgbRed: 0.97, green: 0.97, blue: 0.975, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()

func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .black, weight: NSFont.Weight = .regular) {
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ]).draw(at: NSPoint(x: x, y: CGFloat(sheetHeight) - y))
}

let grey = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1)
text("The Capstone — original vs enhanced", x: 40, y: 58, size: 30, weight: .semibold)
for (label, x) in [("256", 300), ("64", 640), ("32 · actual pixels ×6", 830), ("16 · actual pixels ×6", 1150)] {
    text(label, x: CGFloat(x), y: CGFloat(top) + 6, size: 14, color: grey)
}

for (index, row) in rows.enumerated() {
    let baseY = CGFloat(sheetHeight - top - (index + 1) * rowHeight) + 20
    text(row.0, x: 40, y: CGFloat(sheetHeight) - baseY - 140, size: 18, weight: .medium)

    context.imageInterpolation = .high
    row.1.draw(in: NSRect(x: 260, y: baseY + 10, width: 250, height: 250))
    row.1.draw(in: NSRect(x: 640, y: baseY + 103, width: 64, height: 64))

    for (size, x) in [(32, 830), (16, 1150)] {
        let small = row.2?[size] ?? {
            let rep = bitmap(row.1, size: size)
            let image = NSImage(size: NSSize(width: size, height: size))
            image.addRepresentation(rep)
            return image
        }()
        context.imageInterpolation = .none
        small.draw(in: NSRect(x: CGFloat(x), y: baseY + 39, width: CGFloat(size * 6) , height: CGFloat(size * 6)),
                   from: .zero, operation: .sourceOver, fraction: 1)
    }
}

// Menu bar templates on light and dark bars.
let barY: CGFloat = 40
text("Menu bar templates · 18pt, on light and dark bars", x: 40, y: CGFloat(sheetHeight) - barY - 196, size: 16, color: grey)
for (templateIndex, name) in ["capstone-template-keystone", "capstone-template-open"].enumerated() {
    let label = templateIndex == 0 ? "keystone" : "open slot"
    for (barIndex, dark) in [false, true].enumerated() {
        let x = CGFloat(40 + templateIndex * 760)
        let y = barY + CGFloat(barIndex) * 70
        (dark ? NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1) : NSColor(srgbRed: 0.9, green: 0.9, blue: 0.92, alpha: 1)).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 720, height: 54), xRadius: 10, yRadius: 10).fill()
        let tinted = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            images[name]!.draw(in: rect)
            (dark ? NSColor.white : NSColor.black).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        context.imageInterpolation = .high
        tinted.draw(in: NSRect(x: x + 20, y: y + 18, width: 18, height: 18))
        context.imageInterpolation = .none
        tinted.draw(in: NSRect(x: x + 70, y: y + 4, width: 46, height: 46))
        text(label + (dark ? " · dark" : " · light"), x: x + 140, y: CGFloat(sheetHeight) - y - 36, size: 14,
             color: dark ? NSColor(white: 0.8, alpha: 1) : grey)
    }
}

NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: here.appendingPathComponent("comparison.png"))
print("wrote comparison.png")
