import AppKit

/// Screenshots, wherever they're saved. NotchHover doesn't take over the screenshot
/// keys: it watches the folder macOS writes to (Desktop unless you changed it) and the
/// one you chose for NotchHover's own, and notices each new one as it lands, by the
/// marker macOS puts on every screenshot. It can also take one itself, through the same
/// `screencapture` tool ⇧⌘4 uses.
final class ScreenshotStore {
    static let shared = ScreenshotStore()

    private(set) var items: [URL] = []
    /// A new screenshot arrived — the notch shows it.
    var onNew: ((URL) -> Void)?

    private var observers: [UUID: () -> Void] = [:]
    private var sources: [DispatchSourceFileSystemObject] = []
    private let queue = DispatchQueue(label: "com.notchhover.screenshots", qos: .utility)
    private var known = Set<URL>()
    private static let recentLimit = 30

    static let folderKey = "ScreenshotFolder"

    /// Where macOS saves screenshots: the Screenshot app's choice, or the Desktop.
    static var systemFolder: URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let location = defaults?.string(forKey: "location"), location.isEmpty == false {
            let path = (location as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// The folder you chose in Settings, if any — and if it's still there.
    static var chosenFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: folderKey), path.isEmpty == false else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Where NotchHover's own screenshots go: your choice, else wherever macOS puts them.
    static var folder: URL { chosenFolder ?? systemFolder }

    /// Every folder new screenshots can land in: yours, and macOS's for the keyboard
    /// shortcuts, if they're different.
    static var watchedFolders: [URL] {
        var folders = [folder]
        if systemFolder.standardizedFileURL != folder.standardizedFileURL { folders.append(systemFolder) }
        return folders
    }

    /// Sends ⇧⌘3, ⇧⌘4 and ⇧⌘5 to a folder too — the setting the Screenshot app's
    /// Options → Save to writes. Nil puts them back on the Desktop.
    static func setSystemFolder(_ url: URL?) {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let url {
            defaults?.set(url.path, forKey: "location")
        } else {
            defaults?.removeObject(forKey: "location")
        }
        defaults?.synchronize()
    }

    @discardableResult
    func addObserver(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func start() {
        let folders = Self.watchedFolders
        queue.async { [weak self] in
            guard let self else { return }
            let found = Self.scan(folders)
            DispatchQueue.main.async {
                self.known = Set(found)
                self.items = found
                self.notify()
            }
        }
        folders.forEach(watch)
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    /// The folder changed in Settings: look in the new places.
    func restart() {
        stop()
        start()
    }

    /// A folder changed: anything new that is a screenshot is announced.
    private func watch(_ folder: URL) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.system.error("Screenshots: can't watch \(folder.path, privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setEventHandler { [weak self] in self?.foldersChanged() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }

    private func foldersChanged() {
        let folders = Self.watchedFolders
        // macOS writes the file, then marks it; give it a moment to finish.
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let found = Self.scan(folders)
            DispatchQueue.main.async {
                let fresh = found.filter { self.known.contains($0) == false }
                self.known.formUnion(found)
                self.items = found
                self.notify()
                if let newest = fresh.first, Self.isRecent(newest) { self.onNew?(newest) }
            }
        }
    }

    /// Preview hook.
    func loadForPreview(_ urls: [URL]) {
        items = urls
        notify()
    }

    /// Added from a capture NotchHover took itself, without waiting for the folder.
    func add(_ url: URL) {
        guard known.contains(url) == false else { return }
        known.insert(url)
        items.insert(url, at: 0)
        notify()
        onNew?(url)
    }

    func delete(_ url: URL) {
        NSWorkspace.shared.recycle([url]) { [weak self] _, _ in
            self?.items.removeAll { $0 == url }
            self?.notify()
        }
    }

    private func notify() {
        observers.values.forEach { $0() }
    }

    // MARK: - Finding them

    /// Newest first, the last few dozen, across every folder.
    static func scan(_ folders: [URL]) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let files = folders.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        }
        return files
            .filter(isScreenshot)
            .map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(recentLimit)
            .map(\.0)
    }

    /// macOS tags every screenshot with `kMDItemIsScreenCapture`, whatever language
    /// its name is in.
    static func isScreenshot(_ url: URL) -> Bool {
        guard ["png", "jpg", "jpeg", "heic", "tiff", "pdf"].contains(url.pathExtension.lowercased()) else { return false }
        return getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    private static func isRecent(_ url: URL) -> Bool {
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        return Date().timeIntervalSince(created) < 30
    }

    // MARK: - Taking one

    enum Capture: CaseIterable {
        case area, window, screen, timed

        var title: String {
            switch self {
            case .area: return "Area"
            case .window: return "Window"
            case .screen: return "Screen"
            case .timed: return "In 5 s"
            }
        }

        var symbol: String {
            switch self {
            case .area: return "crop"
            case .window: return "macwindow"
            case .screen: return "display"
            case .timed: return "timer"
            }
        }

        fileprivate var arguments: [String] {
            switch self {
            case .area: return ["-i", "-s"]
            case .window: return ["-i", "-w"]
            case .screen: return []
            case .timed: return ["-T", "5"]
            }
        }
    }

    /// Runs macOS's own screenshot tool into the screenshots folder. The first time,
    /// macOS asks for Screen Recording on NotchHover's behalf.
    func capture(_ kind: Capture) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = Self.folder.appendingPathComponent("Screenshot \(formatter.string(from: Date())).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = kind.arguments + ["-x", url.path]
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                // Esc during an area or window pick leaves no file.
                guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else { return }
                self?.add(url)
            }
        }
        Log.system.notice("Screenshot: \(kind.title, privacy: .public)")
        try? process.run()
    }

    // MARK: - Doing things with one

    static func copy(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    /// Preview has Markup; that is where macOS's own thumbnail sends you too.
    static func markup(_ url: URL) {
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }
}
