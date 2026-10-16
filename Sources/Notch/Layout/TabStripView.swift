import AppKit

/// Bottom strip that switches the detail pane.
final class TabStripView: NSView {
    enum Tab: Int, CaseIterable {
        case home
        case clipboard
        case notes
        case nowPlaying
        case playlists
        case tray
        case shortcuts
        case timer
        case system
        case calendar
        case notifications
        case apps
        case mirror

        var symbol: String {
            switch self {
            case .home: return "rectangle.split.3x1.fill"
            case .clipboard: return "doc.on.clipboard.fill"
            case .notes: return "note.text"
            case .nowPlaying: return "play.circle.fill"
            case .playlists: return "music.note.list"
            case .tray: return "tray.full.fill"
            case .shortcuts: return "bolt.fill"
            case .timer: return "timer"
            case .system: return "slider.horizontal.3"
            case .calendar: return "calendar"
            case .notifications: return "bell.fill"
            case .apps: return "square.grid.2x2.fill"
            case .mirror: return "video.fill"
            }
        }

        var title: String {
            switch self {
            case .home: return "Home"
            case .clipboard: return "Clipboard — ⌃⌥V"
            case .notes: return "Quick notes — ⌃⌥N"
            case .nowPlaying: return "Now Playing"
            case .playlists: return "Playlists"
            case .tray: return "Tray"
            case .shortcuts: return "Shortcuts"
            case .timer: return "Timer"
            case .system: return "Volume, microphone, brightness, keyboard"
            case .calendar: return "Calendar"
            case .notifications: return "Notifications"
            case .apps: return "Apps"
            case .mirror: return "Mirror"
            }
        }
    }

    var onSelect: ((Tab) -> Void)?
    var onOpenSettings: (() -> Void)?
    private(set) var selected: Tab = .nowPlaying

    private var buttons: [Tab: NSButton] = [:]

    init() {
        super.init(frame: .zero)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for tab in Tab.allCases {
            let button = Style.symbolButton(tab.symbol, pointSize: 13, target: self, action: #selector(handleTab(_:)))
            button.tag = tab.rawValue
            button.toolTip = tab.title
            buttons[tab] = button
            stack.addArrangedSubview(button)
        }

        // Settings sits apart from the tabs: it opens a window rather than switching panes.
        let settingsButton = Style.symbolButton("gearshape.fill", pointSize: 13, target: self, action: #selector(handleSettings))
        settingsButton.toolTip = "Settings"
        settingsButton.contentTintColor = Style.tertiaryText
        addSubview(settingsButton)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        select(.home, notify: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ tab: Tab, notify: Bool = true) {
        selected = tab
        for (candidate, button) in buttons {
            let active = candidate == tab
            button.contentTintColor = active ? Style.accent : Style.tertiaryText
            button.alphaValue = active ? 1 : 0.85
        }
        if notify {
            onSelect?(tab)
        }
    }

    @objc private func handleSettings() {
        onOpenSettings?()
    }

    @objc private func handleTab(_ sender: NSButton) {
        guard let tab = Tab(rawValue: sender.tag) else { return }
        select(tab)
    }
}
