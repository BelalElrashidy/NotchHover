import AppKit

/// Pinned playlists, albums and songs — Spotify links, Music library playlists and
/// Apple Music links — started with one click. See `PinnedPlaylists`.
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
        playlists = PinnedPlaylists.entries.map { Playlist(name: $0.name, uri: $0.link) }

        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, playlist) in playlists.prefix(5).enumerated() {
            let button = Style.pushButton(playlist.name, prominent: index == 0, target: self, action: #selector(handlePlay(_:)))
            button.tag = index
            button.toolTip = "\(playlist.name) — \(PinnedPlaylists.Service(link: playlist.uri).title)"
            buttonStack.addArrangedSubview(button)
        }

        hintLabel.stringValue = playlists.isEmpty
            ? "Share a Spotify or Apple Music link to NotchHover, or add one in Settings → Music"
            : "Share → NotchHover on any Spotify or Apple Music link adds it here"
    }

    @objc private func handlePlay(_ sender: NSButton) {
        guard playlists.indices.contains(sender.tag) else { return }
        onPlay?(playlists[sender.tag].uri)
    }
}
