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

/// Three bars that rise and fall while playback is running.
final class LevelMeterView: NSView {
    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            isRunning ? startAnimating() : stopAnimating()
        }
    }

    private let bars: [CALayer] = (0..<3).map { _ in CALayer() }

    /// The artwork's colour; nil for the theme's text colour.
    var tint: NSColor? {
        didSet { bars.forEach { $0.backgroundColor = (tint ?? Style.primaryText).cgColor } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bars.forEach {
            $0.backgroundColor = Style.primaryText.cgColor
            $0.cornerRadius = 1.5
            layer?.addSublayer($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let barWidth: CGFloat = 3
        let gap: CGFloat = 4
        for (index, bar) in bars.enumerated() {
            let height = bounds.height * [0.55, 1, 0.75][index]
            bar.frame = CGRect(x: CGFloat(index) * (barWidth + gap), y: 0, width: barWidth, height: height)
        }
    }

    private func startAnimating() {
        for (index, bar) in bars.enumerated() {
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = 0.35
            animation.toValue = 1
            animation.duration = 0.42 + Double(index) * 0.11
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.add(animation, forKey: "bounce")
        }
    }

    private func stopAnimating() {
        bars.forEach { $0.removeAnimation(forKey: "bounce") }
    }

    /// Each bar's drawn height right now, as a fraction of its full height — for the
    /// self-test, which has to see the bars move rather than trust that they do.
    var drawnLevels: [CGFloat] {
        bars.map { bar in
            let transform = bar.presentation()?.transform ?? bar.transform
            return CGFloat(transform.m22)
        }
    }

    var hasBounceAnimation: Bool { bars.allSatisfy { $0.animation(forKey: "bounce") != nil } }
}
