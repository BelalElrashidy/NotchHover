import AppKit

/// The parts every settings pane is built from, in the style System Settings uses —
/// grouped cards of rows, each row a title with a line saying what it does, the control
/// on the right — drawn from the active theme rather than stock grey controls.
enum SettingsKit {
    static var theme: Theme { SettingsStyle.theme }

    /// A small coloured note beside a title: what a setting reaches beyond the Mac, or
    /// that it doesn't.
    enum Badge {
        case internet
        case onThisMac
        case asks(String)

        var text: String {
            switch self {
            case .internet: return "uses the internet"
            case .onThisMac: return "on this Mac only"
            case .asks(let permission): return "asks for \(permission)"
            }
        }

        var color: NSColor {
            switch self {
            case .internet: return .systemOrange
            case .onThisMac: return .systemGreen
            case .asks: return .systemBlue
            }
        }
    }

    /// The pane's title and a sentence about it.
    static func header(_ title: String, _ intro: String?) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = theme.primaryText
        var views: [NSView] = [titleLabel]
        if let intro {
            let introLabel = NSTextField(wrappingLabelWithString: intro)
            introLabel.font = .systemFont(ofSize: 12)
            introLabel.textColor = theme.secondaryText
            introLabel.preferredMaxLayoutWidth = 560
            views.append(introLabel)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }

    /// A titled card of rows with hairlines between them, and an optional note under it.
    static func section(_ title: String?, footer: String? = nil, rows: [NSView]) -> NSView {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 0
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.cornerCurve = .continuous
        card.layer?.backgroundColor = theme.elevatedBackground.cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = theme.primaryText.withAlphaComponent(0.08).cgColor

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let rule = NSView()
                rule.wantsLayer = true
                rule.layer?.backgroundColor = theme.primaryText.withAlphaComponent(0.08).cgColor
                rule.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                card.addArrangedSubview(rule)
                rule.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14).isActive = true
                rule.trailingAnchor.constraint(equalTo: card.trailingAnchor).isActive = true
            }
            card.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor).isActive = true
        }

        var views: [NSView] = []
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = theme.secondaryText
            views.append(label)
        }
        views.append(card)
        if let footer {
            let note = NSTextField(wrappingLabelWithString: footer)
            note.font = .systemFont(ofSize: 11)
            note.textColor = theme.tertiaryText
            note.preferredMaxLayoutWidth = 560
            views.append(note)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// Title, what it does, and the control at the right edge.
    static func row(_ title: String, detail: String? = nil, badge: Badge? = nil, control: NSView? = nil) -> NSView {
        SettingsRowView(title: title, detail: detail, badge: badge, control: control)
    }

    static func toggle(_ title: String, detail: String? = nil, badge: Badge? = nil, isOn: Bool, onChange: @escaping (Bool) -> Void) -> NSView {
        let control = SwitchControl()
        control.isOn = isOn
        control.onChange = onChange
        return row(title, detail: detail, badge: badge, control: control)
    }

    static func popup(_ title: String, detail: String? = nil, options: [String], selected: Int, onSelect: @escaping (Int) -> Void) -> NSView {
        let menu = MenuButton(titles: options)
        menu.select(selected, notify: false)
        menu.onSelect = onSelect
        return row(title, detail: detail, control: menu)
    }

    /// A button that runs a closure.
    static func button(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = (prominent ? theme.accent : theme.controlFill).cgColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: prominent ? theme.onAccentText : theme.primaryText,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ])
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.widthAnchor.constraint(equalToConstant: button.intrinsicContentSize.width + 20).isActive = true
        return button
    }

    /// A slider with its value beside it.
    static func slider(value: Double, range: ClosedRange<Double>, format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) -> NSView {
        let readout = NSTextField(labelWithString: format(value))
        readout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        readout.textColor = theme.secondaryText
        readout.alignment = .right
        readout.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let bar = ProgressBarView()
        bar.fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        bar.widthAnchor.constraint(equalToConstant: 180).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        bar.onScrub = { fraction in
            let resolved = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
            readout.stringValue = format(resolved)
            onChange(resolved)
        }
        let stack = NSStackView(views: [bar, readout])
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }

    /// A status dot and a word: granted, off, not asked yet.
    static func status(_ text: String, good: Bool?) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = (good == true ? NSColor.systemGreen : (good == false ? NSColor.systemOrange : theme.tertiaryText)).cgColor
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = theme.secondaryText
        let stack = NSStackView(views: [dot, label])
        stack.spacing = 6
        stack.alignment = .centerY
        return stack
    }

    /// Controls side by side, for a row with more than one.
    static func group(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }
}

