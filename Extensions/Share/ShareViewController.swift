import AppKit

/// "NotchHover" in the Share menu. It takes the shared link — a Spotify or Apple Music
/// playlist, album or song — and hands it to NotchHover over its own `notchhover://`
/// link, then gets out of the way: NotchHover pins it and says so in the notch.
///
/// Built outside SwiftPM by Scripts/build-app.sh and embedded in the app's PlugIns.
/// Like every share extension it runs sandboxed; it reads only what was shared with it.
final class ShareViewController: NSViewController {
    override func loadView() {
        // Nothing to show: the notch is the answer.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let title = items.lazy.compactMap { $0.attributedTitle?.string ?? $0.attributedContentText?.string }.first
        let providers = items.flatMap { $0.attachments ?? [] }

        Self.firstLink(in: providers) { [weak self] link in
            DispatchQueue.main.async {
                if let link { Self.handOver(link, title: title) }
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    /// A URL if one was shared; failing that, the first link inside shared text.
    private static func firstLink(in providers: [NSItemProvider], completion: @escaping (URL?) -> Void) {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.url") }) {
            provider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
                if let url = item as? URL { return completion(url) }
                if let data = item as? Data { return completion(URL(dataRepresentation: data, relativeTo: nil)) }
                completion((item as? String).flatMap(URL.init(string:)))
            }
            return
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.plain-text") }) {
            provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
                let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
                completion(match?.url ?? (text.hasPrefix("spotify:") ? URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) : nil))
            }
            return
        }
        completion(nil)
    }

    private static func handOver(_ link: URL, title: String?) {
        var components = URLComponents()
        components.scheme = "notchhover"
        components.host = "add-playlist"
        components.queryItems = [URLQueryItem(name: "url", value: link.absoluteString)]
            + (title.map { [URLQueryItem(name: "title", value: $0)] } ?? [])
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
