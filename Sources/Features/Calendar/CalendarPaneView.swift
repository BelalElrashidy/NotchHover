import AppKit
import EventKit

/// The schedule: a week strip over a timeline of the chosen day — Boring Notch's day
/// strip on top of Crest's hour blocks, with Atoll's all-day capsules and Join buttons in
/// each service's colour. Today's timeline has a red line at now and opens scrolled to it.
/// Read-only, and silent when access is not granted.
final class CalendarPaneView: NSView {
    private let calendar = CalendarService.shared
    private let strip = DayStripView()
    private let allDayRow = NSStackView()
    private let scrollView = NSScrollView()
    private let timeline = TimelineView()
    private let statusLabel = Style.label("", size: 11, color: Style.secondaryText)
    private lazy var allowButton = Style.pushButton("Allow calendar access", prominent: true, target: self, action: #selector(handleAllow))

    private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// Preview hook: made-up events, so the card renders without calendar access.
    static var previewEvents: [EKEvent]?
    private var minuteTimer: Timer?
    /// Scrolling needs a size; a render before the first layout scrolls once it has one.
    private var pendingFocus: [EKEvent]?
    private var storeObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)

        strip.onSelect = { [weak self] day in
            self?.selectedDay = day
            self?.render(scrollToFocus: true)
        }

        allDayRow.orientation = .horizontal
        allDayRow.spacing = 5

        scrollView.documentView = timeline
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.contentView.postsBoundsChangedNotifications = false

        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        [strip, allDayRow, scrollView, statusLabel, allowButton].forEach(addSubview)
        allowButton.isHidden = true

        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: calendar.store, queue: .main) { [weak self] _ in
            self?.render(scrollToFocus: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        storeObserver.map(NotificationCenter.default.removeObserver)
        minuteTimer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        minuteTimer?.invalidate()
        minuteTimer = nil
        guard window != nil else { return }
        reload()
        // The now line, and the day itself at midnight.
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.render(scrollToFocus: false)
        }
    }

    func reload() {
        if calendar.isAuthorized || Self.previewEvents != nil {
            statusLabel.isHidden = true
            allowButton.isHidden = true
            render(scrollToFocus: true)
        } else if calendar.isDenied {
            showStatus("Calendar access is off — turn it on in System Settings → Privacy & Security → Calendars", allow: false)
        } else {
            showStatus("See your day, with a Join button on every call", allow: true)
        }
    }

    private func showStatus(_ text: String, allow: Bool) {
        statusLabel.stringValue = text
        statusLabel.isHidden = false
        allowButton.isHidden = allow == false
        [strip, allDayRow, scrollView].forEach { $0.isHidden = true }
        needsLayout = true
    }

    private func render(scrollToFocus: Bool) {
        guard calendar.isAuthorized || Self.previewEvents != nil else { return }
        [strip, scrollView].forEach { $0.isHidden = false }

        let today = Calendar.current.startOfDay(for: Date())
        let days = (-2...4).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
        if days.contains(selectedDay) == false { selectedDay = today }
        let weekEvents = Self.previewEvents
            ?? calendar.events(from: days.first!, to: Calendar.current.date(byAdding: .day, value: 1, to: days.last!)!)
        strip.show(days: days, selected: selectedDay, busy: Set(weekEvents.map { Calendar.current.startOfDay(for: $0.startDate) }))

        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay)!
        let events = weekEvents.filter { $0.startDate < dayEnd && $0.endDate > selectedDay }

        allDayRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for event in events where event.isAllDay {
            allDayRow.addArrangedSubview(AllDayCapsule(title: event.title ?? "Untitled", color: event.color))
        }
        allDayRow.isHidden = allDayRow.arrangedSubviews.isEmpty
        // A spacer takes the slack, so capsules stay as wide as their titles.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        allDayRow.addArrangedSubview(spacer)

        timeline.show(day: selectedDay, events: events.filter { $0.isAllDay == false })
        if scrollToFocus { pendingFocus = events }
        needsLayout = true
    }

    /// Today opens just before now; another day at its first event, or at nine.
    private func scrollToFocusPoint(events: [EKEvent]) {
        let focus: Date
        if Calendar.current.isDateInToday(selectedDay) {
            focus = Date().addingTimeInterval(-30 * 60)
        } else {
            focus = events.filter { $0.isAllDay == false }.map(\.startDate).min()?.addingTimeInterval(-30 * 60)
                ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay)!
        }
        let y = max(0, min(timeline.y(for: focus), timeline.frame.height - scrollView.contentView.bounds.height))
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let width = bounds.width - inset * 2
        var top = bounds.height - 6

        if statusLabel.isHidden == false {
            let buttonHeight: CGFloat = allowButton.isHidden ? 0 : 30
            let textHeight = statusLabel.sizeThatFits(CGSize(width: width, height: 100)).height
            let blockTop = bounds.midY + (textHeight + buttonHeight) / 2
            statusLabel.frame = CGRect(x: inset, y: blockTop - textHeight, width: width, height: textHeight)
            let buttonWidth = allowButton.fittingSize.width + 20
            allowButton.frame = CGRect(x: bounds.midX - buttonWidth / 2, y: statusLabel.frame.minY - 28, width: buttonWidth, height: 22)
            return
        }

        strip.frame = CGRect(x: inset, y: top - DayStripView.height, width: width, height: DayStripView.height)
        top = strip.frame.minY - 4
        if allDayRow.isHidden == false {
            allDayRow.frame = CGRect(x: inset, y: top - 16, width: width, height: 16)
            top = allDayRow.frame.minY - 4
        }
        scrollView.frame = CGRect(x: inset, y: 4, width: width, height: max(0, top - 4))
        timeline.frame = CGRect(x: 0, y: 0, width: width, height: TimelineView.hourHeight * 24)
        if let events = pendingFocus, scrollView.frame.height > 0 {
            pendingFocus = nil
            scrollToFocusPoint(events: events)
        }
    }

    @objc private func handleAllow() {
        calendar.requestAccessIfNeeded { [weak self] _ in self?.reload() }
    }
}

