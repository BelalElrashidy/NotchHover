import AppKit

/// The tabs left of the notch: Home, Shelf, Notes, in a capsule.
///
/// Only the selected tab is named; the others are icons. Three named tabs need about
/// 180pt and the wing beside the notch has around 140 at the default width — and a
/// single name is enough to say where you are. A highlight slides to whichever is
/// chosen. When the panel shows something that isn't a tab — the clipboard, the mirror,
/// an approval — nothing is highlighted, and choosing a tab goes back.
final class HeaderTabsView: NSView {
    var onSelect: ((PanelTab) -> Void)?
    private(set) var selected: PanelTab?

    private let highlight = NSView()
    private var buttons: [(tab: PanelTab, button: NSButton)] = []

    private enum Metrics {
        static let height: CGFloat = 24
        static let inset: CGFloat = 2
        static let iconWidth: CGFloat = 28
        static let labelPadding: CGFloat = 10
    }

    init(tabs: [PanelTab] = PanelTab.headerTabs) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.height / 2
        layer?.backgroundColor = Style.primaryText.withAlphaComponent(0.07).cgColor

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = (Metrics.height - Metrics.inset * 2) / 2
        highlight.layer?.backgroundColor = Style.primaryText.withAlphaComponent(0.15).cgColor
        addSubview(highlight)
        setTabs(tabs)
    }

    /// Puts these tabs in the capsule, in order — on launch, and when they're
    /// rearranged in Settings.
    func setTabs(_ tabs: [PanelTab]) {
        guard tabs != buttons.map(\.tab) else { return }
        let isFirst = buttons.isEmpty
        let current = selected
        buttons.forEach { $0.button.removeFromSuperview() }
        buttons.removeAll()
        for tab in tabs {
            let button = ClickThroughButton(title: "", target: self, action: #selector(handleTab(_:)))
            button.isBordered = false
            button.tag = tab.rawValue
            button.toolTip = [tab.title, tab.shortcut].compactMap { $0 }.joined(separator: " — ")
            button.image = Style.symbolImage(tab.symbol, pointSize: 11, description: tab.title)
            button.imageHugsTitle = true
            button.font = .systemFont(ofSize: Style.scaled(11), weight: .medium)
            addSubview(button)
            buttons.append((tab, button))
        }
        invalidateIntrinsicContentSize()
        // The first time, Home; after a rearrangement, whatever was highlighted, if it's
        // still a tab here.
        select(isFirst ? .home : current, notify: false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: buttons.reduce(Metrics.inset * 2) { $0 + width(of: $1.tab) }, height: Metrics.height)
    }

    /// Highlights a tab; nil clears the highlight, for views that aren't tabs.
    func select(_ tab: PanelTab?, notify: Bool = true, animated: Bool = true) {
        let tab = tab.flatMap { candidate in buttons.contains { $0.tab == candidate } ? candidate : nil }
        selected = tab

        for (candidate, button) in buttons {
            let isSelected = candidate == tab
            button.title = isSelected ? candidate.title : ""
            button.imagePosition = isSelected ? .imageLeading : .imageOnly
            let color = isSelected ? Style.primaryText : Style.tertiaryText
            button.contentTintColor = color
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .foregroundColor: color,
                .font: button.font ?? .systemFont(ofSize: 11)
            ])
        }

        invalidateIntrinsicContentSize()
        layoutButtons(animated: animated)

        if notify, let tab { onSelect?(tab) }
    }

    override func layout() {
        super.layout()
        layoutButtons(animated: false)
    }

    private func width(of tab: PanelTab) -> CGFloat {
        guard tab == selected else { return Metrics.iconWidth }
        let font = NSFont.systemFont(ofSize: Style.scaled(11), weight: .medium)
        let label = (tab.title as NSString).size(withAttributes: [.font: font]).width
        return Metrics.iconWidth + ceil(label) + Metrics.labelPadding - 6
    }

    private func layoutButtons(animated: Bool) {
        var x = Metrics.inset
        let height = Metrics.height - Metrics.inset * 2
        var highlightFrame: CGRect?

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
            context.allowsImplicitAnimation = animated

            for (tab, button) in buttons {
                let frame = CGRect(x: x, y: Metrics.inset, width: width(of: tab), height: height)
                (animated ? button.animator() : button).frame = frame
                if tab == selected { highlightFrame = frame }
                x += frame.width
            }

            (animated ? highlight.animator() : highlight).alphaValue = highlightFrame == nil ? 0 : 1
            if let highlightFrame {
                (animated ? highlight.animator() : highlight).frame = highlightFrame
            }
        }
    }

    @objc private func handleTab(_ sender: NSButton) {
        guard let tab = PanelTab(rawValue: sender.tag) else { return }
        Haptics.tick()
        select(tab)
    }
}

/// The controls right of the notch: an approvals badge when Claude Code is waiting,
/// the clipboard and the mirror, and a gear whose menu carries Settings and Quit —
/// there is no menu bar icon, so this is where leaving the app lives. Battery fills
/// the end when nothing is waiting.
final class HeaderActionsView: NSView {
    /// One of the circles: the view it stands for.
    var onOpen: ((PanelTab) -> Void)?
    var onSettings: (() -> Void)?
    /// The gear: quick settings in the panel. Right-click still has the old menu.
    var onQuickSettings: (() -> Void)?

    /// True while the gear's menu is open, so the panel doesn't close underneath it.
    private(set) var isShowingMenu = false

