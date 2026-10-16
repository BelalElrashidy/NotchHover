import AppKit
import EventKit

/// One calendar store for everything that reads events — the Home card, the peek, the
/// meeting join. Read-only, asks for access once, and says nothing without it.
final class CalendarService {
    static let shared = CalendarService()

    let store = EKEventStore()
    private var hasRequestedAccess = false

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Asks the first time anything wants the calendar; afterwards just reports.
    func requestAccessIfNeeded(_ completion: @escaping (Bool) -> Void) {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            completion(isAuthorized)
            return
        }
        guard hasRequestedAccess == false else { return }
        hasRequestedAccess = true
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Events that haven't ended yet, starting within the next `interval`.
    func upcomingEvents(within interval: TimeInterval = 24 * 60 * 60) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 60 * 60), end: now.addingTimeInterval(interval), calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.endDate > now && $0.startDate < now.addingTimeInterval(interval) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// The next thing on today's calendar that hasn't finished, ignoring all-day events
    /// — a holiday is not what you want to see when you glance at the notch.
    func nextEvent() -> EKEvent? {
        let endOfDay = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
        return upcomingEvents(within: endOfDay.timeIntervalSinceNow).first { $0.isAllDay == false }
    }

    /// A call that is on now, or starts within the next ten minutes, with a link to
    /// join it. That window is when a Join button is worth the space.
    func joinableMeeting(lead: TimeInterval = 10 * 60) -> (event: EKEvent, link: MeetingLink)? {
        let now = Date()
        for event in upcomingEvents(within: lead) where event.isAllDay == false {
            guard event.startDate <= now.addingTimeInterval(lead), event.endDate > now,
                  let link = MeetingLink.find(in: event) else { continue }
            return (event, link)
        }
        return nil
    }
}

/// A video-call link found in an event. NotchHover only hands it to the app that owns it
/// — it never connects to anything itself — so this works offline and shares nothing.
struct MeetingLink: Equatable {
    let service: String
    let url: URL

    /// Where calendars put the link: the event's URL field, its location, or its notes,
    /// usually inside a block of invitation text.
    static func find(in event: EKEvent) -> MeetingLink? {
        let haystack = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: "\n")
        return find(in: haystack)
    }

    static func find(in text: String) -> MeetingLink? {
        for (service, pattern) in patterns {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            // Invitations wrap links in <…> or end sentences with them; neither belongs.
            let raw = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ">).,;\"'"))
            guard let url = URL(string: raw) else { continue }
            return MeetingLink(service: service, url: url)
        }
        return nil
    }

    private static let patterns: [(String, String)] = [
        ("Zoom", #"https?://[\w.-]*zoom\.us/(j|w|my|s)/[^\s<>"]+"#),
        ("Google Meet", #"https?://meet\.google\.com/[a-z]{3,4}-[a-z]{4}-[a-z]{3,4}[^\s<>"]*"#),
        ("Teams", #"https?://teams\.(microsoft|live)\.com/(l/meetup-join|meet)/[^\s<>"]+"#),
        ("FaceTime", #"https?://facetime\.apple\.com/join[^\s<>"]+"#),
        ("Webex", #"https?://[\w.-]*webex\.com/[^\s<>"]+"#)
    ]

    /// Straight into the meeting app when it is installed, rather than via a browser tab
    /// that then asks to open it.
    func open() {
        NSWorkspace.shared.open(appURL ?? url)
    }

    private var appURL: URL? {
        switch service {
        case "Zoom" where isInstalled("us.zoom.xos"):
            // https://zoom.us/j/123?pwd=abc → zoommtg://zoom.us/join?confno=123&pwd=abc
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let number = components.path.split(separator: "/").last,
                  number.allSatisfy(\.isNumber) else { return nil }
            var app = URLComponents()
            app.scheme = "zoommtg"
            app.host = "zoom.us"
            app.path = "/join"
            app.queryItems = [URLQueryItem(name: "confno", value: String(number))]
                + (components.queryItems?.filter { $0.name == "pwd" } ?? [])
            return app.url
        case "Teams" where isInstalled("com.microsoft.teams2") || isInstalled("com.microsoft.teams"):
            return URL(string: "msteams:" + url.path + (url.query.map { "?" + $0 } ?? ""))
        default:
            return nil
        }
    }

    private func isInstalled(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}