extension CalendarService {
    /// Every event overlapping the range, all-day ones included.
    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
    }
}

private extension EKEvent {
    var color: NSColor {
        calendar.flatMap { NSColor(cgColor: $0.cgColor) } ?? Style.accent
    }
}

// MARK: - Week strip

/// Seven days, today in red; a dot under any day with something on. Click to pick one.
private final class DayStripView: NSView {
    static let height: CGFloat = 40
    var onSelect: ((Date) -> Void)?

    private var days: [Date] = []
    private var selected = Date()
    private var busy = Set<Date>()

    func show(days: [Date], selected: Date, busy: Set<Date>) {
        self.days = days
        self.selected = selected
        self.busy = busy
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard days.isEmpty == false else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(point.x / (bounds.width / CGFloat(days.count)))
        guard days.indices.contains(index) else { return }
        Haptics.tick()
        onSelect?(days[index])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard days.isEmpty == false else { return }
        let cell = bounds.width / CGFloat(days.count)
        let weekday = DateFormatter()
        weekday.setLocalizedDateFormatFromTemplate("EEEEE")
        let red = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)

        for (index, day) in days.enumerated() {
            let midX = cell * (CGFloat(index) + 0.5)
            let isToday = Calendar.current.isDateInToday(day)
            let isSelected = day == selected

            let letter = NSAttributedString(string: weekday.string(from: day), attributes: [
                .font: NSFont.systemFont(ofSize: Style.scaled(9), weight: .medium), .foregroundColor: Style.secondaryText
            ])
            letter.draw(at: CGPoint(x: midX - letter.size().width / 2, y: bounds.height - letter.size().height))

            let circle = CGRect(x: midX - 10, y: 5, width: 20, height: 20)
            if isToday {
                red.setFill()
                NSBezierPath(ovalIn: circle).fill()
            } else if isSelected {
                Style.primaryText.withAlphaComponent(0.16).setFill()
                NSBezierPath(ovalIn: circle).fill()
            }
            let number = NSAttributedString(string: "\(Calendar.current.component(.day, from: day))", attributes: [
                .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: isToday || isSelected ? .semibold : .regular),
                .foregroundColor: isToday ? NSColor.white : Style.primaryText
            ])
            number.draw(at: CGPoint(x: midX - number.size().width / 2, y: circle.midY - number.size().height / 2))

            if busy.contains(day) {
                Style.secondaryText.setFill()
                NSBezierPath(ovalIn: CGRect(x: midX - 1.5, y: 0, width: 3, height: 3)).fill()
            }
        }
    }
}

// MARK: - All-day capsule

private final class AllDayCapsule: NSView {
    init(title: String, color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = Style.primaryText.withAlphaComponent(0.1).cgColor

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = color.cgColor
        let label = Style.label(title, size: 10)
        let stack = NSStackView(views: [dot, label])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 7, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        setContentHuggingPriority(.required, for: .horizontal)
        stack.setHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Timeline

/// A whole day of hours, scrolled to the part that matters. Events are blocks in their
/// calendar's colour; side by side when they overlap. Calls get a Join chip.
final class TimelineView: NSView {
    static let hourHeight: CGFloat = 36
    private static let labelWidth: CGFloat = 24

    private var day = Date()
    private var events: [EKEvent] = []
    private var placed: [(event: EKEvent, rect: CGRect)] = []
    private var joinLinks: [MeetingLink] = []

    override var isFlipped: Bool { true }

    func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(day) / 3600) * Self.hourHeight
    }

