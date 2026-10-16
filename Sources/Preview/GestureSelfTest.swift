import AppKit

/// Feeds the swipe recogniser synthetic trackpad gestures: --gesture-selftest
///
/// Real scroll events, built through CoreGraphics with the fields a trackpad sets —
/// continuous deltas, gesture phases, momentum — so what is tested is what arrives.
enum GestureSelfTest {
    private enum Phase: Int64 {
        case began = 1, changed = 2, ended = 4, mayBegin = 128
    }

    static func run() {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }

        /// Deltas are in finger terms (+x right, +y down) and converted to what macOS
        /// reports with natural scrolling off, where content moves against the fingers.
        func gesture(_ steps: [(dx: Double, dy: Double)], precise: Bool = true, momentum: Bool = false) -> [SwipeRecognizer.Direction] {
            let recognizer = SwipeRecognizer()
            var fired: [SwipeRecognizer.Direction] = []
            func send(_ dx: Double, _ dy: Double, phase: Phase?, momentumPhase: Int64 = 0) {
                guard let event = CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0
                ) else { return }
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -dy)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -dx)
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase?.rawValue ?? 0)
                event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
                guard let nsEvent = NSEvent(cgEvent: event) else { return }
                if let direction = recognizer.feed(nsEvent) { fired.append(direction) }
            }

            send(0, 0, phase: .mayBegin)
            send(0, 0, phase: .began)
            for step in steps {
                send(step.dx, step.dy, phase: momentum ? nil : .changed, momentumPhase: momentum ? 2 : 0)
            }
            send(0, 0, phase: .ended)
            return fired
        }

        let short = Array(repeating: (dx: 0.0, dy: 6.0), count: 5)          // 30pt down
        let down = Array(repeating: (dx: 0.0, dy: 8.0), count: 8)           // 64pt down
        let up = Array(repeating: (dx: 0.0, dy: -8.0), count: 8)
        let left = Array(repeating: (dx: -10.0, dy: 0.0), count: 8)         // 80pt left
        let right = Array(repeating: (dx: 10.0, dy: 0.0), count: 8)
        let diagonal = Array(repeating: (dx: 8.0, dy: 7.0), count: 10)

        expect("down", gesture(down) == [.down])
        expect("up", gesture(up) == [.up])
        expect("left", gesture(left) == [.left])
        expect("right", gesture(right) == [.right])
        expect("a short movement is not a swipe", gesture(short).isEmpty)
        expect("a diagonal is not a swipe", gesture(diagonal).isEmpty)
        expect("a long swipe fires once", gesture(down + down + down) == [.down])
        expect("a mouse wheel never swipes", gesture(down, precise: false).isEmpty)
        expect("momentum after lifting never swipes", gesture(down, momentum: true).isEmpty)

        let failed = results.filter { $0.hasPrefix("✗") }.count
        FileHandle.standardError.write(Data(("gestures: " + results.joined(separator: "  ") + "\n").utf8))
        exit(failed == 0 ? 0 : 1)
    }
}
