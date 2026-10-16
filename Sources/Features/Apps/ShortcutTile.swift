import AppKit

/// One app icon in the shortcut row, with a dot marking apps that are already running.
final class ShortcutTile: NSView {
    var onActivate: (() -> Void)?

    private let button: ClickThroughButton
    private let runningDot = NSView()
    private let iconSize: CGFloat

    init(shortcut: AppShortcut, iconSize: CGFloat) {
        self.iconSize = iconSize

        let icon = shortcut.icon
        icon.size = NSSize(width: iconSize, height: iconSize)
        button = ClickThroughButton(image: icon, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.imagePosition = .imageOnly
        button.toolTip = shortcut.name

        super.init(frame: .zero)

        button.target = self
        button.action = #selector(handleClick)

        runningDot.wantsLayer = true
        runningDot.layer?.cornerRadius = 2
        runningDot.layer?.backgroundColor = Style.secondaryText.cgColor
        runningDot.alphaValue = 0

        let stack = NSStackView(views: [button, runningDot])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: iconSize),
            button.heightAnchor.constraint(equalToConstant: iconSize),
            runningDot.widthAnchor.constraint(equalToConstant: 4),
            runningDot.heightAnchor.constraint(equalToConstant: 4),
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

    func setRunning(_ isRunning: Bool) {
        runningDot.alphaValue = isRunning ? 1 : 0
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        animateIcon(scale: 1.12)
    }

    override func mouseExited(with event: NSEvent) {
        animateIcon(scale: 1)
    }

    private func animateIcon(scale: CGFloat) {
        guard let layer = button.layer else { return }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: button.frame.midX, y: button.frame.midY)

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.toValue = scale
        animation.duration = 0.12
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "hoverScale")
    }

    @objc private func handleClick() {
        onActivate?()
    }
}
