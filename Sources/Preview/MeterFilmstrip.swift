import AppKit

/// --meter-filmstrip <file.png>: the level meter, music then recording, drawn every
/// 80ms in a strip, enlarged — to judge the motion by eye rather than by numbers.
enum MeterFilmstrip {
    static func run(to path: String) {
        let size = CGSize(width: 18, height: 13)
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 60, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .black
        let meter = LevelMeterView(frame: CGRect(origin: CGPoint(x: 20, y: 13), size: size))
        window.contentView?.addSubview(meter)
        window.orderFrontRegardless()
        meter.layoutSubtreeIfNeeded()

        let frames = 24, scale: CGFloat = 6
        var shots: [[CGImage]] = [[], []]
        var phase = 0, count = 0

        func capture() -> CGImage? {
            let width = Int(size.width * scale), height = Int(size.height * scale)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            (meter.layer?.presentation() ?? meter.layer)?.render(in: context)
            return context.makeImage()
        }

        meter.kind = .music
        meter.isRunning = true
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { timer in
            if let image = capture() { shots[phase].append(image) }
            count += 1
            guard count >= frames else { return }
            count = 0
            if phase == 0 {
                phase = 1
                meter.kind = .recording
                meter.isRunning = false
                meter.isRunning = true
                return
            }
            timer.invalidate()
            write(shots, cell: CGSize(width: size.width * scale, height: size.height * scale), to: path)
            exit(0)
        }
    }

    private static func write(_ rows: [[CGImage]], cell: CGSize, to path: String) {
        let gap: CGFloat = 8
        let columns = rows.map(\.count).max() ?? 0
        let width = Int(CGFloat(columns) * (cell.width + gap)), height = Int(CGFloat(rows.count) * (cell.height + gap))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(NSColor(white: 0.2, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (row, images) in rows.enumerated() {
            for (column, image) in images.enumerated() {
                let y = CGFloat(height) - CGFloat(row + 1) * (cell.height + gap)
                context.draw(image, in: CGRect(x: CGFloat(column) * (cell.width + gap), y: y, width: cell.width, height: cell.height))
            }
        }
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
