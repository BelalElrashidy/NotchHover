import AppKit

/// Every colour and size the panel draws with. Views read the active theme instead
/// of hardcoding values, so a new look is a new `Theme` rather than edits scattered
/// across every pane.
struct Theme {
    enum Surface: Equatable {
        /// Painted with a solid colour, which may itself be translucent.
        case solid(NSColor)
        /// Liquid Glass, so the desktop shows through.
        case glass
    }

    let id: String
    let name: String
    let summary: String
    let surface: Surface
    let primaryText: NSColor
    let secondaryText: NSColor
    let tertiaryText: NSColor
    let accent: NSColor
    /// Background for capsule buttons and placeholder tiles.
    let controlFill: NSColor
    let bottomRadius: CGFloat
    /// Multiplies every font and symbol size.
    let typeScale: CGFloat
    /// Light text over an unpredictable backdrop needs a shadow; dark text on a light
    /// panel does not.
    let usesTextShadow: Bool
    /// Recolours the surface from the album art of whatever is playing.
    let followsArtwork: Bool

    static let midnight = Theme(
        id: "midnight",
        name: "Midnight",
        summary: "Pure black, blue accent",
        surface: .solid(.black),
        primaryText: .white,
        secondaryText: NSColor.white.withAlphaComponent(0.66),
        tertiaryText: NSColor.white.withAlphaComponent(0.45),
        accent: NSColor(srgbRed: 0.29, green: 0.56, blue: 1, alpha: 1),
        controlFill: NSColor.white.withAlphaComponent(0.16),
        bottomRadius: 34,
        typeScale: 1,
        usesTextShadow: true,
        followsArtwork: false
    )

