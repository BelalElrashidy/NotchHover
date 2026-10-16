import AppKit

/// The layout editor: the panel's widgets as a row of chips you can reorder, remove
/// and add to, plus the sliders that size the panel. Every change saves immediately.
final class LayoutEditorView: NSView {
    var onChange: (() -> Void)?

    private let chipsStack = NSStackView()
    private let summaryLabel = SettingsStyle.label("", size: 11, secondary: true)
    private let slidersStack = NSStackView()
    private var widgets: [PanelWidget] = []

    init() {
        super.init(frame: .zero)

        chipsStack.orientation = .vertical
        chipsStack.alignment = .leading
        chipsStack.spacing = 8

        slidersStack.orientation = .vertical
        slidersStack.alignment = .leading
        slidersStack.spacing = 10

        let addButton = SettingsStyle.capsule("Add widget…", target: self, action: #selector(handleAdd))

        let stack = NSStackView(views: [
            SettingsStyle.heading("Layout"),
            summaryLabel,
            chipsStack,
            addButton,
            SettingsStyle.label("Size", size: 13, secondary: false),
            slidersStack
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(18, after: addButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        reload()
        buildSliders()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Widget chips

    func reload() {
        widgets = PanelLayoutStore.widgets

        chipsStack.arrangedSubviews.forEach {
            chipsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // Three to a line, so a long list wraps instead of running off the window.
        for start in stride(from: 0, to: widgets.count, by: 3) {
            let line = NSStackView()
            line.orientation = .horizontal
            line.spacing = 8
            for index in start..<min(start + 3, widgets.count) {
                line.addArrangedSubview(makeChip(for: widgets[index], at: index))
            }
            chipsStack.addArrangedSubview(line)
        }

        let widths = widgets.reduce(0) { $0 + $1.idealWidth }
        summaryLabel.stringValue = widgets.isEmpty
            ? "No widgets — the panel will open empty"
            : "\(widgets.count) widget\(widgets.count == 1 ? "" : "s") · wants \(Int(widths))pt of content"
    }

    private func makeChip(for widget: PanelWidget, at index: Int) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: widget.symbol, accessibilityDescription: nil)
        icon.contentTintColor = SettingsStyle.theme.primaryText

        let title = SettingsStyle.label(widget.title, size: 12)

        let left = SettingsStyle.capsule("◀", target: self, action: #selector(handleMoveLeft(_:)))
        left.tag = index
        left.isEnabled = index > 0

        let right = SettingsStyle.capsule("▶", target: self, action: #selector(handleMoveRight(_:)))
        right.tag = index
        right.isEnabled = index < widgets.count - 1

        let remove = SettingsStyle.capsule("✕", target: self, action: #selector(handleRemove(_:)))
        remove.tag = index

        [left, right, remove].forEach {
            $0.widthAnchor.constraint(equalToConstant: 26).isActive = true
            $0.alphaValue = $0.isEnabled ? 1 : 0.35
        }

        let row = NSStackView(views: [icon, title, left, right, remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        title.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let chip = SettingsStyle.card(row, padding: 8)
        return chip
    }

    private func commit(_ updated: [PanelWidget]) {
        PanelLayoutStore.set(updated)
        reload()
        onChange?()
    }

    @objc private func handleMoveLeft(_ sender: NSButton) {
        let index = sender.tag
        guard widgets.indices.contains(index), index > 0 else { return }
        var updated = widgets
        updated.swapAt(index, index - 1)
        commit(updated)
    }

    @objc private func handleMoveRight(_ sender: NSButton) {
        let index = sender.tag
        guard widgets.indices.contains(index), index < widgets.count - 1 else { return }
        var updated = widgets
        updated.swapAt(index, index + 1)
        commit(updated)
    }

    @objc private func handleRemove(_ sender: NSButton) {
        let index = sender.tag
        // Let the click finish before its button is rebuilt away.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.widgets.indices.contains(index) else { return }
            var updated = self.widgets
            updated.remove(at: index)
            self.commit(updated)
        }
    }

    @objc private func handleAdd(_ sender: NSButton) {
        let available = PanelWidget.allCases.filter { widgets.contains($0) == false }
        guard available.isEmpty == false else { return }

        let menu = NSMenu()
        for widget in available {
            let item = NSMenuItem(title: widget.title, action: #selector(handlePick(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: widget.symbol, accessibilityDescription: nil)
            item.representedObject = widget.rawValue
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func handlePick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let widget = PanelWidget(rawValue: raw) else { return }
        commit(widgets + [widget])
    }

    // MARK: - Size sliders

    private func buildSliders() {
        let widthMode = SegmentedRow(labels: ["Auto", "Fixed"])
        widthMode.select(PanelSizes.usesAutomaticWidth ? 0 : 1, notify: false)
        widthMode.onSelect = { [weak self] index in
            UserDefaults.standard.set(index == 0 ? "auto" : "fixed", forKey: PanelSizes.Key.widthMode)
            self?.onChange?()
        }
        slidersStack.addArrangedSubview(labelled("Panel width", control: widthMode))

        addSlider("Width (fixed)", key: PanelSizes.Key.width, value: PanelSizes.width, min: 420, max: 1400, unit: "pt")
        addSlider("Panel height", key: PanelSizes.Key.height, value: PanelSizes.height, min: 110, max: 320, unit: "pt")
        addSlider("Resting bar sides", key: PanelSizes.Key.restingWing, value: PanelSizes.restingWing, min: 0, max: 200, unit: "pt")
        addSlider("Resting bar drop", key: PanelSizes.Key.restingExtraHeight, value: PanelSizes.restingExtraHeight, min: 0, max: 40, unit: "pt")
        addSlider("Corner radius", key: PanelSizes.Key.cornerRadius, value: PanelSizes.cornerRadius, min: 12, max: 48, unit: "pt")
        addSlider("Flare", key: PanelSizes.Key.flare, value: PanelSizes.flare, min: 0, max: 60, unit: "pt")
        addSlider("Text size", key: PanelSizes.Key.typeScale, value: PanelSizes.typeScale * 100, min: 85, max: 130, unit: "%")
    }

    private func addSlider(_ title: String, key: String, value: CGFloat, min: CGFloat, max: CGFloat, unit: String) {
        let readout = SettingsStyle.label("\(Int(value))\(unit)", size: 11, secondary: true)
        readout.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let bar = ProgressBarView()
        bar.fraction = Double((value - min) / (max - min))
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        bar.widthAnchor.constraint(equalToConstant: 220).isActive = true
        bar.onScrub = { [weak self] fraction in
            let resolved = min + CGFloat(fraction) * (max - min)
            // Text size is stored as a multiplier, everything else in points.
            let stored = unit == "%" ? resolved / 100 : resolved
            UserDefaults.standard.set(Double(stored), forKey: key)
            readout.stringValue = "\(Int(resolved))\(unit)"
            self?.onChange?()
        }

        let row = NSStackView(views: [bar, readout])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        slidersStack.addArrangedSubview(labelled(title, control: row))
    }

    private func labelled(_ title: String, control: NSView) -> NSView {
        let label = SettingsStyle.label(title, size: 12, secondary: true)
        label.widthAnchor.constraint(equalToConstant: 128).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
}
