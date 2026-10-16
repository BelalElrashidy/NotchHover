import AppKit

/// Path math for the slab that grows out of the notch: flush with the top of the
/// screen, flaring outward at the top with inverted corners so it appears to come
/// from the menu bar, and rounded at the bottom.
enum NotchShape {
    static var topFlare: CGFloat { PanelSizes.flare }
    static var bottomRadius: CGFloat { PanelSizes.cornerRadius }
    /// The idle bar stays tighter so it reads as part of the notch.
    static var idleBottomRadius: CGFloat { min(20, PanelSizes.cornerRadius * 0.6) }

    /// The flare actually used for a given rect — clamped so it can never exceed
    /// the shape it is cut into.
    static func flare(in rect: CGRect) -> CGFloat {
        max(0, min(topFlare, rect.width / 2, rect.height * 0.55))
    }

    /// Traced from the top-left flare, down the left side, across the rounded
    /// bottom, and back up to the top-right flare.
    static func path(in rect: CGRect, bottomRadius: CGFloat = bottomRadius) -> CGPath {
        let flare = flare(in: rect)
        // Leave room for the flare and for the wider footprint of a continuous corner.
        let radius = max(0, min(bottomRadius, (rect.height - flare) / 1.35, (rect.width / 2 - flare) / 1.35))
        let maxX = rect.maxX
        let maxY = rect.maxY

        let path = CGMutablePath()
        // A circular fillet, not a quad curve: the concave corner stays perfectly
        // round as the flare grows.
        path.move(to: CGPoint(x: rect.minX, y: maxY))
        path.addArc(
            center: CGPoint(x: rect.minX, y: maxY - flare),
            radius: flare,
            startAngle: .pi / 2,
            endAngle: 0,
            clockwise: true
        )
        // Continuous ("squircle") corners rather than circular arcs: a plain arc
        // meets the straight edge abruptly, which reads as a hard corner.
        let span = radius * 1.35
        let grip = span * 0.36

        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.minY + span))
        path.addCurve(
            to: CGPoint(x: rect.minX + flare + span, y: rect.minY),
            control1: CGPoint(x: rect.minX + flare, y: rect.minY + grip),
            control2: CGPoint(x: rect.minX + flare + grip, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: maxX - flare - span, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: maxX - flare, y: rect.minY + span),
            control1: CGPoint(x: maxX - flare - grip, y: rect.minY),
            control2: CGPoint(x: maxX - flare, y: rect.minY + grip)
        )
        path.addLine(to: CGPoint(x: maxX - flare, y: maxY - flare))
        path.addArc(
            center: CGPoint(x: maxX, y: maxY - flare),
            radius: flare,
            startAngle: .pi,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
