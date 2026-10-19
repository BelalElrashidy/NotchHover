import AppKit

/// The resting state that hugs the notch: artwork on one side, a level meter on the
/// other, and nothing taller than the notch itself.
///
/// The bar it draws into is only as wide as the slab behind it — everything outside
/// that is masked away — so layout is done against `barWidth`, not the view's own
/// bounds, and an activity reports the width it needs before it is shown.
final class IdleActivityView: NSView {
    private let artworkView = Style.roundedImageView(cornerRadius: 6)
    private let meter = LevelMeterView()
    private let activityIcon = NSImageView()
    private let levelBar = ProgressBarView()
    private let levelLabel = Style.label("", size: 11, weight: .semibold)

    private let notchWidth: CGFloat
    private let bandHeight: CGFloat

    /// How wide the slab behind this content currently is. Content is laid out inside
    /// it, so nothing is ever drawn where the mask would cut it off.
    var barWidth: CGFloat = 0 {
        didSet {
            guard barWidth != oldValue else { return }
            needsLayout = true
        }
    }

    private enum Layout {
        static let artworkSize: CGFloat = 24
        static let meterSize = CGSize(width: 18, height: 13)
        /// Gap between the notch edge and the content beside it.
        static let notchGap: CGFloat = 10
        /// Clearance between content and the slab's curved bottom corner.
        static let edgeInset: CGFloat = 16
        static let levelBarWidth: CGFloat = 54
        /// Every activity gets the same slot, whatever it has to say — so a banner and
        /// a volume change produce exactly the same bar, and a long title is cut.
        static let activitySlot: CGFloat = 54
    }

