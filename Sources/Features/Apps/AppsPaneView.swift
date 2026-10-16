import AppKit

/// The app launcher row, moved out of the media pane.
final class AppsPaneView: NSView {
    var onSelect: ((AppShortcut) -> Void)?

    private let row = NSStackView()
    private var shortcuts: [AppShortcut] = []
    private let isCompact: Bool

    init(isCompact: Bool = false) {
        self.isCompact = isCompact
        super.init(frame: .zero)

        row.orientation = isCompact ? .vertical : .horizontal
        row.alignment = isCompact ? .centerX : .centerY
        row.distribution = isCompact ? .fillEqually : .equalSpacing
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        shortcuts = AppShortcutStore.shortcuts()
        row.arrangedSubviews.forEach {
            row.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard isCompact else {
            for shortcut in shortcuts {
                row.addArrangedSubview(makeTile(for: shortcut, size: 32))
            }
            return
        }

        // Two rows of three, so a narrow zone never clips the last app.
        for start in stride(from: 0, to: shortcuts.count, by: 3) {
            let line = NSStackView()
            line.orientation = .horizontal
            line.alignment = .centerY
            line.spacing = 10
            for shortcut in shortcuts[start..<min(start + 3, shortcuts.count)] {
                line.addArrangedSubview(makeTile(for: shortcut, size: 26))
            }
            row.addArrangedSubview(line)
        }
    }

    private func makeTile(for shortcut: AppShortcut, size: CGFloat) -> ShortcutTile {
        let tile = ShortcutTile(shortcut: shortcut, iconSize: size)
        tile.onActivate = { [weak self] in self?.onSelect?(shortcut) }
        return tile
    }

    private var allTiles: [ShortcutTile] {
        row.arrangedSubviews.flatMap { view -> [ShortcutTile] in
            if let tile = view as? ShortcutTile { return [tile] }
            return (view as? NSStackView)?.arrangedSubviews.compactMap { $0 as? ShortcutTile } ?? []
        }
    }

    func refreshRunningStates() {
        for (index, tile) in allTiles.enumerated() where index < shortcuts.count {
            tile.setRunning(shortcuts[index].isRunning)
        }
    }
}
