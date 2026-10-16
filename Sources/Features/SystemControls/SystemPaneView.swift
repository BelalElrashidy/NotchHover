import AppKit

/// The HUD pane: drag any bar to set volume, microphone gain, display brightness, or
/// keyboard backlight. The mic is here so that turning yourself down — or off — never
/// means opening Sound settings mid-call.
final class SystemPaneView: NSView {
    private let volumeRow = SystemSliderRow(symbol: "speaker.wave.2.fill", title: "Volume")
    private let micRow = SystemSliderRow(symbol: "mic.fill", title: "Microphone", mutedSymbol: "mic.slash.fill")
    private let displayRow = SystemSliderRow(symbol: "sun.max.fill", title: "Display")
    private let keyboardRow = SystemSliderRow(symbol: "keyboard.fill", title: "Keyboard")
    private var refreshTimer: Timer?

    init() {
        super.init(frame: .zero)

        volumeRow.onChange = { level in
            SystemControls.setVolume(level)
        }
        micRow.onChange = { level in
            SystemControls.setInputVolume(level)
        }
        // Clicking the mic icon is the whole point: mute in one hit, from anywhere.
        micRow.onToggleMute = { [weak self] in
            let muted = SystemControls.isInputMuted() == false
            SystemControls.setInputMuted(muted)
            self?.refresh()
        }
        displayRow.onChange = { level in
            SystemControls.setDisplayBrightness(level)
        }
        keyboardRow.onChange = { level in
            SystemControls.setKeyboardBacklight(level)
        }

        let stack = NSStackView(views: [volumeRow, micRow, displayRow, keyboardRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            volumeRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            micRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            displayRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            keyboardRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        displayRow.isEnabled = SystemControls.supportsDisplayBrightness
        keyboardRow.isEnabled = SystemControls.supportsKeyboardBacklight
        configureMicRow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Only polls while the pane is on screen.
    func startTracking() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopTracking() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Inputs come and go with the device — AirPods in, interface out — so the row is
    /// re-read rather than settled once at build time.
    private func configureMicRow() {
        let canSetGain = SystemControls.supportsInputVolume
        // A mic with no gain control can still be muted; the bar just has nothing to say.
        micRow.isEnabled = canSetGain || SystemControls.supportsInputMute
        micRow.isBarEnabled = canSetGain
        micRow.toolTip = [SystemControls.inputDeviceName(), canSetGain ? nil : "no gain control"]
            .compactMap { $0 }
            .joined(separator: " — ")
        micRow.emptyText = canSetGain ? nil : "—"
    }

    private func refresh() {
        configureMicRow()

        // Skip whichever row the pointer is currently dragging.
        if volumeRow.isTracking == false {
            volumeRow.level = SystemControls.isMuted() ? 0 : (SystemControls.volume() ?? 0)
        }
        if micRow.isTracking == false {
            micRow.isMuted = SystemControls.isInputMuted()
            micRow.level = micRow.isMuted ? 0 : (SystemControls.inputVolume() ?? 0)
        }
        if displayRow.isTracking == false, let level = SystemControls.displayBrightness() {
            displayRow.level = level
        }
        if keyboardRow.isTracking == false, let level = SystemControls.keyboardBacklight() {
            keyboardRow.level = level
        }
    }
}

/// Icon, label, draggable bar, percentage. Give it a `mutedSymbol` and the icon
/// becomes a button that toggles mute, which is how the microphone row works.
final class SystemSliderRow: NSView {
    var onChange: ((Double) -> Void)?
    var onToggleMute: (() -> Void)?

    var level: Double = 0 {
        didSet {
            bar.fraction = level
            valueLabel.stringValue = emptyText ?? "\(Int((level * 100).rounded()))%"
        }
    }

    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.35
            bar.isEnabled = isEnabled && isBarEnabled
            iconButton?.isEnabled = isEnabled
        }
    }

    /// A device can be mutable without being adjustable, so the bar is dimmed
    /// separately from the row: the icon still takes a click.
    var isBarEnabled = true {
        didSet {
            bar.isEnabled = isEnabled && isBarEnabled
            bar.alphaValue = isBarEnabled ? 1 : 0.3
        }
    }

    /// Shown in place of the percentage when there is no level to report.
    var emptyText: String? {
        didSet {
            guard emptyText != oldValue else { return }
            valueLabel.stringValue = emptyText ?? "\(Int((level * 100).rounded()))%"
        }
    }

    var isMuted = false {
        didSet {
            guard isMuted != oldValue, let mutedSymbol else { return }
            let symbol = isMuted ? mutedSymbol : symbol
            iconButton?.image = Style.symbolImage(symbol, pointSize: 12)
            iconButton?.contentTintColor = isMuted ? Style.tertiaryText : Style.primaryText
        }
    }

    var isTracking: Bool { bar.isTracking }

    private let bar = ProgressBarView()
    private let valueLabel = Style.label("0%", size: 10, color: Style.secondaryText)
    private let symbol: String
    private let mutedSymbol: String?
    private var iconButton: NSButton?

    init(symbol: String, title: String, mutedSymbol: String? = nil) {
        self.symbol = symbol
        self.mutedSymbol = mutedSymbol
        super.init(frame: .zero)

        let icon: NSView
        if mutedSymbol != nil {
            let button = Style.symbolButton(symbol, pointSize: 12, target: self, action: #selector(handleToggleMute))
            button.toolTip = title
            iconButton = button
            icon = button
        } else {
            let view = NSImageView()
            view.image = Style.symbolImage(symbol, pointSize: 12)
            view.contentTintColor = Style.primaryText
            view.toolTip = title
            icon = view
        }

        bar.onScrub = { [weak self] fraction in
            self?.level = fraction
            self?.onChange?(fraction)
        }

        let stack = NSStackView(views: [icon, bar, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            valueLabel.widthAnchor.constraint(equalToConstant: 34),
            bar.heightAnchor.constraint(equalToConstant: 5),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleToggleMute() {
        onToggleMute?()
    }
}
