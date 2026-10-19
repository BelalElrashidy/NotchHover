import Foundation

/// Every view the open panel can show.
///
/// Home is always the first tab left of the notch. Which others sit beside it, which
/// are circles on the right, and which are left out is yours to choose — see
/// `HeaderLayout`. The rest are reached from Home's cards or a keyboard shortcut.
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
    case screenshots

    /// The tabs left of the notch, in order: Home, then your choice.
    static var headerTabs: [PanelTab] { [.home] + HeaderLayout.left }

    /// The same symbol without its fill, for the circles right of the notch.
    var outlineSymbol: String {
        symbol.hasSuffix(".fill") ? String(symbol.dropLast(5)) : symbol
    }

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
        case .screenshots: return "camera.viewfinder"
        }
    }

    /// Its key in the open panel, shown in tooltips so shortcuts can be found by hovering.
    var shortcut: String? {
        switch self {
        case .home: return "⌘1"
        case .shelf: return "⌘2"
        case .notes: return "⌘3"
        case .clipboard: return "⌘4"
        case .mirror: return "⌘5"
        case .screenshots: return "⌘6"
        default: return nil
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
        case .screenshots: return "Screenshots"
        }
    }
}

/// Which views sit beside the notch: tabs on the left after Home, circles on the right
/// before the gear, and the ones you've left out. Saved as two ordered lists.
enum HeaderLayout {
    enum Place: Int, CaseIterable {
        case left, right, hidden

        var title: String {
            switch self {
            case .left: return "Left"
            case .right: return "Right"
            case .hidden: return "Off"
            }
        }
    }

    static let leftKey = "HeaderLeftTabs"
    static let rightKey = "HeaderRightTabs"

    /// What can be placed. Home is always there; the rest of the panel's views are
    /// reached from Home, so they can be given a place too.
    static let movable: [PanelTab] = [
        .shelf, .notes, .screenshots, .clipboard, .mirror, .calendar, .timer,
        .nowPlaying, .playlists, .apps, .shortcuts, .system, .notifications
    ]

    /// The wings beside the notch are narrow: past this, tabs would run under it.
    static let maxLeft = 4
    static let maxRight = 4

    private static let defaultLeft: [PanelTab] = [.shelf, .notes, .screenshots]
    private static let defaultRight: [PanelTab] = [.clipboard, .mirror]

    static var left: [PanelTab] { read(leftKey, default: defaultLeft, limit: maxLeft) }
    static var right: [PanelTab] { read(rightKey, default: defaultRight, limit: maxRight).filter { left.contains($0) == false } }

    /// Home, the left tabs, then the right circles — the order ⌃⇥ and a sideways swipe
    /// step through.
    static var cycle: [PanelTab] { [.home] + left + right }

    static func place(of tab: PanelTab) -> Place {
        if left.contains(tab) { return .left }
        if right.contains(tab) { return .right }
        return .hidden
    }

    /// False when that side is already full.
    static func canMove(_ tab: PanelTab, to place: Place) -> Bool {
        switch place {
        case .left: return left.contains(tab) || left.count < maxLeft
        case .right: return right.contains(tab) || right.count < maxRight
        case .hidden: return true
        }
    }

    static func move(_ tab: PanelTab, to place: Place) {
        guard tab != .home, canMove(tab, to: place) else { return }
        var left = self.left.filter { $0 != tab }
        var right = self.right.filter { $0 != tab }
        switch place {
        case .left: left.append(tab)
        case .right: right.append(tab)
        case .hidden: break
        }
        write(left: left, right: right)
    }

    /// One step earlier (-1) or later (+1) on its own side.
    static func shift(_ tab: PanelTab, by step: Int) {
        var left = self.left, right = self.right
        if let index = left.firstIndex(of: tab) {
            let target = index + step
            guard left.indices.contains(target) else { return }
            left.swapAt(index, target)
        } else if let index = right.firstIndex(of: tab) {
            let target = index + step
            guard right.indices.contains(target) else { return }
            right.swapAt(index, target)
        }
        write(left: left, right: right)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: leftKey)
        UserDefaults.standard.removeObject(forKey: rightKey)
    }

    private static func write(left: [PanelTab], right: [PanelTab]) {
        UserDefaults.standard.set(left.map(\.rawValue), forKey: leftKey)
        UserDefaults.standard.set(right.map(\.rawValue), forKey: rightKey)
    }

    private static func read(_ key: String, default fallback: [PanelTab], limit: Int) -> [PanelTab] {
        // Numbers, or numbers written as text by `defaults write`.
        guard let raw = UserDefaults.standard.array(forKey: key)?.compactMap({ ($0 as? Int) ?? Int("\($0)") }) else { return fallback }
        var seen = Set<PanelTab>()
        return Array(raw.compactMap(PanelTab.init(rawValue:))
            .filter { movable.contains($0) && seen.insert($0).inserted }
            .prefix(limit))
    }
}
