import AppKit

/// Shared builders so the panel's views stay visually consistent. Every colour and
/// size comes from the active theme — nothing here is hardcoded, which is what lets a
/// light theme like Frost work at all.
enum Style {
    static var theme: Theme { ThemeStore.active }

    static var primaryText: NSColor { theme.primaryText }
    static var secondaryText: NSColor { theme.secondaryText }
    static var tertiaryText: NSColor { theme.tertiaryText }
    static var accent: NSColor { theme.accent }
    static var controlFill: NSColor { theme.controlFill }

    static func scaled(_ size: CGFloat) -> CGFloat {
        (size * theme.typeScale * PanelSizes.typeScale).rounded()
    }

    private static var textShadow: NSShadow? {
        guard theme.usesTextShadow else { return nil }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        return shadow
    }

    static func label(
        _ text: String = "",
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor? = nil,
        monospaced: Bool = false
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        let pointSize = scaled(size)
        label.font = monospaced
            ? .monospacedSystemFont(ofSize: pointSize, weight: weight)
            : .systemFont(ofSize: pointSize, weight: weight)
        label.textColor = color ?? primaryText
        label.shadow = textShadow
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.alignment = .left
        return label
    }

    static func symbolImage(_ name: String, pointSize: CGFloat, description: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description ?? name)?
            .withSymbolConfiguration(.init(pointSize: scaled(pointSize), weight: .medium))
    }

    static func symbolButton(_ name: String, pointSize: CGFloat, target: AnyObject, action: Selector) -> NSButton {
        let button = ClickThroughButton(
            image: symbolImage(name, pointSize: pointSize) ?? NSImage(),
            target: target,
            action: action
        )
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.contentTintColor = primaryText
        button.shadow = textShadow
        return button
    }

    /// Capsule button that reads on glass without a hard border.
    static func pushButton(_ title: String, prominent: Bool, target: AnyObject, action: Selector) -> NSButton {
        let button = ClickThroughButton(title: title, target: target, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 11
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = prominent ? accent.cgColor : controlFill.cgColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: prominent ? theme.onAccentText : primaryText,
                .font: NSFont.systemFont(ofSize: scaled(12), weight: prominent ? .semibold : .medium)
            ]
        )
        button.heightAnchor.constraint(equalToConstant: scaled(22)).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
        return button
    }

    /// Small accent pill for counts, e.g. pending approvals.
    static func badge() -> NSTextField {
        let badge = NSTextField(labelWithString: "")
        badge.font = .systemFont(ofSize: scaled(10), weight: .bold)
        badge.textColor = theme.onAccentText
        badge.alignment = .center
        badge.wantsLayer = true
        badge.drawsBackground = true
        badge.backgroundColor = accent
        badge.layer?.cornerRadius = 7
        badge.layer?.masksToBounds = true
        badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return badge
    }

    static func roundedImageView(cornerRadius: CGFloat) -> NSImageView {
        let view = ClickThroughImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = controlFill.cgColor
        return view
    }
}

/// The panel never activates the app, so the first click on a control would otherwise
/// be swallowed just to focus the window. These accept it directly.
final class ClickThroughButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ClickThroughImageView: NSImageView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
