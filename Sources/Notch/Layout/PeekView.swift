import AppKit

/// What the peek shows: one line of whatever matters most right now.
enum PeekContent {
    /// A track or anything else playing. Only Spotify and Music can be controlled.
    case playing(title: String, subtitle: String, icon: NSImage?, isPlaying: Bool, isControllable: Bool)
    /// A call that is on now or about to start, with a link to join it.
    case meeting(title: String, when: String, service: String)
    /// Nothing happening: the date, and what's next today.
    case glance(title: String, subtitle: String)
}

/// The peek: the resting bar grown into a small card when the pointer rests on the
/// notch. The band keeps the resting bar's artwork and meter, so it reads as the same
/// thing opening up; underneath, one row says what is happening, with the one or two
/// controls that go with it. A click anywhere else on it opens the full panel.
final class PeekView: NSView {
    var onOpen: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onJoin: (() -> Void)?

    /// Only while the peek is on screen does it take clicks. It spans the whole card and
    /// sits above the panel's content, and AppKit hit-tests faded-out views — the same
    /// trap that once swallowed every click in the open panel.
    var isActive = false

    /// The straight part of the peek card, which is all the content may use.
    var bodyWidth: CGFloat = 0 {
        didSet { if bodyWidth != oldValue { needsLayout = true } }
    }

    static let rowHeight: CGFloat = 40

    private let notchWidth: CGFloat
    private let bandHeight: CGFloat

    private let icon = Style.roundedImageView(cornerRadius: 6)
    private let meter = LevelMeterView()
    private let titleLabel = Style.label("", size: 13, weight: .semibold)
    private let subtitleLabel = Style.label("", size: 11, color: Style.secondaryText)
    private lazy var previousButton = Style.symbolButton("backward.fill", pointSize: 13, target: self, action: #selector(handlePrevious))
    private lazy var playButton = Style.symbolButton("pause.fill", pointSize: 16, target: self, action: #selector(handlePlayPause))
    private lazy var nextButton = Style.symbolButton("forward.fill", pointSize: 13, target: self, action: #selector(handleNext))
    private lazy var joinButton = Style.pushButton("Join", prominent: true, target: self, action: #selector(handleJoin))
    private let actions = NSStackView()
    private let text = NSStackView()

    private enum Layout {
        static let iconSize: CGFloat = 24
        static let meterSize = CGSize(width: 18, height: 13)
        static let notchGap: CGFloat = 10
        static let edgeInset: CGFloat = 18
    }

    init(notchWidth: CGFloat, bandHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.bandHeight = bandHeight
        super.init(frame: .zero)

        icon.imageScaling = .scaleProportionallyUpOrDown
        [titleLabel, subtitleLabel].forEach(text.addArrangedSubview)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        [previousButton, playButton, nextButton, joinButton].forEach(actions.addArrangedSubview)
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 14
        actions.setHuggingPriority(.required, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        [icon, meter, text, actions].forEach(addSubview)
        previousButton.toolTip = "Previous — ⌘←"
        playButton.toolTip = "Play or pause — Space"
        nextButton.toolTip = "Next — ⌘→"
        joinButton.toolTip = "Join the call — ⌘J"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isActive ? super.hitTest(point) : nil
    }

    /// Anywhere that isn't a control opens the full panel.
    override func mouseDown(with event: NSEvent) {
        onOpen?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ content: PeekContent) {
        switch content {
        case let .playing(title, subtitle, image, isPlaying, isControllable):
            icon.image = image ?? Style.symbolImage("waveform", pointSize: 13)
            icon.contentTintColor = image == nil ? Style.primaryText : nil
            icon.isHidden = false
            meter.isHidden = false
            meter.isRunning = isPlaying
            meter.alphaValue = isPlaying ? 1 : 0.35
            titleLabel.stringValue = title
            subtitleLabel.stringValue = subtitle
            playButton.image = Style.symbolImage(isPlaying ? "pause.fill" : "play.fill", pointSize: 16)
            [previousButton, playButton, nextButton].forEach { $0.isHidden = isControllable == false }
            joinButton.isHidden = true

        case let .meeting(title, when, service):
            icon.image = Style.symbolImage("video.fill", pointSize: 13)
            icon.contentTintColor = Style.accent
            icon.isHidden = false
            meter.isHidden = true
            meter.isRunning = false
            titleLabel.stringValue = title
            subtitleLabel.stringValue = "\(when) · \(service)"
            [previousButton, playButton, nextButton].forEach { $0.isHidden = true }
            joinButton.isHidden = false

        case let .glance(title, subtitle):
            icon.isHidden = true
            meter.isHidden = true
            meter.isRunning = false
            titleLabel.stringValue = title
            subtitleLabel.stringValue = subtitle
            [previousButton, playButton, nextButton, joinButton].forEach { $0.isHidden = true }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let notchLeft = (bounds.width - notchWidth) / 2
        let notchRight = notchLeft + notchWidth
        let bandMidY = bounds.height - bandHeight / 2
        let body = max(bodyWidth, notchWidth)
        let bodyLeft = (bounds.width - body) / 2 + Layout.edgeInset
        let bodyRight = (bounds.width + body) / 2 - Layout.edgeInset

        // The band carries over from the resting bar: artwork left of the notch, meter right.
        icon.frame = CGRect(
            x: notchLeft - Layout.notchGap - Layout.iconSize,
            y: bandMidY - Layout.iconSize / 2,
            width: Layout.iconSize,
            height: Layout.iconSize
        )
        meter.frame = CGRect(
            x: notchRight + Layout.notchGap,
            y: bandMidY - Layout.meterSize.height / 2,
            width: Layout.meterSize.width,
            height: Layout.meterSize.height
        )

        // The row below the notch: words on the left, controls on the right.
        let rowMidY = bounds.height - bandHeight - Self.rowHeight / 2 - 2
        let actionsSize = actions.fittingSize
        actions.frame = CGRect(
            x: bodyRight - actionsSize.width,
            y: rowMidY - actionsSize.height / 2,
            width: actionsSize.width,
            height: actionsSize.height
        )
        let textHeight = text.fittingSize.height
        text.frame = CGRect(
            x: bodyLeft,
            y: rowMidY - textHeight / 2,
            width: max(0, actions.frame.minX - 14 - bodyLeft),
            height: textHeight
        )
    }

    @objc private func handlePlayPause() { onPlayPause?() }
    @objc private func handleNext() { onNext?() }
    @objc private func handlePrevious() { onPrevious?() }
    @objc private func handleJoin() { onJoin?() }
}
