import AppKit

/// Detail pane for a Claude Code permission request. Approve and Deny are the only
/// ways out other than the timeout, which defers to Claude Code's own prompt.
final class PermissionDetailView: NSView {
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?

    private let headlineLabel = Style.label(size: 12, weight: .semibold)
    private let toolLabel = Style.label(size: 12, weight: .semibold, color: Style.primaryText)
    private let detailLabel = Style.label(size: 11, color: Style.secondaryText, monospaced: true)
    private let queueLabel = Style.label(size: 10, color: Style.tertiaryText)
    private lazy var approveButton = Style.pushButton("Approve", prominent: true, target: self, action: #selector(handleApprove))
    private lazy var denyButton = Style.pushButton("Deny", prominent: false, target: self, action: #selector(handleDeny))

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingMiddle

        let iconView = NSImageView()
        iconView.image = Style.symbolImage("hand.raised.fill", pointSize: 13)
        iconView.contentTintColor = Style.accent

        let headline = NSStackView(views: [iconView, headlineLabel])
        headline.orientation = .horizontal
        headline.alignment = .centerY
        headline.spacing = 6

        let buttons = NSStackView(views: [approveButton, denyButton, queueLabel])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let rootStack = NSStackView(views: [headline, toolLabel, detailLabel, buttons])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            detailLabel.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rootStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func render(request: PermissionRequest, queued: Int) {
        headlineLabel.stringValue = "Claude Code · \(request.projectName)"
        toolLabel.stringValue = request.toolName
        detailLabel.stringValue = request.detail
        detailLabel.toolTip = request.detail
        queueLabel.stringValue = queued > 0 ? "+\(queued) more waiting" : ""
    }

    @objc private func handleApprove() { onApprove?() }
    @objc private func handleDeny() { onDeny?() }
}