    init(notchWidth: CGFloat, bandHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.bandHeight = bandHeight
        super.init(frame: .zero)

        [artworkView, activityIcon, meter, levelBar, levelLabel].forEach(addSubview)
        activityIcon.contentTintColor = Style.primaryText
        activityIcon.imageScaling = .scaleProportionallyUpOrDown
        levelLabel.alignment = .center
        levelLabel.lineBreakMode = .byTruncatingTail
        setActivityHidden(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Purely something to look at. This view spans the whole card and sits above the
    /// panel's content, and while the panel is open it is only faded out — which AppKit
    /// does not count when hit-testing. Left alone it swallowed every click in the open
    /// panel, which is why the notes editor could never be clicked into.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()

        let notchLeft = (bounds.width - notchWidth) / 2
        let notchRight = notchLeft + notchWidth
        let bandMidY = bounds.height - bandHeight / 2
        // The straight body of the slab, minus the room its corner curves need.
        // `barWidth` is that body; like everything else it is centred on the notch.
        let body = max(barWidth, notchWidth)
        let barLeft = (bounds.width - body) / 2 + Layout.edgeInset
        let barRight = (bounds.width + body) / 2 - Layout.edgeInset

        // Now playing hugs the notch: its bar is only as wide as that content.
        artworkView.frame = CGRect(
            x: notchLeft - Layout.notchGap - Layout.artworkSize,
            y: bandMidY - Layout.artworkSize / 2,
            width: Layout.artworkSize,
            height: Layout.artworkSize
        )

        meter.frame = CGRect(
            x: notchRight + Layout.notchGap,
            y: bandMidY - Layout.meterSize.height / 2,
            width: Layout.meterSize.width,
            height: Layout.meterSize.height
        )

        // An activity can make the bar much wider than its own content on one side —
        // the shape has to stay centred on the notch — so each side centres what it
        // holds inside its own half rather than crowding the notch.
        let leftSlot = CGRect(
            x: barLeft,
            y: bandMidY - Layout.artworkSize / 2,
            width: max(0, notchLeft - Layout.notchGap - barLeft),
            height: Layout.artworkSize
        )
        let rightSlot = CGRect(
            x: notchRight + Layout.notchGap,
            y: 0,
            width: max(0, barRight - notchRight - Layout.notchGap),
            height: bandHeight
        )

        activityIcon.frame = CGRect(
            x: leftSlot.midX - Layout.artworkSize / 2,
            y: leftSlot.minY,
            width: Layout.artworkSize,
            height: Layout.artworkSize
        )
        let levelBarWidth = min(rightSlot.width, Layout.levelBarWidth)
        levelBar.frame = CGRect(
            x: rightSlot.midX - levelBarWidth / 2,
            y: bandMidY - 2,
            width: levelBarWidth,
            height: 4
        )
        levelLabel.frame = CGRect(
            x: rightSlot.minX,
            y: bandMidY - 8,
            width: rightSlot.width,
            height: 16
        )
    }

    /// Shows a system event in place of the now-playing content for a moment, and
    /// reports how wide the bar has to be for all of it to fit.
    @discardableResult
    func showActivity(_ activity: LiveActivity) -> CGFloat {
        setActivityHidden(false)
        activityIcon.contentTintColor = Style.primaryText

        switch activity {
        case .volume(let level, let muted):
            activityIcon.image = Style.symbolImage(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", pointSize: 15)
            levelBar.fraction = muted ? 0 : level
            levelBar.isHidden = false
            levelLabel.isHidden = true
        case .brightness(let level):
            activityIcon.image = Style.symbolImage("sun.max.fill", pointSize: 15)
            levelBar.fraction = level
            levelBar.isHidden = false
            levelLabel.isHidden = true
        case .keyboardBacklight(let level):
            activityIcon.image = Style.symbolImage("keyboard.fill", pointSize: 15)
            levelBar.fraction = level
            levelBar.isHidden = false
            levelLabel.isHidden = true
        case .battery(let percent, let charging):
            activityIcon.image = Style.symbolImage(charging ? "battery.100.bolt" : "battery.75", pointSize: 15)
            levelLabel.stringValue = "\(percent)%"
            levelLabel.isHidden = false
            levelBar.isHidden = true
        case .notification(let app, let title):
            activityIcon.image = icon(forAppNamed: app)
            levelLabel.stringValue = title
            levelLabel.isHidden = false
            levelBar.isHidden = true
        case .device(let device):
            // The icon says which; the slot only has room for the lowest level.
            activityIcon.image = Style.symbolImage(device.kind.symbol, pointSize: 15)
            levelLabel.stringValue = device.lowest.map { "\($0)%" } ?? device.caseLevel.map { "\($0)%" } ?? ""
            levelLabel.isHidden = false
            levelBar.isHidden = true
        case let .status(symbol, text):
            activityIcon.image = Style.symbolImage(symbol, pointSize: 15)
            levelLabel.stringValue = text
            levelLabel.isHidden = false
            levelBar.isHidden = true
        case .claudeDone(let project):
            // Claude's own icon when the app is installed; the project is the label.
            activityIcon.image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
                .map { url -> NSImage in
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: Layout.artworkSize, height: Layout.artworkSize)
                    return icon
                } ?? Style.symbolImage("checkmark.circle.fill", pointSize: 15)
            levelLabel.stringValue = project
            levelLabel.isHidden = false
            levelBar.isHidden = true
        case .meeting(let title):
            activityIcon.image = Style.symbolImage("video.fill", pointSize: 15)
            activityIcon.contentTintColor = Style.accent
            levelLabel.stringValue = title
            levelLabel.isHidden = false
            levelBar.isHidden = true
        case .timer(let remaining):
            activityIcon.image = Style.symbolImage("timer", pointSize: 15)
            levelLabel.stringValue = remaining > 0 ? CountdownTimer.format(remaining) : "Time's up"
            levelLabel.isHidden = false
            levelBar.isHidden = true
        }

        return requiredBarWidth
    }

    /// One size for every activity: the notch, the icon on one side, the same slot on
    /// the other. A bar that resized itself per event meant a notification threw the
    /// notch open to nearly the width of the whole panel, and no two events looked
    /// alike. Anything too long for the slot is truncated instead.
    var requiredBarWidth: CGFloat {
        let side = max(Layout.artworkSize, Layout.activitySlot) + Layout.notchGap + Layout.edgeInset
        // Symmetric: the shape grows out of the notch evenly on both sides.
        return notchWidth + side * 2
    }

    /// Best-effort match from a banner's app name to its icon on disk.
    private func icon(forAppNamed name: String) -> NSImage {
        let fallback = Style.symbolImage("bell.fill", pointSize: 15) ?? NSImage()
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier(forAppNamed: name)) else {
            return fallback
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: Layout.artworkSize, height: Layout.artworkSize)
        return icon
    }

