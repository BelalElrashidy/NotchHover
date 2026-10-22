import AppKit

/// Turns two-finger trackpad scrolls into swipes: up, down, left or right, at most once
/// per gesture.
///
/// Directions are the way the *fingers* moved, whatever the natural-scrolling setting —
/// macOS reports scroll deltas in content terms, so the same swipe arrives with opposite
/// signs on two Macs set up differently. A mouse wheel never counts: it scrolls, it
/// doesn't swipe. Nor does momentum after the fingers lift, which would otherwise turn a
/// flick into a second swipe.
final class SwipeRecognizer {
    enum Direction {
        case up, down, left, right

        var isVertical: Bool { self == .up || self == .down }
    }

    /// Defaults key for switching gestures off.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "TrackpadGestures") as? Bool ?? true
    }

    private enum Threshold {
        /// Far enough to be deliberate, short enough not to feel like work.
        static let vertical: CGFloat = 40
        /// Sideways needs a little more: a vertical scroll often drifts sideways.
        static let horizontal: CGFloat = 60
        /// The winning axis has to lead the other by this much to count at all.
        static let dominance: CGFloat = 1.5
    }

    /// How far the fingers have moved in this gesture so far: +x right, +y down. The
    /// panel's views follow it sideways until a swipe is recognised.
    private(set) var travel = CGVector.zero
    private(set) var isTracking = false
    private(set) var hasFired = false
    /// The fingers lifted before anything was recognised — whatever followed them
    /// goes back.
    private(set) var endedWithoutSwipe = false

    /// Feeds one scroll event. Returns a direction the moment a swipe is recognised;
    /// afterwards the rest of that gesture is ignored until the fingers lift.
    func feed(_ event: NSEvent) -> Direction? {
        guard Self.isEnabled, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return nil }

        endedWithoutSwipe = false
        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            travel = .zero
            hasFired = false
            isTracking = true
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            endedWithoutSwipe = isTracking && hasFired == false
            isTracking = false
            return nil
        }
        guard isTracking, hasFired == false else { return nil }

        // Finger motion: +x is right, +y is down.
        let inverted = event.isDirectionInvertedFromDevice
        travel.dx += inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        travel.dy += inverted ? event.scrollingDeltaY : -event.scrollingDeltaY

        let horizontal = abs(travel.dx), vertical = abs(travel.dy)
        let direction: Direction?
        if vertical >= Threshold.vertical, vertical >= horizontal * Threshold.dominance {
            direction = travel.dy > 0 ? .down : .up
        } else if horizontal >= Threshold.horizontal, horizontal >= vertical * Threshold.dominance {
            direction = travel.dx > 0 ? .right : .left
        } else {
            direction = nil
        }

        if direction != nil { hasFired = true }
        return direction
    }
}
