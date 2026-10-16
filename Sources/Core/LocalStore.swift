import Foundation

/// Reads and writes the app's own files under
/// `~/Library/Application Support/NotchHover`. Nothing here touches the network:
/// notes and clipboard history live on this Mac, readable only by this user.
enum LocalStore {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchHover", isDirectory: true)
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func ensureDirectory(_ url: URL = directory) {
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    /// Atomic write with owner-only permissions.
    static func save<T: Encodable>(_ value: T, to name: String) {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        let target = url(name)
        do {
            try data.write(to: target, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            Log.system.error("Could not save \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
