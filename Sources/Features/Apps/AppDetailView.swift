import AppKit

/// Detail pane for a single app: what it is doing right now, plus a way in.
final class AppDetailView: NSView {
    var onOpen: (() -> Void)?
    var onBack: (() -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = Style.label(size: 13, weight: .semibold)
    private let statusLabel = Style.label(size: 11, color: Style.secondaryText)
    private let linesStack = NSStackView()
    private lazy var openButton = Style.pushButton("Open", prominent: true, target: self, action: #selector(handleOpen))
    private lazy var backButton = Style.pushButton("Back", prominent: false, target: self, action: #selector(handleBack))

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let titleStack = NSStackView(views: [nameLabel, statusLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let header = NSStackView(views: [iconView, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        linesStack.orientation = .vertical
        linesStack.alignment = .leading
        linesStack.spacing = 3

        let buttons = NSStackView(views: [openButton, backButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let rootStack = NSStackView(views: [header, linesStack, buttons])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
            header.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rootStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func render(_ details: AppDetails) {
        let icon = details.shortcut.icon
        icon.size = NSSize(width: 34, height: 34)
        iconView.image = icon
        nameLabel.stringValue = details.shortcut.name
        statusLabel.stringValue = details.statusText

        linesStack.arrangedSubviews.forEach {
            linesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for line in details.lines.prefix(4) {
            let key = Style.label(line.label, size: 11, color: Style.tertiaryText)
            let value = Style.label(line.value, size: 11, color: Style.secondaryText)
            let row = NSStackView(views: [key, value])
            row.orientation = .horizontal
            row.spacing = 8
            key.widthAnchor.constraint(equalToConstant: 86).isActive = true
            linesStack.addArrangedSubview(row)
        }
    }

    @objc private func handleOpen() { onOpen?() }
    @objc private func handleBack() { onBack?() }
}