    func show(day: Date, events: [EKEvent]) {
        self.day = day
        self.events = events
        place()
    }

    /// Columns depend on the width, so placing waits for a frame and redoes on resize.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { place() }
    }

    private func place() {
        subviews.forEach { $0.removeFromSuperview() }
        joinLinks = []
        placed = []

        // Greedy columns: an event goes in the first column whose last event has ended.
        var columns: [[EKEvent]] = []
        var columnOf: [ObjectIdentifier: Int] = [:]
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            let column = columns.firstIndex { ($0.last?.endDate ?? .distantPast) <= event.startDate } ?? columns.count
            if column == columns.count { columns.append([]) }
            columns[column].append(event)
            columnOf[ObjectIdentifier(event)] = column
        }
        let left = Self.labelWidth + 4
        let usable = max(0, bounds.width - left)
        let columnWidth = usable / CGFloat(max(1, columns.count))

        for event in events {
            let column = CGFloat(columnOf[ObjectIdentifier(event)] ?? 0)
            let top = max(0, y(for: event.startDate))
            let bottom = min(bounds.height, y(for: event.endDate))
            let rect = CGRect(x: left + column * columnWidth, y: top + 1, width: columnWidth - 2, height: max(16, bottom - top - 2))
            placed.append((event, rect))

            if event.endDate > Date(), let link = MeetingLink.find(in: event) {
                let chip = Self.joinChip(service: link.service, tag: joinLinks.count, target: self, action: #selector(handleJoin(_:)))
                joinLinks.append(link)
                let width = chip.intrinsicContentSize.width + 14
                chip.frame = CGRect(x: rect.maxX - width - 4, y: rect.minY + 2, width: width, height: min(16, rect.height - 4))
                addSubview(chip)
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: Style.scaled(9), weight: .regular)
        let left = Self.labelWidth + 4

        for hour in 0..<24 {
            let y = CGFloat(hour) * Self.hourHeight
            Style.primaryText.withAlphaComponent(0.08).setFill()
            NSRect(x: left, y: y, width: bounds.width - left, height: 1).fill()
            let label = NSAttributedString(string: String(format: "%02d", hour), attributes: [
                .font: labelFont, .foregroundColor: Style.secondaryText
            ])
            label.draw(at: CGPoint(x: 0, y: y - label.size().height / 2 + 1))
        }

        for (event, rect) in placed {
            let color = event.color
            let isPast = event.endDate < Date()
            color.withAlphaComponent(isPast ? 0.14 : 0.3).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            color.withAlphaComponent(isPast ? 0.5 : 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height), xRadius: 1.5, yRadius: 1.5).fill()

            let title = NSAttributedString(string: event.title ?? "Untitled", attributes: [
                .font: NSFont.systemFont(ofSize: Style.scaled(11), weight: .semibold),
                .foregroundColor: Style.primaryText.withAlphaComponent(isPast ? 0.55 : 1)
            ])
            let titleRect = CGRect(x: rect.minX + 8, y: rect.minY + 2, width: rect.width - 12 - 50, height: min(rect.height - 2, 15))
            title.draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            if rect.height >= 30 {
                let time = NSAttributedString(string: event.startDate.formatted(date: .omitted, time: .shortened), attributes: [
                    .font: NSFont.systemFont(ofSize: Style.scaled(10)), .foregroundColor: Style.secondaryText
                ])
                time.draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 16))
            }
        }

        // Now, on today's timeline.
        if Calendar.current.isDate(day, inSameDayAs: Date()) {
            let red = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)
            let y = self.y(for: Date())
            red.setFill()
            NSRect(x: left - 2, y: y - 0.75, width: bounds.width - left + 2, height: 1.5).fill()
            NSBezierPath(ovalIn: CGRect(x: left - 6, y: y - 3.5, width: 7, height: 7)).fill()
        }
    }

    /// A small Join button in the meeting service's own colour.
    private static func joinChip(service: String, tag: Int, target: AnyObject, action: Selector) -> NSButton {
        let chip = ClickThroughButton(title: "Join", target: target, action: action)
        chip.tag = tag
        chip.isBordered = false
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 5
        chip.layer?.backgroundColor = PeekView.serviceColor(service).cgColor
        chip.attributedTitle = NSAttributedString(string: "Join", attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: Style.scaled(10), weight: .semibold)
        ])
        chip.toolTip = "Join on \(service) — ⌘J"
        return chip
    }

    @objc private func handleJoin(_ sender: NSButton) {
        guard joinLinks.indices.contains(sender.tag) else { return }
        Log.ui.notice("Joining a \(self.joinLinks[sender.tag].service, privacy: .public) call from the calendar")
        joinLinks[sender.tag].open()
    }
}
