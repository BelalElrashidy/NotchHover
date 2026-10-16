import AppKit

/// The one way to put a window on the macOS lock screen: a WindowServer space of our
/// own, raised to the level the lock screen's notification centre uses. The functions
/// are private SkyLight ones, looked up at run time and checked, so a macOS that drops
/// or renames them just means no lock screen card — never a crash.
///
/// The same technique Boring Notch uses (through the MIT-licensed SkyLightWindow
/// package); written out here so NotchHover keeps no dependencies.
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsToSpace = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private typealias RemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private struct Functions {
        let connection: MainConnectionID
        let create: SpaceCreate
        let setLevel: SpaceSetAbsoluteLevel
        let show: ShowSpaces
        let add: AddWindowsToSpace
        let remove: RemoveWindowsFromSpaces
    }

    /// The lock screen's notification centre sits at 400; the lock screen itself at 300.
    private static let level: Int32 = 400

    private lazy var functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let connection = symbol("SLSMainConnectionID", as: MainConnectionID.self),
              let create = symbol("SLSSpaceCreate", as: SpaceCreate.self),
              let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = symbol("SLSShowSpaces", as: ShowSpaces.self),
              let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsToSpace.self),
              let remove = symbol("SLSRemoveWindowsFromSpaces", as: RemoveWindowsFromSpaces.self) else {
            Log.ui.error("Lock screen: SkyLight functions not found on this macOS")
            return nil
        }
        return Functions(connection: connection, create: create, setLevel: setLevel, show: show, add: add, remove: remove)
    }()

    private var space: UInt64?

    var isAvailable: Bool { functions != nil }

    /// Created once, the first time a window needs it, and kept: an empty space shows
    /// nothing.
    private func makeSpace() -> UInt64? {
        if let space { return space }
        guard let functions else { return nil }
        let connection = functions.connection()
        let created = functions.create(connection, 1, nil)
        guard created != 0 else { return nil }
        _ = functions.setLevel(connection, created, Self.level)
        _ = functions.show(connection, [NSNumber(value: created)] as CFArray)
        space = created
        return created
    }

    /// Moves the window into the lock screen's space. False if that isn't possible.
    @discardableResult
    func add(_ window: NSWindow) -> Bool {
        guard let functions, let space = makeSpace() else { return false }
        return functions.add(functions.connection(), space, [NSNumber(value: window.windowNumber)] as CFArray, 7) == 0
    }

    func remove(_ window: NSWindow) {
        guard let functions, let space else { return }
        _ = functions.remove(functions.connection(), [NSNumber(value: window.windowNumber)] as CFArray, [NSNumber(value: space)] as CFArray)
    }
}

