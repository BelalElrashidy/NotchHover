import AppKit

/// Claude Code at a glance: each session that is active, what it is doing, and how many
/// tokens today has used. All of it from the transcripts on this Mac.
final class ClaudePaneView: NSView {
    private let stack = NSStackView()
    private var observer: UUID?

    init() {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        observer = ClaudeSessionMonitor.shared.addObserver { [weak self] in self?.reload() }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let monitor = ClaudeSessionMonitor.shared
        stack.addArrangedSubview(Style.label("Claude Code", size: 12, weight: .semibold))

        if monitor.sessions.isEmpty {
            stack.addArrangedSubview(Style.label("No active sessions", size: 11, color: Style.tertiaryText))
        }
        for session in monitor.sessions.prefix(3) {
            stack.addArrangedSubview(row(for: session))
        }

        let usage = monitor.usage
        if usage.today > 0 {
            // Cache reads dwarf everything else, so what was written is shown beside the total.
            let line = "Today \(Self.tokens(usage.today)), \(Self.tokens(usage.todayOutput)) written · 5h \(Self.tokens(usage.lastFiveHours))"
            stack.addArrangedSubview(Style.label(line, size: 10, color: Style.tertiaryText))
        }
    }

    private func row(for session: ClaudeSession) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = Self.color(for: session.state).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 6), dot.heightAnchor.constraint(equalToConstant: 6)])

        let where_ = [session.project, session.branch].compactMap { $0 }.joined(separator: " · ")
        let name = Style.label(where_, size: 11, weight: .medium)
        let state = Style.label(session.state.label, size: 11, color: Style.secondaryText)
        state.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [dot, name, state])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    /// Waiting on you is the one worth seeing from across the room.
    private static func color(for state: ClaudeSessionState) -> NSColor {
        switch state {
        case .waiting: return Style.accent
        case .working: return .systemGreen
        case .thinking: return Style.secondaryText
        }
    }

    /// 1,234,567 → "1.2M", 45,600 → "46K".
    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: return "\(Int((Double(count) / 1_000).rounded()))K"
        default: return "\(count)"
        }
    }
}
