import AppKit

/// A track for the peek. Position is where the track was at `asOf`; the peek moves it on
/// itself while playing, so the scrubber runs smoothly between poller ticks.
struct PeekTrack {
    var title: String
    var subtitle: String
    var icon: NSImage?
    var isPlaying: Bool
    /// Only Spotify and Music can be controlled; a browser video can only be shown.
    var isControllable: Bool
    var position: Double = 0
    var duration: Double = 0
    var asOf = Date()
    /// The artwork's colour, for the level meter.
    var tint: NSColor?
}

extension PeekTrack {
    /// A Spotify or Music track as the peek and the lock screen show it: the line being
    /// sung in place of the artist, when lyrics are on.
    init(track: TrackInfo, icon: NSImage?, tint: NSColor?, asOf: Date) {
        self.init(
            title: track.name,
            subtitle: LyricsService.shared.currentLine
                ?? [track.artist, track.sourceName].filter { $0.isEmpty == false }.joined(separator: " · "),
            icon: icon,
            isPlaying: track.isPlaying,
            isControllable: true,
            position: track.position,
            duration: track.duration,
            asOf: asOf,
            tint: tint
        )
    }
}

/// An event for the peek's "next" line.
struct PeekEvent {
    var title: String
    var start: Date
    var color: NSColor
}

/// What the peek shows: whatever matters most right now.
enum PeekContent {
    case playing(PeekTrack)
    /// A call on now or about to start, with a link to join it.
    case meeting(title: String, service: String, start: Date)
    /// Nothing happening: the time, the date, and what's next today.
    case glance(next: PeekEvent?, hasCalendar: Bool)
    /// A call in progress: mute, camera, leave.
    case call(CallState)
    /// A screenshot just taken: drag it out, or copy, mark up, shelve, delete.
    case screenshot(URL)
}

/// The peek, laid out like the Dynamic Island's expanded view — the layout Crest and
/// Droppy borrow, and the one people already read without thinking: artwork beside the
/// title, the level meter in the artwork's colour, a scrubber with elapsed and remaining
/// time, and the transport underneath. A call about to start gets a countdown and a
/// Join button; with nothing on, the clock and the next event.
///
/// A click anywhere that isn't a control opens the full panel.
final class PeekView: NSView {
    var onOpen: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onJoin: (() -> Void)?
    var onMute: (() -> Void)?
    var onCamera: (() -> Void)?
    var onLeave: (() -> Void)?
    /// The content changed height; the card has to follow.
    var onHeightChange: (() -> Void)?