/// A button whose action is a closure.
final class ClosureButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(title: String, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        handler = action
        target = self
        self.action = #selector(fire)
    }

    @objc private func fire() { handler?() }
}

/// The theme's own switch: a track and a knob, like System Settings' mini switch.
final class SwitchControl: NSView {
    var onChange: ((Bool) -> Void)?
    var isOn = false { didSet { refresh(animated: oldValue != isOn) } }

    private let knob = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        knob.backgroundColor = NSColor.white.cgColor
        knob.cornerRadius = 7
        knob.shadowOpacity = 0.25
        knob.shadowRadius = 1
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        layer?.addSublayer(knob)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
        refresh(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        refresh(animated: false)
    }

    private func refresh(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(animated == false)
        CATransaction.setAnimationDuration(0.15)
        layer?.backgroundColor = (isOn ? SettingsKit.theme.accent : SettingsKit.theme.controlFill).cgColor
        knob.frame = CGRect(x: isOn ? bounds.width - 16 : 2, y: 2, width: 14, height: 14)
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onChange?(isOn)
    }
}

/// One settings row. Laid out by hand rather than in a stack: a wrapping description has
/// to know how wide it really is, and a stack only finds out after it has measured it —
/// which clipped second lines and squeezed the row's padding away.
final class SettingsRowView: NSView {
    private let textStack: NSStackView
    private let detailLabel: NSTextField?
    private let control: NSView?

    init(title: String, detail: String?, badge: SettingsKit.Badge?, control: NSView?) {
        let theme = SettingsKit.theme
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = theme.primaryText

        var titleLine: [NSView] = [titleLabel]
        if let badge {
            let tag = NSTextField(labelWithString: " \(badge.text) ")
            tag.font = .systemFont(ofSize: 10, weight: .medium)
            tag.textColor = badge.color
            tag.wantsLayer = true
            tag.drawsBackground = true
            tag.backgroundColor = badge.color.withAlphaComponent(0.15)
            tag.layer?.cornerRadius = 4
            titleLine.append(tag)
        }
        let top = NSStackView(views: titleLine)
        top.spacing = 6
        top.alignment = .centerY

        var lines: [NSView] = [top]
        if let detail {
            let label = NSTextField(wrappingLabelWithString: detail)
            label.font = .systemFont(ofSize: 11)
            label.textColor = theme.secondaryText
            label.preferredMaxLayoutWidth = 300
            detailLabel = label
            lines.append(label)
        } else {
            detailLabel = nil
        }
        textStack = NSStackView(views: lines)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        self.control = control
        super.init(frame: .zero)

        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)
        var constraints = [
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ]
        if let control {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            control.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(control)
            constraints += [
                control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                control.centerYAnchor.constraint(equalTo: centerYAnchor),
                control.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 18),
                heightAnchor.constraint(greaterThanOrEqualTo: control.heightAnchor, constant: 16)
            ]
        } else {
            constraints.append(textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The description wraps to the room between the left edge and the control.
    override func layout() {
        let available = bounds.width - 14 - 14 - (control.map { $0.fittingSize.width + 18 } ?? 0)
        if let detailLabel, available > 50, abs(detailLabel.preferredMaxLayoutWidth - available) > 1 {
            detailLabel.preferredMaxLayoutWidth = available
            invalidateIntrinsicContentSize()
            needsUpdateConstraints = true
        }
        super.layout()
    }
}
