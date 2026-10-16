import AppKit

/// Something that can sit in the panel. Each declares how it wants to be sized, and
/// the row lays them out like a CSS flex line.
enum PanelWidget: String, CaseIterable {
    case media
    case playlists
    case tray
    case apps
    case shortcuts
    case timer
    case calendar
    case notifications
    case system
    case mirror
    case notes
    case clipboard
    case devices

    var title: String {
        switch self {
        case .media: return "Now playing"
        case .playlists: return "Playlists"
        case .tray: return "File tray"
        case .apps: return "Apps"
        case .shortcuts: return "Shortcuts"
        case .timer: return "Timer"
        case .calendar: return "Calendar"
        case .notifications: return "Notifications"
        case .system: return "Volume & brightness"
        case .mirror: return "Mirror"
        case .notes: return "Quick notes"
        case .clipboard: return "Clipboard"
        case .devices: return "Batteries"
        }
    }

    var symbol: String {
        switch self {
        case .media: return "play.circle"
        case .playlists: return "music.note.list"
        case .tray: return "tray.full"
        case .apps: return "square.grid.2x2"
        case .shortcuts: return "bolt"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .notifications: return "bell"
        case .system: return "slider.horizontal.3"
        case .mirror: return "video"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .devices: return "battery.75percent"
        }
    }

    /// Never rendered narrower than this; dropped instead.
    var minWidth: CGFloat {
        switch self {
        case .media: return 150
        case .system: return 150
        case .calendar: return 140
        case .notifications: return 160
        case .tray, .playlists, .shortcuts: return 130
        case .apps: return 110
        case .timer: return 120
        case .mirror: return 150
        case .notes: return 170
        case .clipboard: return 190
        case .devices: return 140
        }
    }

    /// What it would like if there is room.
    var idealWidth: CGFloat {
        switch self {
        case .media: return 250
        // Home is player, calendar and controls side by side; at their old widths the
        // panel opened to 860pt, well over half the screen. These keep it near 740.
        case .system: return 180
        case .calendar: return 170
        case .notifications: return 230
        case .tray: return 200
        case .playlists, .shortcuts: return 190
        case .apps: return 180
        case .timer: return 170
        case .mirror: return 200
        case .notes: return 240
        case .clipboard: return 280
        case .devices: return 180
        }
    }

    /// Share of the leftover space this absorbs, flex-grow style.
    var grow: CGFloat {
        switch self {
        case .media: return 1.4
        case .calendar, .notifications, .system: return 1
        case .tray, .playlists, .shortcuts, .mirror: return 0.8
        case .apps, .timer, .devices: return 0.4
        case .notes, .clipboard: return 1.2
        }
    }

    /// Lower goes first when the row runs out of room.
    var dropPriority: Int {
        switch self {
        case .media: return 100
        case .tray: return 80
        case .apps: return 70
        case .system: return 60
        case .notifications: return 50
        case .calendar: return 40
        case .timer: return 30
        case .playlists: return 20
        case .shortcuts: return 15
        case .mirror: return 10
        case .clipboard: return 90
        case .notes: return 85
        case .devices: return 35
        }
    }
}

/// How much room a widget ended up with, so it can render accordingly.
enum WidgetSizeClass {
    case mini
    case compact
    case regular

    init(width: CGFloat) {
        switch width {
        case ..<170: self = .mini
        case ..<240: self = .compact
        default: self = .regular
        }
    }
}

/// The ordered list of widgets in the panel.
enum PanelLayoutStore {
    static let defaultsKey = "PanelWidgets"

    /// Bumped when the default Home changes in a way everyone should get once.
    private static let revisionKey = "PanelWidgetsRevision"
    private static let revision = 2

    static var widgets: [PanelWidget] {
        // Revision 2: Home became player, calendar and controls when the tabs moved
        // beside the notch and files and clips got a Shelf of their own. A layout
        // saved before that is moved over once; anything chosen after is kept.
        if UserDefaults.standard.integer(forKey: revisionKey) < revision {
            UserDefaults.standard.set(revision, forKey: revisionKey)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            legacyZoneKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        }

        if let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            let resolved = stored.compactMap(PanelWidget.init(rawValue:))
            return resolved.isEmpty ? defaultWidgets : resolved
        }
        // Carried over from when the panel had three fixed zones — but only for someone
        // who actually set one. Without that check the old zones' fallbacks answered
        // for everybody, and the default below could never be reached.
        guard legacyZoneKeys.contains(where: { UserDefaults.standard.string(forKey: $0) != nil }) else {
            return defaultWidgets
        }
        // A position that was never set keeps its old default; "empty" drops out.
        let legacy: [(key: String, fallback: PanelWidget)] = [
            ("ZoneLeft", .media), ("ZoneMiddle", .tray), ("ZoneRight", .apps)
        ]
        let migrated = legacy.compactMap { entry -> PanelWidget? in
            guard let stored = UserDefaults.standard.string(forKey: entry.key) else { return entry.fallback }
            return PanelWidget(rawValue: stored)
        }
        return migrated.isEmpty ? defaultWidgets : migrated
    }

    static let defaultWidgets: [PanelWidget] = [.media, .calendar, .system]

    private static let legacyZoneKeys = ["ZoneLeft", "ZoneMiddle", "ZoneRight"]

    static func set(_ widgets: [PanelWidget]) {
        UserDefaults.standard.set(widgets.map(\.rawValue), forKey: defaultsKey)
    }
}