    /// Best-effort match from a banner's app name to an installed app, for its icon.
    private func bundleIdentifier(forAppNamed name: String) -> String {
        for directory in ["/Applications", "/System/Applications", "/Applications/Utilities"] {
            let path = "\(directory)/\(name).app"
            guard FileManager.default.fileExists(atPath: path),
                  let bundle = Bundle(path: path),
                  let identifier = bundle.bundleIdentifier else { continue }
            return identifier
        }
        return ""
    }

    func clearActivity() {
        setActivityHidden(true)
    }

    /// The meter, for the self-test.
    var levelMeter: LevelMeterView { meter }

    /// The content's half of the breath, started by the card so the two share a phase:
    /// artwork and meter swell and settle while the slab around them does the same.
    /// Zero cycles stops it.
    func breathe(cycles: Int) {
        let breathers = [artworkView, meter]
        guard cycles > 0 else {
            breathers.forEach { $0.layer?.removeAnimation(forKey: "breath") }
            return
        }

        for view in breathers {
            view.wantsLayer = true
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 1
            animation.toValue = NotchBreath.contentScale
            NotchBreath.configure(animation, cycles: cycles)
            view.layer?.add(animation, forKey: "breath")
        }
    }

    private func setActivityHidden(_ hidden: Bool) {
        activityIcon.isHidden = hidden
        levelBar.isHidden = hidden
        levelLabel.isHidden = hidden
        artworkView.isHidden = hidden == false
        meter.isHidden = hidden == false
    }

    /// `artwork` is nil when something is playing that we cannot name — a video in a
    /// browser, say — so the slot falls back to a generic glyph rather than a hole.
    func update(artwork: NSImage?, isPlaying: Bool) {
        if let artwork {
            artworkView.image = artwork
            artworkView.contentTintColor = nil
            artworkView.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            artworkView.image = isPlaying ? Style.symbolImage("waveform", pointSize: 14) : nil
            artworkView.contentTintColor = isPlaying ? Style.primaryText : nil
            artworkView.layer?.backgroundColor = isPlaying
                ? NSColor.clear.cgColor
                : Style.controlFill.cgColor
        }
        meter.isRunning = isPlaying
        meter.alphaValue = isPlaying ? 1 : 0.35
    }
}

/// Bars beside the notch that move while something plays — Boring Notch's and the
/// Dynamic Island's way of saying "this is live": thin rounded bars, centred on the
/// band, each easing to a new height several times a second. Paused, they rest as dots.
///
/// With the live visualizer on, `AudioLevels` drives them from the sound itself; the
/// animation is what they do otherwise.
final class LevelMeterView: NSView {
    enum Kind {
        /// Four bars in the artwork's colour.
        case music
        /// Five red bars that flicker like speech: an app has the microphone.
        case recording

        var barCount: Int { self == .music ? 4 : 5 }
        /// Seconds between new heights. Speech moves faster than a song's beat.
        var step: TimeInterval { self == .music ? 0.24 : 0.13 }
    }

