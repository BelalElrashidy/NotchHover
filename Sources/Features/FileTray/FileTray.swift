import AppKit

/// Files parked on the notch. Nothing is copied — the tray holds references, and
/// clearing it never touches the originals.
final class FileTray {
    static let shared = FileTray()

    private(set) var items: [URL] = []
    var onChange: (() -> Void)?

    private let maximumItems = 12

    func add(_ urls: [URL]) {
        for url in urls where items.contains(url) == false {
            items.insert(url, at: 0)
        }
        if items.count > maximumItems {
            items = Array(items.prefix(maximumItems))
        }
        Log.system.notice("Tray now holds \(self.items.count, privacy: .public) item(s)")
        onChange?()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        onChange?()
    }

    func clear() {
        items.removeAll()
        onChange?()
    }

    func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Hands the tray to the system share sheet, which is where AirDrop lives.
    func share(from view: NSView) {
        guard items.isEmpty == false else { return }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func revealInFinder() {
        guard items.isEmpty == false else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items)
    }
}