    private let badge = Style.badge()
    private lazy var gearButton = Style.symbolButton("gearshape", pointSize: 10, target: self, action: #selector(handleGear))
    private let batteryIcon = NSImageView()
    private let batteryLabel = Style.label("", size: 10, weight: .medium)
    private let stack = NSStackView()

    private static let buttonSize: CGFloat = 22
    private var circles: [PanelTab: NSView] = [:]
    private var tabs: [PanelTab] = []
    private var gearCircle: NSView!
    private var openTab: PanelTab?

    init() {
        super.init(frame: .zero)

        batteryIcon.contentTintColor = Style.secondaryText
        batteryLabel.textColor = Style.secondaryText
        // Labels truncate by default so long titles give way; a battery reading is
        // short and has to be read whole.
        batteryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        // As wide as "100%" from the start, so the reading never truncates and the
        // buttons beside it don't shift as the charge changes.
        batteryLabel.alignment = .right
        let widest = ("100%" as NSString).size(withAttributes: [.font: batteryLabel.font as Any]).width
        batteryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: ceil(widest) + 4).isActive = true
        let battery = NSStackView(views: [batteryLabel, batteryIcon])
        battery.orientation = .horizontal
        battery.spacing = 2

        badge.isHidden = true

        gearCircle = circle(around: gearButton, tip: "Settings ⌘, — every shortcut ⌘/")
        ([badge, gearCircle, battery]).forEach(stack.addArrangedSubview)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.setCustomSpacing(9, after: gearCircle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Top and bottom too, not just the centre: without them this view had no height,
        // and although the buttons still drew, hit-testing stops at a parent's frame —
        // so every click on the right of the header landed on nothing.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        refreshBattery()
        setTabs(HeaderLayout.right)
    }

    /// The circles before the gear, in order — on launch, and when they're rearranged.
    func setTabs(_ tabs: [PanelTab]) {
        guard tabs != self.tabs else { return }
        self.tabs = tabs
        circles.values.forEach { $0.removeFromSuperview() }
        circles.removeAll()
        for (offset, tab) in tabs.enumerated() {
            let button = Style.symbolButton(tab.outlineSymbol, pointSize: 10, target: self, action: #selector(handleCircle(_:)))
            button.tag = tab.rawValue
            let tip = tab == .clipboard
                ? "Clipboard history — ⌘4, or ⌃⌥V anywhere"
                : [tab.title, tab.shortcut].compactMap { $0 }.joined(separator: " — ")
            let circle = circle(around: button, tip: tip)
            circles[tab] = circle
            // After the badge, before the gear.
            stack.insertArrangedSubview(circle, at: 1 + offset)
        }
        setOpen(openTab)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Claude Code approvals waiting. The badge takes the battery's place: in a wing
    /// this narrow, something waiting on you matters more than the charge.
    func setPendingCount(_ count: Int) {
        badge.stringValue = "\(count)"
        badge.isHidden = count == 0
        refreshBattery()
    }

    /// Lights the circle for the view on screen, the way a tab is highlighted: the
    /// clipboard and the mirror are views too, just reached from this side.
    func setOpen(_ tab: PanelTab?) {
        openTab = tab
        for (candidate, circle) in circles {
            let isOpen = candidate == tab
            circle.layer?.backgroundColor = Style.primaryText.withAlphaComponent(isOpen ? 0.2 : 0.08).cgColor
            (circle.subviews.first as? NSButton)?.contentTintColor = isOpen ? Style.primaryText : Style.secondaryText
        }
    }

    /// Read when the panel opens rather than watched: it is only seen while open.
    func refreshBattery() {
        guard badge.isHidden, let state = BatteryMonitor.currentState() else {
            batteryLabel.superview?.isHidden = true
            return
        }
        batteryLabel.superview?.isHidden = false
        batteryLabel.stringValue = "\(state.percent)%"
        let symbol: String
        switch (state.isCharging, state.percent) {
        case (true, _): symbol = "battery.100percent.bolt"
        case (_, 80...): symbol = "battery.100percent"
        case (_, 55..<80): symbol = "battery.75percent"
        case (_, 30..<55): symbol = "battery.50percent"
        case (_, 10..<30): symbol = "battery.25percent"
        default: symbol = "battery.0percent"
        }
        batteryIcon.image = Style.symbolImage(symbol, pointSize: 12, description: "Battery")
    }

    /// The circle is a plain view and the button sits inside it. Sizing the button
    /// itself didn't hold: its bezel's own height won, and the circles came out as
    /// tall pills.
    private func circle(around button: NSButton, tip: String) -> NSView {
        let circle = NSView()
        circle.wantsLayer = true
        circle.layer?.cornerRadius = Self.buttonSize / 2
        circle.layer?.backgroundColor = Style.primaryText.withAlphaComponent(0.08).cgColor
        circle.toolTip = tip
        circle.translatesAutoresizingMaskIntoConstraints = false

        button.toolTip = tip
        button.contentTintColor = Style.secondaryText
        button.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(button)

        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            circle.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            button.leadingAnchor.constraint(equalTo: circle.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: circle.trailingAnchor),
            button.topAnchor.constraint(equalTo: circle.topAnchor),
            button.bottomAnchor.constraint(equalTo: circle.bottomAnchor)
        ])
        return circle
    }

    @objc private func handleCircle(_ sender: NSButton) {
        guard let tab = PanelTab(rawValue: sender.tag) else { return }
        onOpen?(tab)
    }

    @objc private func handleGear() {
        if let onQuickSettings, NSApp.currentEvent?.type != .rightMouseDown {
            onQuickSettings()
            return
        }
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(handleSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NotchHover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        // popUp blocks until the menu closes; until then the panel must stay put.
        isShowingMenu = true
        let below = gearButton.isFlipped ? gearButton.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: gearButton)
        isShowingMenu = false
    }

    @objc private func handleSettings() { onSettings?() }
}
