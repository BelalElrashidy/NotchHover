import AppKit

/// How the resting bar breathes: one beat, shared by the slab's shape and by the
/// content sitting on it, so the whole bar rises and falls together rather than only
/// its edges creeping in and out.
enum NotchBreath {
    /// How much wider the bar gets at the top of a breath, on each side. The breath is
    /// mostly sideways: the bar hangs off the bottom of the menu bar, so height that
    /// comes and goes reads as the notch growing rather than as breathing.
    static let widen: CGFloat = 12
    /// And how much deeper — just enough that the bottom edge is not perfectly still.
    static let drop: CGFloat = 1
    /// What the content does over the same beat.
    static let contentScale: CGFloat = 1.05
    /// Half a cycle — around twenty breaths a minute.
    static let halfCycle: CFTimeInterval = 1.5
    /// How many breaths an event is worth. The bar is still the rest of the time: a
    /// permanent animation stops meaning anything, and a notch that never sits still
    /// is just something moving at the top of the screen.
    static let cycles = 2

    /// Rising and falling a set number of times, then done. Everything that breathes is
    /// started by the card in the same turn of the run loop, so they share a phase
    /// without pinning one: a breath that joined mid-phase would jump to meet it.
    static func configure(_ animation: CABasicAnimation, cycles: Int) {
        animation.duration = halfCycle
        animation.autoreverses = true
        animation.repeatCount = Float(cycles)
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    }

    /// Wall-clock length of a burst, out and back each time.
    static func duration(cycles: Int) -> TimeInterval {
        halfCycle * 2 * Double(cycles)
    }
}

/// The panel's surface, masked to the notch slab shape.
///
/// The material is only ever a *backdrop*: content lives in `contentContainer`, a
/// plain sibling on top, laid out identically whichever material is in use. Glass
/// used to adopt the content as its own `contentView`, which let it re-parent and
/// re-lay-out everything — so switching material changed the whole panel instead of
/// just what was behind it.
final class GlassCardView: NSView {
    /// Add panel content here.
    let contentContainer = NSView()

    var bottomRadius: CGFloat {
        didSet { needsLayout = true }
    }

    /// Offscreen previews cannot capture a live glass effect, so they opt out.
    static var usesLiveGlass = true

    /// Which theme this card was built with, so the panel is only rebuilt on a real change.
    let themeID: String

    private let maskLayer = CAShapeLayer()
    private let slabLayer = CAShapeLayer()
    private var backdropView: NSView?
    private let tintView = NSView()

    /// The part of the card the slab currently occupies. The card itself always spans
    /// the whole panel; only this rect changes, so the shape can grow and shrink from
    /// its own centre instead of being dragged around by an animating frame.
    private(set) var shapeRect: CGRect = .zero

    /// Breaths still owed. A burst is a reaction to something happening, so it is
    /// always a finite number of them, and the shape is still in between.
    private var breathCycles = 0

    private var breathWorkItem: DispatchWorkItem?

    /// When the morph currently running will land. A breath added on top of a running
    /// transition would win — both animate `path`, and the later one is what is drawn —
    /// so the shape would snap to its final size and start breathing there.
    private var transitionEndsAt: CFTimeInterval = 0

    /// Told how many breaths the shape is about to take — zero when it stops — so the
    /// content on the bar can rise and fall with it rather than sit still inside a
    /// moving slab.
    var onBreath: ((Int) -> Void)?