    static let graphite = Theme(
        id: "graphite",
        name: "Graphite",
        summary: "Warm charcoal, clay accent",
        surface: .solid(NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.98)),
        primaryText: NSColor(srgbRed: 0.95, green: 0.94, blue: 0.92, alpha: 1),
        secondaryText: NSColor(srgbRed: 0.62, green: 0.61, blue: 0.58, alpha: 1),
        tertiaryText: NSColor(srgbRed: 0.45, green: 0.44, blue: 0.42, alpha: 1),
        accent: NSColor(srgbRed: 0.85, green: 0.35, blue: 0.19, alpha: 1),
        controlFill: NSColor.white.withAlphaComponent(0.14),
        bottomRadius: 34,
        typeScale: 1,
        usesTextShadow: true,
        followsArtwork: false
    )

    static let frost = Theme(
        id: "frost",
        name: "Frost",
        summary: "Light panel, dark text",
        surface: .solid(NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 0.97)),
        primaryText: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.16, alpha: 1),
        secondaryText: NSColor(srgbRed: 0.44, green: 0.43, blue: 0.41, alpha: 1),
        tertiaryText: NSColor(srgbRed: 0.60, green: 0.60, blue: 0.57, alpha: 1),
        accent: NSColor(srgbRed: 0.09, green: 0.37, blue: 0.65, alpha: 1),
        controlFill: NSColor.black.withAlphaComponent(0.08),
        bottomRadius: 34,
        typeScale: 1,
        usesTextShadow: false,
        followsArtwork: false
    )

    static let clearGlass = Theme(
        id: "glass",
        name: "Clear glass",
        summary: "Desktop shows through",
        surface: .glass,
        primaryText: .white,
        secondaryText: NSColor.white.withAlphaComponent(0.7),
        tertiaryText: NSColor.white.withAlphaComponent(0.5),
        accent: NSColor(srgbRed: 0.71, green: 0.83, blue: 0.96, alpha: 1),
        controlFill: NSColor.white.withAlphaComponent(0.2),
        bottomRadius: 34,
        typeScale: 1,
        usesTextShadow: true,
        followsArtwork: false
    )

    static let artworkTint = Theme(
        id: "artwork",
        name: "Artwork tint",
        summary: "Colour follows album art",
        surface: .solid(NSColor(srgbRed: 0.14, green: 0.10, blue: 0.18, alpha: 1)),
        primaryText: .white,
        secondaryText: NSColor.white.withAlphaComponent(0.7),
        tertiaryText: NSColor.white.withAlphaComponent(0.5),
        accent: NSColor(srgbRed: 0.79, green: 0.55, blue: 0.86, alpha: 1),
        controlFill: NSColor.white.withAlphaComponent(0.18),
        bottomRadius: 34,
        typeScale: 1,
        usesTextShadow: true,
        followsArtwork: true
    )

    static let highContrast = Theme(
        id: "contrast",
        name: "High contrast",
        summary: "Bigger text, amber accent",
        surface: .solid(.black),
        primaryText: .white,
        secondaryText: NSColor.white.withAlphaComponent(0.8),
        tertiaryText: NSColor.white.withAlphaComponent(0.6),
        accent: NSColor(srgbRed: 0.94, green: 0.62, blue: 0.15, alpha: 1),
        controlFill: NSColor.white.withAlphaComponent(0.22),
        bottomRadius: 30,
        typeScale: 1.15,
        usesTextShadow: true,
        followsArtwork: false
    )

    static let all: [Theme] = [midnight, graphite, frost, clearGlass, artworkTint, highContrast]

    /// Whether the surface is light enough to need dark system controls.
    var isLightSurface: Bool {
        guard case .solid(let color) = surface,
              let converted = color.usingColorSpace(.sRGB) else { return false }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6
    }

    /// Settings window background: the panel colour, lifted slightly so panes read
    /// as sitting on top of it.
    var windowBackground: NSColor {
        switch surface {
        case .solid(let color):
            let base = color.withAlphaComponent(1)
            return isLightSurface
                ? base.blended(withFraction: 0.35, of: .white) ?? base
                : base.blended(withFraction: 0.10, of: .white) ?? base
        case .glass:
            return NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        }
    }

    /// Slightly raised surface for sidebars and grouped rows.
    var elevatedBackground: NSColor {
        isLightSurface
            ? (windowBackground.blended(withFraction: 0.5, of: .white) ?? windowBackground)
            : (windowBackground.blended(withFraction: 0.06, of: .white) ?? windowBackground)
    }

    var appearance: NSAppearance? {
        NSAppearance(named: isLightSurface ? .aqua : .darkAqua)
    }

    /// Readable text on top of `accent`, picked from the accent's luminance.
    /// Note `getWhite` is not valid on an sRGB colour — it needs a grayscale space —
    /// so this reads the components directly.
    var onAccentText: NSColor {
        guard let converted = accent.usingColorSpace(.sRGB) else { return .white }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1) : .white
    }
}

/// Which theme is active, plus the artwork colour when a theme follows it.
enum ThemeStore {
    static let defaultsKey = "Theme"

    /// Set from the current album art; only themes with `followsArtwork` use it.
    static var artworkColor: NSColor?

    /// Forces a theme for offscreen previews, leaving the stored setting alone.
    static var override: Theme?

    static var selected: Theme {
        if let override { return override }
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
            // Carried over from when the setting was Black/Glass.
            ?? (UserDefaults.standard.string(forKey: "Material") == "glass" ? Theme.clearGlass.id : nil)
        return Theme.all.first { $0.id == stored } ?? .midnight
    }

    /// The theme as drawn: identical to `selected`, except the artwork theme swaps in
    /// the colour pulled from the current cover.
    static var active: Theme {
        let theme = selected
        guard theme.followsArtwork, let artworkColor else { return theme }
        return Theme(
            id: theme.id,
            name: theme.name,
            summary: theme.summary,
            surface: .solid(artworkColor),
            primaryText: theme.primaryText,
            secondaryText: theme.secondaryText,
            tertiaryText: theme.tertiaryText,
            accent: artworkColor.notchAccentVariant,
            controlFill: theme.controlFill,
            bottomRadius: theme.bottomRadius,
            typeScale: theme.typeScale,
            usesTextShadow: theme.usesTextShadow,
            followsArtwork: true
        )
    }
}
