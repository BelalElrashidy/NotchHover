import AppKit

/// Every dimension the panel used to hardcode, now adjustable. Values are clamped on
/// read, so a bad stored number can never produce an unusable panel.
enum PanelSizes {
    enum Key {
        static let widthMode = "PanelWidthMode"      // "auto" | "fixed"
        static let width = "PanelWidth"
        static let height = "PanelHeight"
        static let restingWidthMode = "RestingWidthMode"
        static let restingWing = "RestingWing"
        static let restingExtraHeight = "RestingExtraHeight"
        static let cornerRadius = "PanelCornerRadius"
        static let flare = "PanelFlare"
        static let typeScale = "PanelTypeScale"
    }

    private static func value(_ key: String, default fallback: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        let stored = UserDefaults.standard.object(forKey: key) as? Double
        return Swift.min(upper, Swift.max(lower, CGFloat(stored ?? Double(fallback))))
    }

    static var usesAutomaticWidth: Bool {
        (UserDefaults.standard.string(forKey: Key.widthMode) ?? "auto") == "auto"
    }

    static var usesAutomaticRestingWidth: Bool {
        (UserDefaults.standard.string(forKey: Key.restingWidthMode) ?? "auto") == "auto"
    }

    /// Only consulted when the width mode is fixed.
    static var width: CGFloat { value(Key.width, default: 731, min: 420, max: 1400) }
    static var height: CGFloat { value(Key.height, default: 152, min: 110, max: 320) }
    static var restingWing: CGFloat { value(Key.restingWing, default: 30, min: 0, max: 200) }
    static var restingExtraHeight: CGFloat { value(Key.restingExtraHeight, default: 0, min: 0, max: 40) }
    static var cornerRadius: CGFloat { value(Key.cornerRadius, default: 34, min: 12, max: 48) }
    static var flare: CGFloat { value(Key.flare, default: 36, min: 0, max: 60) }
    static var typeScale: CGFloat { value(Key.typeScale, default: 1, min: 0.85, max: 1.3) }

    /// Width the widgets would like, used when the width mode is automatic.
    static func automaticWidth(for widgets: [PanelWidget], notchWidth: CGFloat) -> CGFloat {
        let content = widgets.reduce(0) { $0 + $1.idealWidth } + CGFloat(max(0, widgets.count - 1)) * 21
        return Swift.max(notchWidth + 320, content + flare * 2 + 24)
    }
}
