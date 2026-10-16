import Foundation

/// Every view the open panel can show.
///
/// Only three are tabs — Home, Shelf and Notes, beside the notch. The rest are reached
/// from the buttons on the other side of the notch (clipboard, mirror), from Home's
/// cards, or by a keyboard shortcut. Thirteen tabs in a row along the bottom was the
/// layout this replaced.
enum PanelTab: Int, CaseIterable {
    case home
    case shelf
    case notes
    case clipboard
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

    /// The ones that get a place in the header, in order.
    static let headerTabs: [PanelTab] = [.home, .shelf, .notes]

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.fill"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard.fill"
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
        case .shelf: return "Shelf"
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        case .nowPlaying: return "Now Playing"
        case .playlists: return "Playlists"
        case .tray: return "Tray"
        case .shortcuts: return "Shortcuts"
        case .timer: return "Timer"
        case .system: return "Controls"
        case .calendar: return "Calendar"
        case .notifications: return "Notifications"
        case .apps: return "Apps"
        case .mirror: return "Mirror"
        }
    }
}
