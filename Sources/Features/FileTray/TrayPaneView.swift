import AppKit

/// The file shelf: drop files on the notch, drag them back out, or AirDrop them.
final class TrayPaneView: NSView {
    private let hintLabel = Style.label("Drop files on the notch to park them", size: 11, color: Style.secondaryText)
    private let itemsStack = NSStackView()
    private lazy var shareButton = Style.pushButton("Send", prominent: true, target: self, action: #selector(handleShare))
    private lazy var revealButton = Style.pushButton("Reveal", prominent: false, target: self, action: #selector(handleReveal))
    private lazy var clearButton = Style.pushButton("Clear", prominent: false, target: self, action: #selector(handleClear))

    private let isCompact: Bool

    init(isCompact: Bool = false) {
        self.isCompact = isCompact
        super.init(frame: .zero)

        itemsStack.orientation = .horizontal
        itemsStack.alignment = .centerY
        itemsStack.spacing = 10

        // Reveal does not earn its width in a zone column.
        let buttons = NSStackView(views: isCompact ? [shareButton, clearButton] : [shareButton, revealButton, clearButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let root = NSStackView(views: [hintLabel, itemsStack, buttons])
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

        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let items = FileTray.shared.items
        hintLabel.stringValue = items.isEmpty
            ? (isCompact ? "Drop files here" : "Drop files on the notch to park them")
            : (isCompact
                ? "\(items.count) item\(items.count == 1 ? "" : "s")"
                : "\(items.count) item\(items.count == 1 ? "" : "s") · drag one out, or send")

        itemsStack.arrangedSubviews.forEach {
            itemsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for url in items.prefix(isCompact ? 4 : 8) {
            itemsStack.addArrangedSubview(TrayItemView(url: url))
        }

        [shareButton, revealButton, clearButton].forEach {
            $0.isEnabled = items.isEmpty == false
            $0.alphaValue = items.isEmpty ? 0.4 : 1
        }
    }

    @objc private func handleShare() {
        FileTray.shared.share(from: shareButton)
    }

    @objc private func handleReveal() {
        FileTray.shared.revealInFinder()
    }

    @objc private func handleClear() {
        FileTray.shared.clear()
    }
}

/// One parked file: shows its icon and can be dragged straight back out.
final class TrayItemView: NSView {
    private let url: URL
    private let imageView = ClickThroughImageView()

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 30, height: 30)
        imageView.image = icon
        imageView.toolTip = url.lastPathComponent
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 30),
            imageView.heightAnchor.constraint(equalToConstant: 30),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: imageView.image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
}

extension TrayItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy out of the tray: the file itself never moves.
        .copy
    }
}
