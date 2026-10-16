import AppKit

/// Recent notification banners, or the prompt to allow reading them.
final class NotificationsPaneView: NSView {
    private let titleLabel = Style.label("Notifications", size: 12, weight: .semibold)
    private let statusLabel = Style.label("", size: 11, color: Style.secondaryText)
    private let listStack = NSStackView()
    private lazy var grantButton = Style.pushButton("Allow", prominent: true, target: self, action: #selector(handleGrant))

    init() {
        super.init(frame: .zero)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 4

        let root = NSStackView(views: [titleLabel, listStack, statusLabel, grantButton])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 6
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let trusted = NotificationWatcher.isTrusted
        grantButton.isHidden = trusted

        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard trusted else {
            statusLabel.stringValue = "Reading notifications needs Accessibility access"
            return
        }

        let recent = NotificationWatcher.shared.recent
        guard recent.isEmpty == false else {
            statusLabel.stringValue = "Nothing captured yet — banners appear here as they arrive"
            return
        }

        statusLabel.stringValue = ""
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        for notification in recent.prefix(4) {
            let time = Style.label(formatter.string(from: notification.date), size: 10, color: Style.tertiaryText)
            time.widthAnchor.constraint(equalToConstant: 40).isActive = true

            let app = Style.label(notification.appName, size: 11, weight: .semibold)
            app.widthAnchor.constraint(equalToConstant: 90).isActive = true

            let text = Style.label(notification.summary, size: 11, color: Style.secondaryText)
            text.toolTip = notification.summary

            let row = NSStackView(views: [time, app, text])
            row.orientation = .horizontal
            row.spacing = 8
            listStack.addArrangedSubview(row)
        }
    }

    @objc private func handleGrant() {
        NotificationWatcher.requestTrust()
        NotificationWatcher.openAccessibilitySettings()
    }
}