    /// Only while the peek is on screen does it take clicks. It spans the whole card and
    /// sits above the panel's content, and AppKit hit-tests faded-out views — the same
    /// trap that once swallowed every click in the open panel.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            isActive ? startClock() : stopClock()
        }
    }

    /// The straight part of the peek card, which is all the content may use.
    var bodyWidth: CGFloat = 0 {
        didSet { if bodyWidth != oldValue { needsLayout = true } }
    }

    /// The card's width. Wide enough for a title beside the artwork, still far smaller
    /// than the panel.
    static func cardWidth(notchWidth: CGFloat) -> CGFloat {
        max(notchWidth + 200, 400)
    }

    /// The whole card for a body of `preferredHeight`: the straight body plus the flares.
    static func cardSize(height: CGFloat, notchWidth: CGFloat) -> CGSize {
        let flare = min(NotchShape.topFlare, height * 0.55)
        return CGSize(width: cardWidth(notchWidth: notchWidth) + flare * 2, height: height)
    }

    private let notchWidth: CGFloat
    private let bandHeight: CGFloat
    private(set) var content: PeekContent = .glance(next: nil, hasCalendar: false)

    private let icon = Style.roundedImageView(cornerRadius: 8)
    private let meter = LevelMeterView()
    private let titleLabel = Style.label("", size: 13, weight: .semibold)
    private let subtitleLabel = Style.label("", size: 11, color: Style.secondaryText)
    private let elapsedLabel = Style.label("0:00", size: 10, color: Style.secondaryText)
    private let remainingLabel = Style.label("-0:00", size: 10, color: Style.secondaryText)
    private let progressTrack = CALayer()
    private let progressFill = CALayer()
    private lazy var previousButton = Style.symbolButton("backward.fill", pointSize: 14, target: self, action: #selector(handlePrevious))
    private lazy var playButton = Style.symbolButton("pause.fill", pointSize: 18, target: self, action: #selector(handlePlayPause))
    private lazy var nextButton = Style.symbolButton("forward.fill", pointSize: 14, target: self, action: #selector(handleNext))
    private lazy var joinButton = Style.pushButton("Join", prominent: true, target: self, action: #selector(handleJoin))
    private let bigLabel = Style.label("", size: 24, weight: .medium)
    private let rule = CALayer()
    private let eventBar = CALayer()
    private let eventTitle = Style.label("", size: 12, weight: .semibold)
    private let eventDetail = Style.label("", size: 11, color: Style.secondaryText)
    private let callTimer = Style.label("", size: 12, color: Style.secondaryText)
    private lazy var muteButton = Self.roundButton("mic.fill", target: self, action: #selector(handleMute))
    private lazy var cameraButton = Self.roundButton("video.fill", target: self, action: #selector(handleCamera))
    private lazy var leaveButton = Self.roundButton("phone.down.fill", target: self, action: #selector(handleLeave))
    private var clock: Timer?
    /// Rebuilt for each screenshot: its thumbnail and its actions.
    private let screenshotContainer = NSView()

    private enum Layout {
        static let edgeInset: CGFloat = 18
        static let topGap: CGFloat = 8
        static let iconSize: CGFloat = 38
        static let meterSize = CGSize(width: 17, height: 13)
        static let progressRow: CGFloat = 12
        static let controlsRow: CGFloat = 24
        static let bottomInset: CGFloat = 12
    }

    init(notchWidth: CGFloat, bandHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.bandHeight = bandHeight
        super.init(frame: .zero)
        wantsLayer = true

        icon.imageScaling = .scaleProportionallyUpOrDown
        [elapsedLabel, remainingLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: Style.scaled(10), weight: .regular)
        }
        remainingLabel.alignment = .right
        bigLabel.font = .monospacedDigitSystemFont(ofSize: Style.scaled(24), weight: .medium)

        progressTrack.backgroundColor = Style.primaryText.withAlphaComponent(0.18).cgColor
        progressTrack.cornerRadius = 1.5
        progressFill.backgroundColor = Style.primaryText.cgColor
        progressFill.cornerRadius = 1.5
        rule.backgroundColor = Style.primaryText.withAlphaComponent(0.12).cgColor
        eventBar.cornerRadius = 1.5
        [progressTrack, progressFill, rule, eventBar].forEach { layer?.addSublayer($0) }

        callTimer.font = .monospacedDigitSystemFont(ofSize: Style.scaled(12), weight: .regular)
        callTimer.alignment = .right
        [icon, meter, titleLabel, subtitleLabel, elapsedLabel, remainingLabel,
         previousButton, playButton, nextButton, joinButton, bigLabel, eventTitle, eventDetail,
         callTimer, muteButton, cameraButton, leaveButton, screenshotContainer].forEach(addSubview)
        muteButton.toolTip = "Mute or unmute — ⌃⌥M"
        cameraButton.toolTip = "Camera on or off"
        leaveButton.toolTip = "Leave the call"
        leaveButton.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1).cgColor

        previousButton.toolTip = "Previous — ⌘←"
        playButton.toolTip = "Play or pause — Space"
        nextButton.toolTip = "Next — ⌘→"
        joinButton.toolTip = "Join the call — ⌘J"
        // The peek lays its controls out by frame; the factory's size constraints would
        // fight the frame it is given.
        NSLayoutConstraint.deactivate(joinButton.constraints)
        // Join is green, as call buttons are everywhere — the one control that means "go".
        joinButton.layer?.backgroundColor = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).cgColor
        joinButton.attributedTitle = NSAttributedString(string: "Join", attributes: [
            .foregroundColor: NSColor(srgbRed: 0.02, green: 0.13, blue: 0.05, alpha: 1),
            .font: NSFont.systemFont(ofSize: Style.scaled(13), weight: .semibold)
        ])
        show(content)
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

    // MARK: - Content

    func show(_ content: PeekContent) {
        let oldHeight = preferredHeight
        self.content = content
        let allViews: [NSView] = [icon, meter, titleLabel, subtitleLabel, elapsedLabel, remainingLabel,
                                  previousButton, playButton, nextButton, joinButton, bigLabel, eventTitle, eventDetail,
                                  callTimer, muteButton, cameraButton, leaveButton, screenshotContainer]
        var visible: [NSView] = []
        var layers: [CALayer] = []

        switch content {
        case .playing(let track):
            icon.image = track.icon ?? Style.symbolImage("waveform", pointSize: 16)
            icon.contentTintColor = track.icon == nil ? Style.primaryText : nil
            icon.layer?.backgroundColor = track.icon == nil ? Style.controlFill.cgColor : NSColor.clear.cgColor
            titleLabel.stringValue = track.title
            subtitleLabel.stringValue = track.subtitle
            meter.tint = track.tint
            meter.isRunning = track.isPlaying
            meter.alphaValue = track.isPlaying ? 1 : 0.35
            playButton.image = Style.symbolImage(track.isPlaying ? "pause.fill" : "play.fill", pointSize: 18)
            visible = [icon, meter, titleLabel, subtitleLabel]
            if track.isControllable {
                visible += [previousButton, playButton, nextButton]
                if track.duration > 0 {
                    visible += [elapsedLabel, remainingLabel]
                    layers = [progressTrack, progressFill]
                }
            }

        case let .meeting(title, service, start):
            icon.image = Style.symbolImage("video.fill", pointSize: 17)
            icon.contentTintColor = .white
            icon.layer?.backgroundColor = Self.serviceColor(service).cgColor
            titleLabel.stringValue = title
            subtitleLabel.stringValue = "\(service) · \(start.formatted(date: .omitted, time: .shortened))"
            meter.isRunning = false
            visible = [icon, titleLabel, subtitleLabel, bigLabel, joinButton]

        case .call(let call):
            // The app's own icon; failing that, the service's coloured tile.
            if let appIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: call.bundleIdentifier)
                .map({ NSWorkspace.shared.icon(forFile: $0.path) }) {
                icon.image = appIcon
                icon.contentTintColor = nil
                icon.layer?.backgroundColor = NSColor.clear.cgColor
            } else {
                icon.image = Style.symbolImage("video.fill", pointSize: 17)
                icon.contentTintColor = .white
                icon.layer?.backgroundColor = Self.serviceColor(call.service).cgColor
            }
            titleLabel.stringValue = call.title ?? "\(call.service) call"
            if call.needsBrowserSetting {
                subtitleLabel.stringValue = "Allow JavaScript from Apple Events in \(call.appName) to control Meet"
            } else {
                var parts = [call.service]
                if let muted = call.isMuted { parts.append(muted ? "muted" : "mic on") }
                if call.isCameraOff == true { parts.append("camera off") }
                subtitleLabel.stringValue = parts.joined(separator: " · ")
            }
            meter.isRunning = false
            let muted = call.isMuted == true
            muteButton.image = Style.symbolImage(muted ? "mic.slash.fill" : "mic.fill", pointSize: 14)
            muteButton.contentTintColor = muted ? .black : .white
            muteButton.layer?.backgroundColor = (muted ? NSColor.white : NSColor.white.withAlphaComponent(0.16)).cgColor
            let cameraOff = call.isCameraOff == true
            cameraButton.image = Style.symbolImage(cameraOff ? "video.slash.fill" : "video.fill", pointSize: 14)
            visible = [icon, titleLabel, subtitleLabel, callTimer, muteButton]
            if call.hasCamera { visible += [cameraButton] }
            if call.canLeave { visible += [leaveButton] }

        case .screenshot(let url):
            meter.isRunning = false
            buildScreenshot(url)
            visible = [screenshotContainer]

        case let .glance(next, _):
            meter.isRunning = false
            visible = [bigLabel, subtitleLabel]
            if let next {
                eventTitle.stringValue = next.title
                eventBar.backgroundColor = next.color.cgColor
                visible += [eventTitle, eventDetail]
                layers = [rule, eventBar]
            }
        }

        allViews.forEach { $0.isHidden = visible.contains($0) == false }
        [progressTrack, progressFill, rule, eventBar].forEach { $0.isHidden = layers.contains($0) == false }
        tick()
        needsLayout = true
        if preferredHeight != oldHeight { onHeightChange?() }
    }

    /// Height of the whole card, the notch's band included.
    var preferredHeight: CGFloat {
        let body: CGFloat
        switch content {
        case .playing(let track):
            var height = Layout.topGap + Layout.iconSize
            if track.isControllable {
                if track.duration > 0 { height += 10 + Layout.progressRow }
                height += 6 + Layout.controlsRow
            }
            body = height + Layout.bottomInset
        case .meeting:
            body = Layout.topGap + Layout.iconSize + 10 + 30 + Layout.bottomInset
        case .call:
            body = Layout.topGap + Layout.iconSize + 10 + Self.roundSize + Layout.bottomInset
        case .screenshot:
            body = Layout.topGap + Self.screenshotHeight + Layout.bottomInset
        case .glance(let next, _):
            body = Layout.topGap + 46 + (next == nil ? 0 : 10 + 1 + 10 + 30) + Layout.bottomInset
        }
        return bandHeight + body
    }

    // MARK: - Time

    private func startClock() {
        tick()
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    /// Everything that moves with the clock: the scrubber, the countdown, the time.
    private func tick() {
        let now = Date()
        switch content {
        case .playing(let track):
            guard track.duration > 0 else { return }
            let position = min(track.duration, track.position + (track.isPlaying ? now.timeIntervalSince(track.asOf) : 0))
            elapsedLabel.stringValue = Self.time(position)
            remainingLabel.stringValue = "-" + Self.time(track.duration - position)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressFill.frame.size.width = progressTrack.frame.width * CGFloat(position / track.duration)
            CATransaction.commit()

        case .meeting(_, _, let start):
            let seconds = Int(start.timeIntervalSince(now).rounded(.up))
            if seconds > 0 {
                bigLabel.stringValue = Self.time(Double(seconds))
            } else {
                let minutes = -seconds / 60
                bigLabel.stringValue = minutes == 0 ? "Now" : "\(minutes) min in"
            }

        case .call(let call):
            callTimer.stringValue = Self.time(now.timeIntervalSince(call.startedAt))

        case .screenshot:
            break

        case .glance(let next, let hasCalendar):
            bigLabel.stringValue = now.formatted(date: .omitted, time: .shortened)
            subtitleLabel.stringValue = now.formatted(.dateTime.weekday(.wide).day().month(.wide))
            if let next {
                eventDetail.stringValue = "\(next.start.formatted(date: .omitted, time: .shortened)) · \(Self.relative(next.start, from: now))"
            } else if hasCalendar {
                subtitleLabel.stringValue += " · nothing else today"
            }
        }
    }

    /// "3:52", "1:04:09".
    static func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// "in 3 h", "in 25 min", "now".
    static func relative(_ date: Date, from now: Date = Date()) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded())
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        let hours = Int((Double(minutes) / 60).rounded())
        return "in \(hours) h"
    }

    /// The colour each service paints its own buttons, as Atoll uses for Join.
    static func serviceColor(_ service: String) -> NSColor {
        switch service {
        case "Zoom": return NSColor(srgbRed: 0.16, green: 0.52, blue: 0.95, alpha: 1)
        case "Google Meet": return NSColor(srgbRed: 0, green: 0.65, blue: 0.42, alpha: 1)
        case "Teams": return NSColor(srgbRed: 0.36, green: 0.42, blue: 0.89, alpha: 1)
        case "Webex": return NSColor(srgbRed: 0.04, green: 0.6, blue: 0.55, alpha: 1)
        default: return NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let body = max(bodyWidth, notchWidth)
        let left = (bounds.width - body) / 2 + Layout.edgeInset
        let right = (bounds.width + body) / 2 - Layout.edgeInset
        var y = bounds.height - bandHeight - Layout.topGap

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        switch content {
        case .screenshot:
            screenshotContainer.frame = CGRect(x: left, y: y - Self.screenshotHeight, width: right - left, height: Self.screenshotHeight)
            layoutScreenshot()

        case .call:
            // Row 1: the app, the call's name and state, how long it has run.
            icon.frame = CGRect(x: left, y: y - Layout.iconSize, width: Layout.iconSize, height: Layout.iconSize)
            let timerWidth: CGFloat = 60
            let timerHeight = callTimer.fittingSize.height
            let rowMid = y - Layout.iconSize / 2
            callTimer.frame = CGRect(x: right - timerWidth, y: rowMid - timerHeight / 2, width: timerWidth, height: timerHeight)
            let textLeft = icon.frame.maxX + 10, textRight = callTimer.frame.minX - 8
            let titleHeight = titleLabel.fittingSize.height, subtitleHeight = subtitleLabel.fittingSize.height
            titleLabel.frame = CGRect(x: textLeft, y: rowMid + (titleHeight + subtitleHeight) / 2 - titleHeight, width: textRight - textLeft, height: titleHeight)
            subtitleLabel.frame = CGRect(x: textLeft, y: titleLabel.frame.minY - subtitleHeight, width: textRight - textLeft, height: subtitleHeight)
            y -= Layout.iconSize + 10

            // Row 2: the round buttons, centred — mute, camera, and leave in red.
            let buttons = [muteButton, cameraButton, leaveButton].filter { $0.isHidden == false }
            let gap: CGFloat = 22
            let total = CGFloat(buttons.count) * Self.roundSize + CGFloat(buttons.count - 1) * gap
            var x = (left + right) / 2 - total / 2
            for button in buttons {
                button.frame = CGRect(x: x, y: y - Self.roundSize, width: Self.roundSize, height: Self.roundSize)
                x += Self.roundSize + gap
            }

        case .playing, .meeting:
            // Row 1: artwork (or the call's tile), title and subtitle, the meter.
            let rowMid = y - Layout.iconSize / 2
            icon.frame = CGRect(x: left, y: y - Layout.iconSize, width: Layout.iconSize, height: Layout.iconSize)
            let meterRight = meter.isHidden ? right : right - Layout.meterSize.width - 10
            meter.frame = CGRect(x: right - Layout.meterSize.width, y: rowMid - Layout.meterSize.height / 2,
                                 width: Layout.meterSize.width, height: Layout.meterSize.height)
            let textLeft = icon.frame.maxX + 10
            let titleHeight = titleLabel.fittingSize.height, subtitleHeight = subtitleLabel.fittingSize.height
            let textTop = rowMid + (titleHeight + subtitleHeight) / 2
            titleLabel.frame = CGRect(x: textLeft, y: textTop - titleHeight, width: max(0, meterRight - textLeft), height: titleHeight)
            subtitleLabel.frame = CGRect(x: textLeft, y: titleLabel.frame.minY - subtitleHeight, width: max(0, meterRight - textLeft), height: subtitleHeight)
            y -= Layout.iconSize

            if case .meeting = content {
                // Row 2: the countdown, and Join.
                y -= 10
                let joinSize = CGSize(width: max(70, joinButton.intrinsicContentSize.width + 28), height: 26)
                joinButton.frame = CGRect(x: right - joinSize.width, y: y - 15 - joinSize.height / 2, width: joinSize.width, height: joinSize.height)
                let bigHeight = bigLabel.fittingSize.height
                bigLabel.frame = CGRect(x: left, y: y - 15 - bigHeight / 2, width: joinButton.frame.minX - left - 10, height: bigHeight)
                return
            }

            // Row 2: the scrubber.
            if progressTrack.isHidden == false {
                y -= 10
                let labelWidth: CGFloat = 40
                let mid = y - Layout.progressRow / 2
                let labelHeight = elapsedLabel.fittingSize.height
                elapsedLabel.frame = CGRect(x: left, y: mid - labelHeight / 2, width: labelWidth, height: labelHeight)
                remainingLabel.frame = CGRect(x: right - labelWidth, y: mid - labelHeight / 2, width: labelWidth, height: labelHeight)
                progressTrack.frame = CGRect(x: left + labelWidth + 4, y: mid - 1.5, width: right - left - (labelWidth + 4) * 2, height: 3)
                progressFill.frame = CGRect(x: progressTrack.frame.minX, y: progressTrack.frame.minY,
                                            width: progressFill.frame.width, height: 3)
                y -= Layout.progressRow
            }

            // Row 3: the transport, centred under everything.
            y -= 6
            let mid = y - Layout.controlsRow / 2
            let centre = (left + right) / 2
            let spacing: CGFloat = 46
            for (button, offset) in [(previousButton, -spacing), (playButton, 0), (nextButton, spacing)] {
                let size = button.fittingSize
                button.frame = CGRect(x: centre + offset - size.width / 2, y: mid - size.height / 2, width: size.width, height: size.height)
            }
            tick()

        case .glance:
            // The time, big, with the date under it.
            let bigHeight = bigLabel.fittingSize.height
            bigLabel.frame = CGRect(x: left, y: y - bigHeight, width: right - left, height: bigHeight)
            let subtitleHeight = subtitleLabel.fittingSize.height
            subtitleLabel.frame = CGRect(x: left, y: bigLabel.frame.minY - subtitleHeight, width: right - left, height: subtitleHeight)
            y -= 46

            // A hairline, then what's next.
            y -= 10
            rule.frame = CGRect(x: left, y: y, width: right - left, height: 1)
            y -= 11
            eventBar.frame = CGRect(x: left, y: y - 28, width: 3, height: 28)
            let titleHeight = eventTitle.fittingSize.height, detailHeight = eventDetail.fittingSize.height
            eventTitle.frame = CGRect(x: left + 11, y: y - titleHeight, width: right - left - 11, height: titleHeight)
            eventDetail.frame = CGRect(x: left + 11, y: eventTitle.frame.minY - detailHeight, width: right - left - 11, height: detailHeight)
        }
    }

    /// The meter follows the sound when `AudioLevels` is listening.
    func setLevels(_ levels: [Float]?) {
        meter.setLevels(levels)
    }

    @objc private func handlePlayPause() { onPlayPause?() }
    @objc private func handleNext() { onNext?() }
    @objc private func handlePrevious() { onPrevious?() }
    @objc private func handleJoin() { onJoin?() }
    @objc private func handleMute() { onMute?() }
    @objc private func handleCamera() { onCamera?() }
    @objc private func handleLeave() { onLeave?() }

    static let roundSize: CGFloat = 34
    static let screenshotHeight: CGFloat = 80

    // MARK: - Screenshot

    private var screenshotActions: [() -> Void] = []

    /// macOS's floating thumbnail, moved to the notch: the picture on the left, to drag
    /// anywhere, and what to do with it on the right.
    private func buildScreenshot(_ url: URL) {
        screenshotContainer.subviews.forEach { $0.removeFromSuperview() }
        screenshotActions = []

        let thumbnail = ScreenshotThumbnailView(url: url, side: 128)
        thumbnail.onClick = { [weak self] in self?.onOpen?() }
        thumbnail.identifier = NSUserInterfaceItemIdentifier("thumbnail")
        screenshotContainer.addSubview(thumbnail)

        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let title = Style.label("Screenshot \(created.formatted(date: .omitted, time: .standard))", size: 13, weight: .semibold)
        title.identifier = NSUserInterfaceItemIdentifier("title")
        let hint = Style.label("Drag it anywhere, or", size: 11, color: Style.secondaryText)
        hint.identifier = NSUserInterfaceItemIdentifier("hint")
        [title, hint].forEach(screenshotContainer.addSubview)

        // Laid out by hand: a stack sized icon-only buttons by their image, not the row.
        let buttons = NSView()
        buttons.identifier = NSUserInterfaceItemIdentifier("buttons")
        // Copy is what you'll want most; the rest say what they are on hover.
        let entries: [(String, String, String, () -> Void)] = [
            ("Copy", "doc.on.doc", "Copy", { ScreenshotStore.copy(url) }),
            ("", "pencil.tip", "Mark up in Preview", { ScreenshotStore.markup(url) }),
            ("", "tray.and.arrow.down", "Put it on the shelf", { FileTray.shared.add([url]) }),
            ("", "text.viewfinder", "Copy the text in it", { FileActionRunner.run(.copyText, on: [url]) }),
            ("", "trash", "Move to Trash", { ScreenshotStore.shared.delete(url) })
        ]
        for (index, entry) in entries.enumerated() {
            let button = ClickThroughButton(title: entry.0, target: self, action: #selector(handleScreenshotAction(_:)))
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.backgroundColor = Style.controlFill.cgColor
            button.image = Style.symbolImage(entry.1, pointSize: 10)
            button.imagePosition = entry.0.isEmpty ? .imageOnly : .imageLeading
            button.imageHugsTitle = true
            button.contentTintColor = Style.primaryText
            button.attributedTitle = NSAttributedString(string: entry.0, attributes: [
                .foregroundColor: Style.primaryText, .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: .medium)
            ])
            button.toolTip = entry.2
            let width = entry.0.isEmpty ? 30 : button.intrinsicContentSize.width + 16
            button.frame = CGRect(x: buttons.subviews.last.map { $0.frame.maxX + 6 } ?? 0, y: 0, width: width, height: 24)
            screenshotActions.append(entry.3)
            buttons.addSubview(button)
        }
        screenshotContainer.addSubview(buttons)
    }

    private func layoutScreenshot() {
        let bounds = screenshotContainer.bounds
        func view(_ id: String) -> NSView? { screenshotContainer.subviews.first { $0.identifier?.rawValue == id } }
        let thumbWidth = Self.screenshotHeight * 1.45
        view("thumbnail")?.frame = CGRect(x: 0, y: 0, width: thumbWidth, height: Self.screenshotHeight)
        let left = thumbWidth + 14
        let width = bounds.width - left
        if let title = view("title") {
            let height = title.fittingSize.height
            title.frame = CGRect(x: left, y: bounds.height - height - 4, width: width, height: height)
            if let hint = view("hint") {
                let hintHeight = hint.fittingSize.height
                hint.frame = CGRect(x: left, y: title.frame.minY - hintHeight - 1, width: width, height: hintHeight)
            }
        }
        if let buttons = view("buttons") {
            buttons.frame = CGRect(x: left, y: 4, width: width, height: 24)
        }
    }

    @objc private func handleScreenshotAction(_ sender: NSButton) {
        guard screenshotActions.indices.contains(sender.tag) else { return }
        Haptics.tick()
        screenshotActions[sender.tag]()
    }

    /// A round call button, as the Dynamic Island and NotchBay draw them.
    private static func roundButton(_ symbol: String, target: AnyObject, action: Selector) -> NSButton {
        let button = ClickThroughButton(image: Style.symbolImage(symbol, pointSize: 14) ?? NSImage(), target: target, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = roundSize / 2
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        button.contentTintColor = .white
        button.imagePosition = .imageOnly
        return button
    }
}
