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

        let presetStack = NSStackView()
        presetStack.orientation = .horizontal
        presetStack.spacing = 8
        for minutes in presets {
            let button = Style.pushButton("\(minutes)m", prominent: false, target: self, action: #selector(handlePreset(_:)))
            button.tag = minutes
            presetStack.addArrangedSubview(button)
        }

        let row = NSStackView(views: [presetStack, cancelButton])
        row.orientation = .horizontal
        row.spacing = 12

        let root = NSStackView(views: [remainingLabel, row])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor)
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
        cancelButton.isEnabled = running
        cancelButton.alphaValue = running ? 1 : 0.4
    }

    @objc private func handlePreset(_ sender: NSButton) {
        onStart?(sender.tag)
    }

    @objc private func handleCancel() {
        onCancel?()
    }
}
