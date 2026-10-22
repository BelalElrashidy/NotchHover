import AppKit

/// Quick countdowns, mirrored into the resting bar while they run.
final class TimerPaneView: NSView {
    var onStart: ((Int) -> Void)?
    var onCancel: (() -> Void)?

    private let remainingLabel = Style.label("No timer running", size: 13, weight: .semibold)
    private lazy var cancelButton = Style.pushButton("Cancel", prominent: false, target: self, action: #selector(handleCancel))
    private let presets = [1, 5, 10, 25]

    init() {
        super.init(frame: .zero)

        // The presets share the width equally, however narrow the column is; in a row
        // that was allowed to shrink they used to pile on top of each other.
        let presetStack = NSStackView()
        presetStack.orientation = .horizontal
        presetStack.distribution = .fillEqually
        presetStack.spacing = 6
        for minutes in presets {
            let button = Style.pushButton("\(minutes)m", prominent: false, target: self, action: #selector(handlePreset(_:)))
            button.tag = minutes
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // The panel's buttons size themselves to their title; here the row decides.
            button.constraints.filter { $0.firstAttribute == .width }.forEach { $0.isActive = false }
            presetStack.addArrangedSubview(button)
        }

        // The countdown, with Cancel beside it only while one is running.
        remainingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        let header = NSStackView(views: [remainingLabel, cancelButton])
        header.orientation = .horizontal
        header.spacing = 8

        let root = NSStackView(views: [header, presetStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            presetStack.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        update(remaining: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(remaining: TimeInterval) {
        let running = remaining > 0
        remainingLabel.stringValue = running ? CountdownTimer.format(remaining) : "No timer running"
        cancelButton.isHidden = running == false
    }

    @objc private func handlePreset(_ sender: NSButton) {
        onStart?(sender.tag)
    }

    @objc private func handleCancel() {
        onCancel?()
    }
}
