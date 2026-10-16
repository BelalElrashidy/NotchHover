import AppKit
import EventKit

/// Next few calendar events. Read-only, and silent when access is not granted.
final class CalendarPaneView: NSView {
    private let store = EKEventStore()
    private let titleLabel = Style.label("Up next", size: 12, weight: .semibold)
    private let eventsStack = NSStackView()
    private let statusLabel = Style.label("", size: 11, color: Style.secondaryText)
    private var hasRequestedAccess = false

    init() {
        super.init(frame: .zero)

        eventsStack.orientation = .vertical
        eventsStack.alignment = .leading
        eventsStack.spacing = 4

        let root = NSStackView(views: [titleLabel, eventsStack, statusLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 6
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            root.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess:
            render(events: upcomingEvents())
        case .notDetermined:
            requestAccess()
        default:
            statusLabel.stringValue = "Calendar access denied — enable it in System Settings › Privacy"
            render(events: [])
        }
    }

    private func requestAccess() {
        guard hasRequestedAccess == false else { return }
        hasRequestedAccess = true
        statusLabel.stringValue = "Requesting calendar access…"

        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusLabel.stringValue = granted ? "" : "Calendar access denied"
                if granted { self.render(events: self.upcomingEvents()) }
            }
        }
    }

    private func upcomingEvents() -> [EKEvent] {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(60 * 60 * 24),
            calendars: nil
        )
        return store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
    }

    private func render(events: [EKEvent]) {
        eventsStack.arrangedSubviews.forEach {
            eventsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard events.isEmpty == false else {
            if statusLabel.stringValue.isEmpty {
                statusLabel.stringValue = "Nothing scheduled in the next 24 hours"
            }
            return
        }

        statusLabel.stringValue = ""
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        for event in events.prefix(3) {
            let time = Style.label(
                event.isAllDay ? "all day" : formatter.string(from: event.startDate),
                size: 11,
                weight: .semibold,
                color: Style.secondaryText
            )
            time.widthAnchor.constraint(equalToConstant: 52).isActive = true

            let name = Style.label(event.title ?? "Untitled", size: 11)
            let row = NSStackView(views: [time, name])
            row.orientation = .horizontal
            row.spacing = 8
            eventsStack.addArrangedSubview(row)
        }
    }
}
