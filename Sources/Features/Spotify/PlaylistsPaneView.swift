import AppKit

/// Spotify's AppleScript dictionary cannot list your library, but it will play any
/// URI — so playlists are pinned by URI and started with one click.
final class PlaylistsPaneView: NSView {
    struct Playlist {
        let name: String
        let uri: String
    }

    static let defaultsKey = "Playlists"

    var onPlay: ((String) -> Void)?

    private let titleLabel = Style.label("Playlists", size: 12, weight: .semibold)
    private let hintLabel = Style.label("", size: 10, color: Style.tertiaryText)
    private let buttonStack = NSStackView()
    private var playlists: [Playlist] = []

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
        // Stored as "Name|spotify:playlist:id" entries.
        playlists = (UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
            .compactMap { entry in
                let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return Playlist(name: parts[0], uri: parts[1])
            }

        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, playlist) in playlists.prefix(5).enumerated() {
            let button = Style.pushButton(playlist.name, prominent: index == 0, target: self, action: #selector(handlePlay(_:)))
            button.tag = index
            button.toolTip = playlist.uri
            buttonStack.addArrangedSubview(button)
        }

        hintLabel.stringValue = playlists.isEmpty
            ? "Add with: defaults write com.notchhover.NotchHover Playlists -array \"Focus|spotify:playlist:ID\""
            : "Right-click a playlist in Spotify → Share → Copy Spotify URI"
    }

    @objc private func handlePlay(_ sender: NSButton) {
        guard playlists.indices.contains(sender.tag) else { return }
        onPlay?(playlists[sender.tag].uri)
    }
}