/// Music on the lock screen: artwork, title, artist and the three transport buttons,
/// in a card shaped like the peek, hanging from the notch. Nothing else is ever shown
/// there — no notifications, calendar, clipboard or notes — and it is off until
/// switched on in Settings.
///
/// It has its own window, made when the screen locks and thrown away when it unlocks;
/// the notch's panels never go near the lock screen.
final class LockScreenMusic {
    static let defaultsKey = "LockScreenMusic"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    private(set) var isLocked = false
    private var track: TrackInfo?
    private var window: NSPanel?
    private var peek: PeekView?
    private var artwork: NSImage?
    private var artworkKey: String?
    private var lyricsObserver: UUID?

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = true
            self?.refresh()
        }
        center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = false
            self?.refresh()
        }
        lyricsObserver = LyricsService.shared.addObserver { [weak self] _ in self?.render() }
    }

    /// Called with every poller reading.
    func update(_ track: TrackInfo?) {
        self.track = track
        loadArtwork(for: track)
        refresh()
    }

    private func refresh() {
        let wanted = isLocked && Self.isEnabled && track != nil
        if wanted, window == nil {
            open()
        } else if wanted == false, window != nil {
            close()
        }
        render()
    }

    private func open() {
        guard LockScreenSpace.shared.isAvailable,
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let geometry = NotchGeometry(screen: screen)
        let size = Self.cardSize(notchWidth: geometry.notchRect.width, bandHeight: geometry.notchRect.height)
        let frame = geometry.expandedFrame(size: size)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.canBecomeVisibleWithoutLogin = true
        panel.isReleasedWhenClosed = false

        let (card, peek) = Self.makeCard(size: size, notchWidth: geometry.notchRect.width, bandHeight: geometry.notchRect.height)
        peek.onPlayPause = { [weak self] in self?.onPlayPause?() }
        peek.onNext = { [weak self] in self?.onNext?() }
        peek.onPrevious = { [weak self] in self?.onPrevious?() }
        panel.contentView = card

        panel.orderFrontRegardless()
        guard LockScreenSpace.shared.add(panel) else {
            Log.ui.error("Lock screen: could not move the card to the lock screen")
            panel.close()
            return
        }
        window = panel
        self.peek = peek
        Log.ui.notice("Lock screen: showing music")
    }

    private func close() {
        guard let window else { return }
        LockScreenSpace.shared.remove(window)
        window.orderOut(nil)
        window.close()
        self.window = nil
        peek = nil
        Log.ui.notice("Lock screen: music card removed")
    }

    private func render() {
        guard let peek, let track else { return }
        peek.show(.playing(
            title: track.name,
            subtitle: LyricsService.shared.currentLine ?? [track.artist, track.sourceName].filter { $0.isEmpty == false }.joined(separator: " · "),
            icon: artwork ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: track.sourceBundleIdentifier).map { NSWorkspace.shared.icon(forFile: $0.path) },
            isPlaying: track.isPlaying,
            isControllable: true
        ))
    }

    private func loadArtwork(for track: TrackInfo?) {
        let key = track?.artworkURL?.absoluteString
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        guard let url = track?.artworkURL else { return }
        ArtworkLoader.shared.load(url) { [weak self] image in
            guard let self, self.artworkKey == key else { return }
            self.artwork = image
            self.render()
        }
    }

    /// The card and the peek row inside it. Separate so the preview draws the same thing.
    static func makeCard(size: CGSize, notchWidth: CGFloat, bandHeight: CGFloat) -> (NSView, PeekView) {
        let card = LockScreenCardView(frame: CGRect(origin: .zero, size: size))
        let peek = PeekView(notchWidth: notchWidth, bandHeight: bandHeight)
        peek.frame = card.bounds
        peek.autoresizingMask = [.width, .height]
        peek.bodyWidth = size.width - NotchShape.flare(in: card.bounds) * 2
        peek.isActive = true
        card.addSubview(peek)
        return (card, peek)
    }

    /// The peek's size: a little wider than the notch, one row deep.
    static func cardSize(notchWidth: CGFloat, bandHeight: CGFloat) -> CGSize {
        let height = bandHeight + PeekView.rowHeight
        let flare = min(NotchShape.topFlare, height * 0.55)
        return CGSize(width: notchWidth + (flare + 130) * 2, height: height)
    }

    /// Self-test hook: puts a card on the lock-screen space and takes it away again,
    /// without locking anything. Reports whether each step worked.
    static func probe() -> (available: Bool, added: Bool) {
        let space = LockScreenSpace.shared
        guard space.isAvailable else { return (false, false) }
        let panel = NSPanel(contentRect: CGRect(x: -100, y: -100, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let added = space.add(panel)
        space.remove(panel)
        panel.orderOut(nil)
        panel.close()
        return (true, added)
    }
}

/// The notch-shaped card behind the lock screen's music row, in the theme's colours.
/// There is nothing to see through to on the lock screen, so a glass theme gets a
/// solid stand-in that its text reads on.
final class LockScreenCardView: NSView {
    let shape = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let theme = Style.theme
        if case .solid(let color) = theme.surface {
            shape.fillColor = color.cgColor
        } else {
            let textIsLight = (theme.primaryText.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) > 0.5
            shape.fillColor = (textIsLight ? NSColor.black : NSColor.white).withAlphaComponent(0.9).cgColor
        }
        layer?.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        shape.frame = bounds
        shape.path = NotchShape.path(in: bounds, bottomRadius: min(22, NotchShape.bottomRadius))
    }
}