    init(frame frameRect: NSRect, bottomRadius: CGFloat = NotchShape.bottomRadius) {
        self.bottomRadius = bottomRadius
        let theme = ThemeStore.active
        self.themeID = ThemeStore.signature
        super.init(frame: frameRect)

        wantsLayer = true

        if theme.surface == .glass, Self.usesLiveGlass {
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: bounds)
                glass.autoresizingMask = [.width, .height]
                // The mask supplies the shape, so the glass stays a plain rectangle.
                glass.cornerRadius = 0
                glass.style = ThemeTweaks.glassFrosted ? .regular : .clear
                addSubview(glass)
                backdropView = glass
                Log.ui.notice("Surface: clear glass")
            } else {
                let effect = NSVisualEffectView(frame: bounds)
                effect.autoresizingMask = [.width, .height]
                effect.material = .underWindowBackground
                effect.blendingMode = .behindWindow
                effect.state = .active
                addSubview(effect)
                backdropView = effect
                Log.ui.notice("Surface: visual effect fallback")
            }
        } else {
            if case .solid(let color) = theme.surface {
                slabLayer.fillColor = color.cgColor
            } else {
                // Preview mode renders glass themes as a flat stand-in, light enough
                // that the tint over it still shows.
                slabLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
            }
            layer?.addSublayer(slabLayer)
            Log.ui.notice("Surface: \(theme.name, privacy: .public)")
        }

        // The glass's tint: a dark wash between it and the content, so a bright or busy
        // desktop can be toned down until the panel reads.
        if theme.surface == .glass {
            tintView.wantsLayer = true
            tintView.frame = bounds
            tintView.autoresizingMask = [.width, .height]
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(ThemeTweaks.glassTint).cgColor
            addSubview(tintView)
        }

        // Always a sibling on top of the backdrop, never owned by it.
        contentContainer.wantsLayer = true
        contentContainer.frame = bounds.insetBy(dx: NotchShape.flare(in: bounds), dy: 0)
        addSubview(contentContainer)

        layer?.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Opacity, tint and blur changed in Settings, applied to the panel as it is.
    func applyTweaks() {
        let theme = ThemeStore.active
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        if case .solid(let color) = theme.surface, slabLayer.superlayer != nil {
            slabLayer.fillColor = color.cgColor
        }
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(ThemeTweaks.glassTint).cgColor
        CATransaction.commit()
        if #available(macOS 26.0, *), let glass = backdropView as? NSGlassEffectView {
            glass.style = ThemeTweaks.glassFrosted ? .regular : .clear
        }
    }

    /// Live recolour for the artwork theme, without rebuilding the panel.
    func applySurfaceTint(_ color: NSColor) {
        guard slabLayer.superlayer != nil else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        // At the opacity you chose for the theme, whatever the artwork's colour.
        slabLayer.fillColor = color.withAlphaComponent(ThemeTweaks.opacity(for: ThemeStore.selected)).cgColor
        CATransaction.commit()
    }

    /// Morphs the slab to a new rect. Both the painted surface and the clipping mask
    /// animate the same path, so content is revealed outward from the middle as the
    /// shape grows, and swallowed back into it as the shape shrinks.
    func animateShape(to rect: CGRect, bottomRadius radius: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        shapeRect = rect
        bottomRadius = radius
        // A breath left running would fight the transition: both animate `path`, and
        // the breath's endpoints belong to the shape we are leaving.
        stopBreathing()
        transitionEndsAt = CACurrentMediaTime() + duration
        let target = NotchShape.path(in: rect, bottomRadius: radius)

        for layer in [maskLayer, slabLayer] {
            // Start from what is on screen now, so reversing mid-animation never jumps.
            let current = layer.presentation()?.path ?? layer.path ?? target

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.path = target
            CATransaction.commit()

            guard duration > 0 else {
                layer.removeAnimation(forKey: "shape")
                continue
            }

            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = current
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: "shape")
        }

        if breathCycles > 0 { scheduleBreath(after: duration) }
    }

    /// Grows the shape past its target and lets it settle back — what a notification
    /// or a volume change does to the resting bar. Reuses the same two layers as every
    /// other transition, so it starts from whatever is on screen.
    func popShape(
        to rect: CGRect,
        bottomRadius radius: CGFloat,
        overshoot: CGFloat,
        duration: CFTimeInterval
    ) {
        shapeRect = rect
        bottomRadius = radius
        stopBreathing()
        transitionEndsAt = CACurrentMediaTime() + duration

        let target = NotchShape.path(in: rect, bottomRadius: radius)
        // Wider on both sides and a little deeper, with the top edge pinned to the
        // screen: the bar bulges out of the notch rather than drifting down it.
        let past = NotchShape.path(
            in: CGRect(
                x: rect.minX - overshoot,
                y: rect.minY - overshoot * 0.35,
                width: rect.width + overshoot * 2,
                height: rect.height + overshoot * 0.35
            ),
            bottomRadius: radius
        )

        for layer in [maskLayer, slabLayer] {
            let current = layer.presentation()?.path ?? layer.path ?? target

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.path = target
            CATransaction.commit()

            guard duration > 0 else {
                layer.removeAnimation(forKey: "shape")
                continue
            }

            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = [current, past, target]
            // Most of the time goes into the overshoot, so the settle reads as a
            // settle rather than as a second, separate movement.
            animation.keyTimes = [0, 0.62, 1]
            animation.duration = duration
            animation.timingFunctions = [
                CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1),
                CAMediaTimingFunction(name: .easeInEaseOut)
            ]
            layer.add(animation, forKey: "shape")
        }

        if breathCycles > 0 { scheduleBreath(after: duration) }
    }

    // MARK: - Breathing

    /// Takes a few breaths because something happened. A burst asked for mid-morph
    /// waits for the shape to land rather than fighting it.
    func breathe(cycles: Int = NotchBreath.cycles) {
        breathCycles = max(1, cycles)
        scheduleBreath(after: max(0, transitionEndsAt - CACurrentMediaTime()))
    }

    /// Drops a burst entirely — the bar is on its way to being something other than a
    /// resting bar, and a breath would be animating a shape nobody is looking at.
    func cancelBreathing() {
        breathCycles = 0
        stopBreathing()
    }

    private func scheduleBreath(after delay: TimeInterval) {
        breathWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.breathWorkItem = nil
            self?.startBreathing()
        }
        breathWorkItem = work
        // A transition owns the shape until it is done; the breath picks up after it.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.02, execute: work)
    }

    private func startBreathing() {
        guard breathCycles > 0, shapeRect != .zero else { return }
        let cycles = breathCycles
        onBreath?(cycles)

        let rest = NotchShape.path(in: shapeRect, bottomRadius: bottomRadius)
        let full = NotchShape.path(
            in: CGRect(
                x: shapeRect.minX - NotchBreath.widen,
                y: shapeRect.minY - NotchBreath.drop,
                width: shapeRect.width + NotchBreath.widen * 2,
                height: shapeRect.height + NotchBreath.drop
            ),
            bottomRadius: bottomRadius
        )

        for layer in [maskLayer, slabLayer] {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = rest
            animation.toValue = full
            NotchBreath.configure(animation, cycles: cycles)
            layer.add(animation, forKey: "breath")
        }

        // The burst ends by itself; forgetting it here is what keeps the next
        // transition from treating it as still owed and starting it again.
        let done = DispatchWorkItem { [weak self] in
            self?.breathWorkItem = nil
            self?.breathCycles = 0
        }
        breathWorkItem = done
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchBreath.duration(cycles: cycles), execute: done)
    }

    private func stopBreathing() {
        breathWorkItem?.cancel()
        breathWorkItem = nil
        [maskLayer, slabLayer].forEach { $0.removeAnimation(forKey: "breath") }
        onBreath?(0)
    }

    /// Where the slab is actually drawn right now, mid-animation included.
    var presentedShapeBounds: CGRect? {
        maskLayer.presentation()?.path?.boundingBoxOfPath ?? maskLayer.path?.boundingBoxOfPath
    }

    override func layout() {
        super.layout()
        if shapeRect == .zero {
            shapeRect = bounds
        }

        // Frames only. The path is owned by animateShape, and resetting it here is
        // exactly what used to snap the slab to full size mid-animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        slabLayer.frame = bounds
        if maskLayer.path == nil {
            let path = NotchShape.path(in: shapeRect, bottomRadius: bottomRadius)
            maskLayer.path = path
            slabLayer.path = path
        }
        backdropView?.frame = bounds
        contentContainer.frame = bounds.insetBy(dx: NotchShape.flare(in: bounds), dy: 0)
        CATransaction.commit()
    }
}
