import AppKit

/// Measures the open and close animations frame by frame: --animation-selftest
///
/// A still render cannot show whether the slab grows from its centre, so this puts a
/// real panel on screen, samples the drawn shape every 40ms, and reports whether its
/// centre held still while it grew and shrank.
enum AnimationSelfTest {
    private static var retained: [AnyObject] = []

    static func run() {
        func report(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }

        guard let screen = NSScreen.main else { exit(1) }
        let geometry = NotchGeometry(screen: screen)
        let notchWidth = geometry.hasNotch ? geometry.notchRect.width : 0
        let notchHeight = geometry.hasNotch ? geometry.notchRect.height : 0

        let content = NotchContentView(notchWidth: notchWidth, notchHeight: notchHeight)
        let panel = NotchPanel(contentView: content)
        let size = NotchContentView.Metrics.panelSize(notchWidth: notchWidth, notchHeight: notchHeight)
        panel.setFrame(geometry.expandedFrame(size: size), display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        retained = [content, panel]

        let panelMidX = size.width / 2

        func sample(_ label: String, ticksWanted: Int = 11, then next: @escaping () -> Void) {
            var ticks = 0
            var drift: CGFloat = 0
            var widths: [Int] = []
            Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
                ticks += 1
                if let rect = content.card.presentedShapeBounds {
                    drift = max(drift, abs(rect.midX - panelMidX))
                    widths.append(Int(rect.width))
                }
                if ticks >= ticksWanted {
                    timer.invalidate()
                    if widths.count > 20 {
                        // A burst runs for seconds; the whole list would be unreadable.
                        let opening = widths.prefix(12).map(String.init).joined(separator: " → ")
                        report("\(label): \(opening) … peak \(widths.max() ?? 0) → \(widths.last ?? 0)pt over \(String(format: "%.1f", Double(ticks) * 0.04))s")
                    } else {
                        report("\(label): widths \(widths.map(String.init).joined(separator: " → "))")
                    }
                    report("\(label): largest drift of centre from middle = \(String(format: "%.1f", drift))pt")
                    if let last = widths.last, let peak = widths.max() {
                        report("\(label): settled at \(last)pt, peaked at \(peak)pt")
                    }
                    next()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            content.present(.hidden, animated: false)
            report("notch width \(Int(notchWidth))pt")
            content.present(.idle)
            // Exactly what the controller does when music starts: settle the bar out
            // and ask for a breath in the same turn. The morph must run first.
            content.breathe()
            sample("hidden → resting bar, then breath", ticksWanted: 60) {
                content.present(.expanded)
                sample("resting bar → panel") {
                    content.present(.idle)
                    sample("panel → resting bar") {
                        // A notification landing on a bar that is already out: it should
                        // grow past its settled width and come back to it.
                        content.showActivity(.notification(app: "Messages", title: "Are we still on for six?"))
                        sample("resting bar + notification", ticksWanted: 16) {
                            content.clearActivity()
                            sample("notification cleared") {
                                // A burst: the width should move on its own, then stop.
                                content.breathe()
                                // Long enough to outlast the burst: it has to come back
                                // to rest and stay there, not keep going.
                                sample("breath burst", ticksWanted: 180) {
                                    content.present(.hidden)
                                    sample("resting bar → hidden") {
                                        panel.orderOut(nil)
                                        exit(0)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
