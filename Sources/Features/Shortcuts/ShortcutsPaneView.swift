import AppKit

/// Runs macOS Shortcuts straight from the notch.
final class ShortcutsPaneView: NSView {
    private let titleLabel = Style.label("Shortcuts", size: 12, weight: .semibold)
    private let hintLabel = Style.label("", size: 11, color: Style.secondaryText)
    private let buttonStack = NSStackView()

    init() {
        super.init(frame: .zero)

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8

        let root = NSStackView(views: [titleLabel, buttonStack, hintLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        ShortcutsRunner.pinnedNames { [weak self] names in
            guard let self else { return }
            self.buttonStack.arrangedSubviews.forEach {
                self.buttonStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }

            for name in names {
                let button = Style.pushButton(name, prominent: false, target: self, action: #selector(self.handleRun(_:)))
                button.toolTip = name
                self.buttonStack.addArrangedSubview(button)
            }

            self.hintLabel.stringValue = names.isEmpty
                ? "No shortcuts found. Create one in the Shortcuts app."
                : "defaults write com.notchhover.NotchHover PinnedShortcuts -array …"
        }
    }

    @objc private func handleRun(_ sender: NSButton) {
        ShortcutsRunner.run(named: sender.title)
    }
}
