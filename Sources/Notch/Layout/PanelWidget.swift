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
        }
    }

    /// Never rendered narrower than this; dropped instead.
    var minWidth: CGFloat {
        switch self {
        case .media: return 150
        case .system: return 170
        case .calendar, .notifications: return 160
        case .tray, .playlists, .shortcuts: return 130
        case .apps: return 110
        case .timer: return 120
        case .mirror: return 150
        case .notes: return 170
        case .clipboard: return 190
        }
    }

    /// What it would like if there is room.
    var idealWidth: CGFloat {
        switch self {
        case .media: return 250
        case .system: return 240
        case .calendar, .notifications: return 230
        case .tray: return 200
        case .playlists, .shortcuts: return 190
        case .apps: return 180
        case .timer: return 170
        case .mirror: return 200
        case .notes: return 240
        case .clipboard: return 280
        }
    }

    /// Share of the leftover space this absorbs, flex-grow style.
    var grow: CGFloat {
        switch self {
        case .media: return 1.4
        case .calendar, .notifications, .system: return 1
        case .tray, .playlists, .shortcuts, .mirror: return 0.8
        case .apps, .timer: return 0.4
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

    static var widgets: [PanelWidget] {
        if let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            let resolved = stored.compactMap(PanelWidget.init(rawValue:))
            return resolved.isEmpty ? defaultWidgets : resolved
        }
        // Carried over from when the panel had three fixed zones. A position that was
        // never set keeps its old default; "empty" simply drops out.
        let legacy: [(key: String, fallback: PanelWidget)] = [
            ("ZoneLeft", .media), ("ZoneMiddle", .tray), ("ZoneRight", .apps)
        ]
        let migrated = legacy.compactMap { entry -> PanelWidget? in
            guard let stored = UserDefaults.standard.string(forKey: entry.key) else { return entry.fallback }
            return PanelWidget(rawValue: stored)
        }
        return migrated.isEmpty ? defaultWidgets : migrated
    }

    static let defaultWidgets: [PanelWidget] = [.media, .tray, .apps]

    static func set(_ widgets: [PanelWidget]) {
        UserDefaults.standard.set(widgets.map(\.rawValue), forKey: defaultsKey)
    }
}
