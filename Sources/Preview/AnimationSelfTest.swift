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

        /// Samples the meter for a second: a running meter's bars change height, a stopped
        /// one's don't. Runs as a separate phase before the shape test.
        func sampleMeter(_ label: String, then next: @escaping () -> Void) {
            var levels: [[CGFloat]] = []
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                levels.append(content.idleMeter.drawnLevels)
                guard levels.count >= 20 else { return }
                timer.invalidate()
                let spread = (0..<(levels.first?.count ?? 0)).map { bar in
                    let column = levels.map { $0[bar] }
                    return (column.max() ?? 0) - (column.min() ?? 0)
                }
                let moving = spread.allSatisfy { $0 > 0.1 }
                report("meter, \(label): \(moving ? "moving" : "STILL") — bars ranged \(spread.map { String(format: "%.2f", $0) }.joined(separator: " / ")), animation attached: \(content.idleMeter.hasBounceAnimation)")
                next()
            }
        }

        let playing = TrackInfo(
            name: "Test", artist: "Test", isPlaying: true, artworkURL: nil, sourceName: "Spotify",
            sourceBundleIdentifier: "com.spotify.client", position: 10, duration: 200, volume: 50, isShuffling: false
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            content.renderNowPlaying(.track(playing))
            content.present(.idle, animated: false)
            sampleMeter("playing, resting") {
                content.present(.expanded)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    content.present(.idle)
                    sampleMeter("playing, after opening and closing") {
                        panel.orderOut(nil)
                        panel.orderFrontRegardless()
                        sampleMeter("playing, after the window was hidden and shown") {
                            let paused = TrackInfo(
                                name: "Test", artist: "Test", isPlaying: false, artworkURL: nil, sourceName: "Spotify",
                                sourceBundleIdentifier: "com.spotify.client", position: 10, duration: 200, volume: 50, isShuffling: false
                            )
                            content.renderNowPlaying(.track(paused))
                            // The bars ease down to dots first; sample once they're there.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                sampleMeter("paused") {
                                    startShapeTest()
                                }
                            }
                        }
                    }
                }
            }
        }

        func startShapeTest() {
            content.present(.hidden, animated: false)
            report("notch width \(Int(notchWidth))pt")
            content.present(.idle)
            // Exactly what the controller does when music starts: settle the bar out
            // and ask for a breath in the same turn. The morph must run first.
            content.breathe()
            sample("hidden → resting bar, then breath", ticksWanted: 60) {
                // Resting on the notch: the peek, back, the peek again, then a click.
                content.present(.peek)
                sample("resting bar → peek") {
                content.present(.idle)
                sample("peek → resting bar") {
                content.present(.peek)
                sample("resting bar → peek, again") {
                content.present(.expanded)
                sample("peek → panel") {
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
                }}}
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
