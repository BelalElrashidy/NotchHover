import AppKit

/// Downloads and caches Spotify album art. Callbacks are delivered on the main queue.
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSURL, NSImage>()
    private let session = URLSession(configuration: .ephemeral)

    func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }

        session.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            if let image {
                self?.cache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
        .resume()
    }
}
