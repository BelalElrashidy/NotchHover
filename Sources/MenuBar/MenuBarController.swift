import AppKit

final class MenuBarController: NSObject {
    private enum Constants {
        static let maxStatusLength = 44
    }

    private let mediaController: MediaControlling
    private let poller: NowPlayingPoller
    private let statusItem: NSStatusItem
    private let menu: NSMenu

    private let nowPlayingItem = NSMenuItem(title: "Now Playing: --", action: nil, keyEquivalent: "")
    private lazy var playPauseItem = NSMenuItem(title: "Play/Pause", action: #selector(handlePlayPause), keyEquivalent: "p")
    private lazy var nextTrackItem = NSMenuItem(title: "Next Track", action: #selector(handleNextTrack), keyEquivalent: "n")
    private lazy var previousTrackItem = NSMenuItem(title: "Previous Track", action: #selector(handlePreviousTrack), keyEquivalent: "b")
    private let shortcutsItem = NSMenuItem(title: "Open App", action: nil, keyEquivalent: "")
    private lazy var settingsItem = NSMenuItem(title: "Settings…", action: #selector(handleSettings), keyEquivalent: ",")
    private lazy var quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q")

    var onOpenSettings: (() -> Void)?
    private var shortcuts: [AppShortcut] = []

    init(mediaController: MediaControlling, poller: NowPlayingPoller) {
        self.mediaController = mediaController
        self.poller = poller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()
        super.init()
        configureStatusItem()
        configureMenu()
    }

    func start() {
        poller.addObserver { [weak self] result in
            self?.apply(result)
        }
    }

    func stop() {}

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        // The Capstone mark, as a template so macOS tints it for light and dark menu bars.
        if let image = Bundle.main.image(forResource: "MenuBarIcon") ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "NotchHover"
            button.image = image
            button.imagePosition = .imageLeading
        }

        button.title = "--"
        button.toolTip = "NotchHover"
    }

    private func configureMenu() {
        nowPlayingItem.isEnabled = false

        playPauseItem.target = self
        nextTrackItem.target = self
        previousTrackItem.target = self
        quitItem.target = self
        settingsItem.target = self

        shortcutsItem.submenu = makeShortcutsMenu()

        menu.items = [
            nowPlayingItem,
            NSMenuItem.separator(),
            playPauseItem,
            nextTrackItem,
            previousTrackItem,
            NSMenuItem.separator(),
            shortcutsItem,
            settingsItem,
            NSMenuItem.separator(),
            quitItem
        ]

        statusItem.menu = menu
    }

    private func makeShortcutsMenu() -> NSMenu {
        shortcuts = AppShortcutStore.shortcuts()
        let submenu = NSMenu()

        for (index, shortcut) in shortcuts.enumerated() {
            let item = NSMenuItem(title: shortcut.name, action: #selector(handleShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            let icon = shortcut.icon
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            submenu.addItem(item)
        }

        if shortcuts.isEmpty {
            submenu.addItem(NSMenuItem(title: "No apps configured", action: nil, keyEquivalent: ""))
        }

        return submenu
    }

    private func apply(_ result: Result<TrackInfo?, MediaError>) {
        switch result {
        case .success(let track):
            Log.media.notice("Fetched track: \(track?.menuBarText ?? "nil", privacy: .public) playing=\(track?.isPlaying == true, privacy: .public)")
            updateUI(with: track, error: nil)
        case .failure(let error):
            Log.media.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            updateUI(with: nil, error: error)
        }
    }

    private func updateUI(with track: TrackInfo?, error: MediaError?) {
        guard let button = statusItem.button else { return }

        if let track {
            let text = track.menuBarText
            button.title = truncate(" " + text, maxLength: Constants.maxStatusLength)
            button.toolTip = "\(text) — \(track.sourceName)"
            nowPlayingItem.title = "Now Playing: \(text)"
            return
        }

        let fallback = error?.shortDisplayText ?? "Nothing playing"
        button.title = " " + fallback
        button.toolTip = error?.localizedDescription ?? "No track currently playing"
        nowPlayingItem.title = "Now Playing: \(fallback)"
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 1 else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength - 1)
        return String(text[..<end]) + "…"
    }

    private func perform(_ action: MediaAction) {
        mediaController.control(action) { [weak self] result in
            if case .failure(let error) = result {
                Log.media.error("Control \(String(describing: action), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            // Players report the outgoing track for a moment after a skip, so give
            // them a beat before asking again.
            self?.poller.refreshSoon()
        }
    }

    @objc private func handlePlayPause() {
        perform(.playPause)
    }

    @objc private func handleNextTrack() {
        perform(.nextTrack)
    }

    @objc private func handlePreviousTrack() {
        perform(.previousTrack)
    }

    @objc private func handleShortcut(_ sender: NSMenuItem) {
        guard shortcuts.indices.contains(sender.tag) else { return }
        AppShortcutStore.activate(shortcuts[sender.tag])
    }

    @objc private func handleSettings() {
        onOpenSettings?()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
