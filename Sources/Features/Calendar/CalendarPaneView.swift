import AppKit
import EventKit

/// Next few calendar events, with a Join button on any that has a call link. Read-only,
/// and silent when access is not granted.
final class CalendarPaneView: NSView {
    private let calendar = CalendarService.shared
    private let titleLabel = Style.label("Up next", size: 12, weight: .semibold)
    private let eventsStack = NSStackView()
    private let statusLabel = Style.label("", size: 11, color: Style.secondaryText)
    private var links: [MeetingLink] = []

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
        if calendar.isAuthorized {
            render(events: calendar.upcomingEvents())
        } else if calendar.isDenied {
            statusLabel.stringValue = "Calendar access denied — enable it in System Settings › Privacy"
            render(events: [])
        } else {
            statusLabel.stringValue = "Requesting calendar access…"
            calendar.requestAccessIfNeeded { [weak self] granted in
                guard let self else { return }
                self.statusLabel.stringValue = granted ? "" : "Calendar access denied"
                if granted { self.render(events: self.calendar.upcomingEvents()) }
            }
        }
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
        links = []

        for event in events.prefix(3) {
            let isOn = event.startDate <= Date() && event.isAllDay == false
            let time = Style.label(
                event.isAllDay ? "all day" : (isOn ? "now" : formatter.string(from: event.startDate)),
                size: 11,
                weight: .semibold,
                color: isOn ? Style.accent : Style.secondaryText
            )
            time.widthAnchor.constraint(equalToConstant: 40).isActive = true

            let name = Style.label(event.title ?? "Untitled", size: 11)
            var views: [NSView] = [time, name]

            // One click from the calendar into the call. The link only goes to the app
            // that owns it; NotchHover itself connects to nothing.
            if let link = MeetingLink.find(in: event) {
                let join = Style.pushButton("Join", prominent: isOn || event.startDate.timeIntervalSinceNow < 10 * 60, target: self, action: #selector(handleJoin(_:)))
                join.tag = links.count
                join.toolTip = "Join on \(link.service)"
                links.append(link)
                views.append(join)
            }

            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            eventsStack.addArrangedSubview(row)
        }
    }

    @objc private func handleJoin(_ sender: NSButton) {
        guard links.indices.contains(sender.tag) else { return }
        Log.ui.notice("Joining a \(self.links[sender.tag].service, privacy: .public) call from the calendar")
        links[sender.tag].open()
    }
}
