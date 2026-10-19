import AppKit

/// Now playing: artwork, transport, progress, volume and shuffle.
final class MediaDetailView: NSView {
    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    var onOpenSource: (() -> Void)?
    var onShuffle: (() -> Void)?
    var onVolume: ((Int) -> Void)?
    var onSeek: ((Double) -> Void)?

    private let artworkView = Style.roundedImageView(cornerRadius: 8)
    private let titleLabel = Style.label(size: 13, weight: .semibold)
    private let artistLabel = Style.label(size: 11, color: Style.secondaryText)
    /// The line being sung, when synced lyrics are on and the song has them.
    private let lyricLabel = Style.label(size: 12, weight: .medium)
    private var lyricsObserver: UUID?
    private var queueObserver: UUID?
    /// Next in the playlist, beside everything else — Apple Music only.
    private let upNextStack = NSStackView()
    private var mainTrailing: NSLayoutConstraint?
    private var upNextTrailing: NSLayoutConstraint?
    private var artistText = ""
    private var showsTrack = false
    private lazy var previousButton = Style.symbolButton("backward.fill", pointSize: 13, target: self, action: #selector(handlePrevious))
    private lazy var playPauseButton = Style.symbolButton("play.fill", pointSize: 17, target: self, action: #selector(handlePlayPause))
    private lazy var nextButton = Style.symbolButton("forward.fill", pointSize: 13, target: self, action: #selector(handleNext))
    private lazy var shuffleButton = Style.symbolButton("shuffle", pointSize: 12, target: self, action: #selector(handleShuffle))
    private let progressBar = ProgressBarView()
    private let elapsedLabel = Style.label("0:00", size: 9, color: Style.tertiaryText)
    private let durationLabel = Style.label("0:00", size: 9, color: Style.tertiaryText)
    private let volumeBar = ProgressBarView()

    private let artworkLoader = ArtworkLoader.shared
    private var artworkKey: String?

    private let isCompact: Bool

    init(isCompact: Bool = false) {
        self.isCompact = isCompact
        super.init(frame: .zero)
        configure()
        lyricsObserver = LyricsService.shared.addObserver { [weak self] _ in self?.showLyric() }
        if isCompact == false {
            queueObserver = MusicQueue.shared.addObserver { [weak self] entries in self?.showUpNext(entries) }
        }
    }

    deinit {
        lyricsObserver.map(LyricsService.shared.removeObserver)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        let textStack = NSStackView(views: [titleLabel, artistLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let transport = NSStackView(views: [previousButton, playPauseButton, nextButton])
        transport.orientation = .horizontal
        transport.alignment = .centerY
        transport.spacing = 14

        // A zone column cannot fit artwork, text and transport on one line without
        // truncating the title to nothing.
        let topRow = NSStackView(views: isCompact ? [artworkView, textStack] : [artworkView, textStack, transport])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 10

        progressBar.onScrub = { [weak self] fraction in
            guard let self, self.trackDuration > 0 else { return }
            self.onSeek?(fraction * self.trackDuration)
        }

        let progressRow = NSStackView(views: [elapsedLabel, progressBar, durationLabel])
        progressRow.orientation = .horizontal
        progressRow.alignment = .centerY
        progressRow.spacing = 6

        volumeBar.onScrub = { [weak self] fraction in
            self?.onVolume?(Int((fraction * 100).rounded()))
        }

        let speakerIcon = NSImageView()
        speakerIcon.image = Style.symbolImage("speaker.wave.2.fill", pointSize: 10)
        speakerIcon.contentTintColor = Style.tertiaryText

        let bottomRow = NSStackView(views: [shuffleButton, speakerIcon, volumeBar])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 8

        // A zone column has no room for the scrubber and volume bar, nor a line of its
        // own for lyrics: there they take the artist's place.
        let root = NSStackView(views: isCompact ? [topRow, transport, progressRow] : [topRow, lyricLabel, progressRow, bottomRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            artworkView.widthAnchor.constraint(equalToConstant: isCompact ? 34 : 44),
            artworkView.heightAnchor.constraint(equalToConstant: isCompact ? 34 : 44),
            progressBar.heightAnchor.constraint(equalToConstant: 4),
            volumeBar.widthAnchor.constraint(equalToConstant: 90),
            volumeBar.heightAnchor.constraint(equalToConstant: 4),
            // Times must not be squeezed by the progress bar beside them.
            elapsedLabel.widthAnchor.constraint(equalToConstant: 34),
            durationLabel.widthAnchor.constraint(equalToConstant: 34),
            topRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            progressRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            lyricLabel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor),
            progressRow.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        mainTrailing = root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        mainTrailing?.isActive = true

        if isCompact == false {
            upNextStack.orientation = .vertical
            upNextStack.alignment = .leading
            upNextStack.spacing = 4
            upNextStack.translatesAutoresizingMaskIntoConstraints = false
            upNextStack.isHidden = true
            addSubview(upNextStack)
            NSLayoutConstraint.activate([
                upNextStack.widthAnchor.constraint(equalToConstant: 200),
                upNextStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                upNextStack.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            upNextTrailing = root.trailingAnchor.constraint(equalTo: upNextStack.leadingAnchor, constant: -24)
            showUpNext(MusicQueue.shared.upNext)
        }

        artworkView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleOpenSource)))
        lyricLabel.lineBreakMode = .byTruncatingTail
        lyricLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lyricLabel.isHidden = true
    }

    private func showUpNext(_ entries: [MusicQueue.Entry]) {
        upNextStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visible = entries.isEmpty == false && showsTrack
        upNextStack.isHidden = visible == false
        mainTrailing?.isActive = visible == false
        upNextTrailing?.isActive = visible
        guard visible else { return }

        upNextStack.addArrangedSubview(Style.label("Next in playlist", size: 10, weight: .semibold, color: Style.secondaryText))
        for entry in entries {
            let row = UpNextRow(entry: entry)
            upNextStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: upNextStack.widthAnchor).isActive = true
        }
    }

    private func showLyric() {
        let line = showsTrack ? LyricsService.shared.currentLine : nil
        if isCompact {
            artistLabel.stringValue = line ?? artistText
            artistLabel.textColor = line == nil ? Style.secondaryText : Style.primaryText
        } else {
            lyricLabel.stringValue = line ?? ""
            lyricLabel.isHidden = line == nil
        }
    }

    private var trackDuration: Double = 0

    func render(_ state: NowPlayingState) {
        switch state {
        case .track(let track):
            titleLabel.stringValue = track.name
            artistText = track.artist.isEmpty ? track.sourceName : track.artist
            showsTrack = true
            if isCompact == false { showUpNext(MusicQueue.shared.upNext) }
            artistLabel.stringValue = artistText
            showLyric()
            setControlsEnabled(true)
            playPauseButton.image = Style.symbolImage(track.isPlaying ? "pause.fill" : "play.fill", pointSize: 17)
            shuffleButton.contentTintColor = track.isShuffling ? Style.accent : Style.tertiaryText

            trackDuration = track.duration
            progressBar.fraction = track.duration > 0 ? min(1, track.position / track.duration) : 0
            elapsedLabel.stringValue = Self.timeString(track.position)
            durationLabel.stringValue = Self.timeString(track.duration)

            // Leave the slider alone while it is being dragged.
            if let volume = track.volume {
                volumeBar.fraction = Double(volume) / 100
            }

            loadArtwork(from: track.artworkURL, fallbackBundleIdentifier: track.sourceBundleIdentifier)

        case .external(let source):
            // No track, no transport — but at least say what is making the sound, and
            // for a browser that means the page rather than the browser.
            titleLabel.stringValue = source.displayName
            showsTrack = false
            if isCompact == false { showUpNext([]) }
            showLyric()
            artistLabel.stringValue = source.detail
            setControlsEnabled(false)
            trackDuration = 0
            progressBar.fraction = 0
            elapsedLabel.stringValue = "0:00"
            durationLabel.stringValue = "0:00"
            artworkKey = nil
            artworkView.contentTintColor = nil
            artworkView.layer?.backgroundColor = NSColor.clear.cgColor
            artworkView.image = source.displayIcon

        case .message(let message):
            titleLabel.stringValue = message
            showsTrack = false
            if isCompact == false { showUpNext([]) }
            showLyric()
            artistLabel.stringValue = ""
            setControlsEnabled(false)
            trackDuration = 0
            progressBar.fraction = 0
            elapsedLabel.stringValue = "0:00"
            durationLabel.stringValue = "0:00"
            artworkKey = nil
            artworkView.layer?.backgroundColor = Style.controlFill.cgColor
            artworkView.image = Style.symbolImage("music.note", pointSize: 18)
            artworkView.contentTintColor = Style.tertiaryText
        }
    }

    private func setControlsEnabled(_ isEnabled: Bool) {
        [previousButton, playPauseButton, nextButton, shuffleButton].forEach {
            $0.isEnabled = isEnabled
            $0.alphaValue = isEnabled ? 1 : 0.3
        }
        volumeBar.alphaValue = isEnabled ? 1 : 0.3
    }

    private func loadArtwork(from url: URL?, fallbackBundleIdentifier: String) {
        let key = url?.absoluteString ?? "app:\(fallbackBundleIdentifier)"
        guard artworkKey != key else { return }
        artworkKey = key

        guard let url else {
            // Music exposes no artwork URL, so show the player's own icon instead.
            artworkView.contentTintColor = nil
            artworkView.layer?.backgroundColor = NSColor.clear.cgColor
            artworkView.image = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: fallbackBundleIdentifier)
                .map { url -> NSImage in
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 44, height: 44)
                    return icon
                }
            return
        }

        artworkLoader.load(url) { [weak self] image in
            // A later track may have won the race while this download was in flight.
            guard let self, self.artworkKey == key else { return }
            self.artworkView.contentTintColor = nil
            self.artworkView.image = image
            self.artworkView.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func handlePlayPause() { onPlayPause?() }
    @objc private func handleNext() { onNextTrack?() }
    @objc private func handlePrevious() { onPreviousTrack?() }
    @objc private func handleOpenSource() { onOpenSource?() }
    @objc private func handleShuffle() { onShuffle?() }
}

/// Thin playback bar that can also be clicked to scrub.
final class ProgressBarView: NSView {
    var onScrub: ((Double) -> Void)?

    var fraction: Double = 0 {
        didSet { needsLayout = true }
    }

    private let track = CALayer()
    private let fill = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        track.backgroundColor = Style.primaryText.withAlphaComponent(0.2).cgColor
        fill.backgroundColor = Style.primaryText.withAlphaComponent(0.85).cgColor
        track.cornerRadius = 2
        fill.cornerRadius = 2
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(max(0, min(1, fraction))), height: bounds.height)
        CATransaction.commit()
    }

    var isEnabled = true
    private(set) var isTracking = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isTracking = true
        scrub(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, isTracking else { return }
        scrub(to: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, isTracking else { return }
        scrub(to: event)
        isTracking = false
    }

    private func scrub(to event: NSEvent) {
        guard bounds.width > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        onScrub?(Double(max(0, min(1, point.x / bounds.width))))
    }
}

/// One track coming up: click to play it now.
private final class UpNextRow: NSView {
    private let entry: MusicQueue.Entry

    init(entry: MusicQueue.Entry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        let title = Style.label(entry.title, size: 11, weight: .medium)
        let artist = Style.label(entry.artist, size: 10, color: Style.secondaryText)
        let stack = NSStackView(views: [title, artist])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
        toolTip = "Play \(entry.title) now"
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = Style.controlFill.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
    override func mouseDown(with event: NSEvent) {
        Haptics.tick()
        MusicQueue.shared.play(entry)
    }
}
