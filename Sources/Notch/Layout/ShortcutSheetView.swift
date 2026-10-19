import AppKit

/// Every keyboard shortcut, in one place: the sheet ⌘/ shows inside the panel reads it,
/// and so should anything that documents them. NotchHover is meant to be usable without
/// touching the pointer, which only works if the keys can be found.
enum KeyboardShortcutList {
    struct Group {
        let title: String
        let entries: [(keys: String, action: String)]
    }

    static let groups: [Group] = [
        Group(title: "Anywhere — again to close", entries: [
            ("⌃⌥H  ⌃⌥S", "Home, Shelf"),
            ("⌃⌥N  ⌃⌥V", "Notes, Clipboard"),
            ("⌃⌥M", "Mute the call, or the mic")
        ]),
        Group(title: "In the panel", entries: [
            ("⌘1 – ⌘5", "Switch views"),
            ("⌃⇥", "Next tab"),
            ("⎋  ⌘W", "Close"),
            ("⌘,  ⌘/", "Settings, these keys"),
            ("⌘J", "Join the next call")
        ]),
        Group(title: "Playing", entries: [
            ("Space", "Play or pause"),
            ("⌘←  ⌘→", "Previous, next"),
            ("⌘↑  ⌘↓", "Volume"),
            ("⌘⇧M", "Mute the mic")
        ]),
        Group(title: "Claude Code", entries: [
            ("⌘↩  ⌘⌫", "Allow, deny")
        ]),
        Group(title: "Clipboard", entries: [
            ("↑ ↓  ↩", "Choose, copy"),
            ("⌘↩", "Paste in front app"),
            ("⌘P  ⌘⌫", "Pin, delete")
        ]),
        Group(title: "Notes and Shelf", entries: [
            ("⌘↩  ⌘N", "Save, new"),
            ("⌘[  ⌘]", "Other notes"),
            ("⌘S  ⌘R", "Send, show file")
        ])
    ]
}

/// The shortcut sheet: the whole list, laid out in columns over the panel's content.
final class ShortcutSheetView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        // Opaque enough that the pane underneath doesn't read through the text.
        layer?.backgroundColor = Style.theme.windowBackground.withAlphaComponent(0.97).cgColor
        layer?.cornerRadius = 14

        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 18
        columns.translatesAutoresizingMaskIntoConstraints = false
        addSubview(columns)

        // Three columns of two groups each, in reading order.
        let groups = KeyboardShortcutList.groups
        for start in stride(from: 0, to: groups.count, by: 2) {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 7
            groups[start..<min(start + 2, groups.count)].forEach { column.addArrangedSubview(Self.groupView($0)) }
            columns.addArrangedSubview(column)
        }

        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            columns.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            columns.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Purely to read: clicks fall through to whatever closes it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// One block of text per group, keys and descriptions lined up by a tab stop.
    /// Rows built from nested stack views laid out correctly and still drew clipped,
    /// so there is nothing left here to negotiate a width.
    private static func groupView(_ group: KeyboardShortcutList.Group) -> NSView {
        let size = Style.scaled(10)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 66)]
        paragraph.lineSpacing = 1

        let text = NSMutableAttributedString(string: group.title + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: Style.tertiaryText,
            .paragraphStyle: paragraph
        ])
        for (index, entry) in group.entries.enumerated() {
            text.append(NSAttributedString(string: entry.keys, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .medium),
                .foregroundColor: Style.primaryText,
                .paragraphStyle: paragraph
            ]))
            let ending = index == group.entries.count - 1 ? "" : "\n"
            text.append(NSAttributedString(string: "\t" + entry.action + ending, attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: Style.secondaryText,
                .paragraphStyle: paragraph
            ]))
        }

        let label = NSTextField(labelWithAttributedString: text)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }
}