    var kind: Kind = .music {
        didSet {
            guard kind != oldValue else { return }
            rebuildBars()
        }
    }

    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            isRunning ? startAnimating() : stopAnimating()
        }
    }

    private var bars: [CALayer] = []

    /// The artwork's colour; nil for the theme's text colour. A recording is always red.
    var tint: NSColor? {
        didSet { applyColour() }
    }

    /// A bar at rest: just its own width, so it reads as a dot.
    private var restingScale: CGFloat {
        guard bounds.height > 0 else { return 0.2 }
        return min(1, barWidth / bounds.height)
    }

    private var barWidth: CGFloat {
        let count = CGFloat(kind.barCount)
        // Bars and gaps in the ratio 5:4, filling the width the meter was given.
        return max(2, floor(bounds.width / (count + (count - 1) * 0.8) * 2) / 2)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        rebuildBars()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuildBars() {
        bars.forEach { $0.removeFromSuperlayer() }
        bars = (0..<kind.barCount).map { _ in
            let bar = CALayer()
            // Centred, so a bar grows up and down at once, like the Dynamic Island's.
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            return bar
        }
        applyColour()
        needsLayout = true
        if isRunning { startAnimating() } else { rest(animated: false) }
    }

    private func applyColour() {
        let colour = kind == .recording ? NSColor.systemRed : (tint ?? Style.primaryText)
        bars.forEach { $0.backgroundColor = colour.cgColor }
    }

    override func layout() {
        super.layout()
        let width = barWidth
        let count = CGFloat(bars.count)
        let gap = count > 1 ? (bounds.width - width * count) / (count - 1) : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: width / 2 + CGFloat(index) * (width + gap), y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
        if isRunning == false { rest(animated: false) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // No window, nothing to draw: the timer stops rather than ticking for nobody.
        if window == nil { timer?.invalidate(); timer = nil } else if isRunning { startAnimating() }
    }

    // MARK: - Live levels

    /// Real levels — low, middle, high — from `AudioLevels`. While they come, the bars
    /// follow the sound; nil hands them back to the animation.
    private var liveLevels: [Float]?

    func setLevels(_ levels: [Float]?) {
        let wasLive = liveLevels != nil
        liveLevels = levels
        guard let levels else {
            if wasLive, isRunning { startAnimating() }
            return
        }
        if wasLive == false { timer?.invalidate(); timer = nil }
        // Bass in the middle, where the bars are tallest; the edges carry the highs.
        let spread: [Float] = bars.count == 4
            ? [levels[1], levels[0], levels[0] * 0.85 + levels[1] * 0.15, levels[2]]
            : [levels[2], levels[1], levels[0], levels[1], levels[2]]
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0 / 30)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (bar, level) in zip(bars, spread) {
            bar.removeAnimation(forKey: "bounce")
            bar.transform = CATransform3DMakeScale(1, scale(for: isRunning ? CGFloat(level) : 0), 1)
        }
        CATransaction.commit()
    }

    // MARK: - Animation

    private var timer: Timer?
    /// A slow swell under the per-bar jitter, so the bars rise and fall together the
    /// way music does, rather than each doing its own thing.
    private var energy: CGFloat = 0.6

    private func scale(for level: CGFloat) -> CGFloat {
        restingScale + (1 - restingScale) * min(1, max(0, level))
    }

    private func startAnimating() {
        guard liveLevels == nil, window != nil else { return }
        timer?.invalidate()
        step()
        let timer = Timer(timeInterval: kind.step, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
        rest(animated: true)
    }

    /// Every bar to its dot.
    private func rest(animated: Bool) {
        for bar in bars {
            move(bar, to: restingScale, duration: animated ? 0.35 : 0)
        }
    }

    private func step() {
        // Hidden or faded out: nothing to see, so nothing to compute.
        guard isHiddenOrHasHiddenAncestor == false, alphaValue > 0.01 else { return }
        energy = min(1, max(0.35, energy + CGFloat.random(in: -0.18...0.18)))
        let count = bars.count
        for (index, bar) in bars.enumerated() {
            // Middle bars reach higher than the outer ones.
            let fromCentre = abs(CGFloat(index) - CGFloat(count - 1) / 2) / (CGFloat(count) / 2)
            let ceiling = 1 - fromCentre * 0.35
            let level: CGFloat
            switch kind {
            case .music:
                // Each bar anywhere from a quarter to full height; the swell lifts or
                // lowers them all a little, so loud passages read as loud.
                level = ceiling * (0.72 + 0.28 * energy) * CGFloat.random(in: 0.22...1)
            case .recording:
                // Speech: mostly low, with sudden peaks, and the odd silence.
                level = Bool.random() && Int.random(in: 0..<5) == 0 ? 0.08 : ceiling * pow(CGFloat.random(in: 0.15...1), 1.6)
            }
            move(bar, to: scale(for: level), duration: kind.step * 1.15)
        }
    }

    /// Eases from wherever the bar is drawn right now, so a new height never jumps.
    private func move(_ bar: CALayer, to target: CGFloat, duration: TimeInterval) {
        let current = (bar.presentation() ?? bar).transform.m22
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.transform = CATransform3DMakeScale(1, target, 1)
        CATransaction.commit()
        guard duration > 0 else {
            bar.removeAnimation(forKey: "bounce")
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = current
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bar.add(animation, forKey: "bounce")
    }

    /// Each bar's drawn height right now, as a fraction of its full height — for the
    /// self-test, which has to see the bars move rather than trust that they do.
    var drawnLevels: [CGFloat] {
        bars.map { bar in
            let transform = bar.presentation()?.transform ?? bar.transform
            return CGFloat(transform.m22)
        }
    }

    var hasBounceAnimation: Bool { timer != nil || liveLevels != nil }
}
