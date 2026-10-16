import AppKit

/// A tap from the Force Touch trackpad when something happens under your fingers: the
/// notch opening, a tab changing, a swipe landing. It is only felt while a finger is on
/// the trackpad, which is exactly when it means something.
enum Haptics {
    /// defaults write com.notchhover.NotchHover Haptics -bool false
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "Haptics") as? Bool ?? true
    }

    /// A light tick, for the panel opening or a tab being chosen.
    static func tick() {
        perform(.alignment)
    }

    /// A firmer step, for a gesture that did something — a track skipped, the panel closed.
    static func step() {
        perform(.levelChange)
    }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
