import AppKit

/// The Mac's battery and every connected accessory that reports one.
final class DevicesPaneView: NSView {
    private let stack = NSStackView()
    private var observer: UUID?

    init() {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        observer = DeviceBatteryMonitor.shared.addObserver { [weak self] _ in self?.reload() }
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

        if let mac = BatteryMonitor.currentState() {
            stack.addArrangedSubview(row(symbol: mac.isCharging ? "bolt.fill" : "laptopcomputer", name: "This Mac", detail: "\(mac.percent)%"))
        }
        for device in DeviceBatteryMonitor.shared.devices.prefix(3) {
            stack.addArrangedSubview(row(symbol: device.kind.symbol, name: device.name, detail: device.summary))
        }
        if DeviceBatteryMonitor.shared.devices.isEmpty {
            stack.addArrangedSubview(Style.label("No accessories connected", size: 11, color: Style.tertiaryText))
        }
    }

    /// Name and level as one run of text: a name label beside a level label in a stack
    /// clipped the level at draw time, as the shortcut sheet once did.
    private func row(symbol: String, name: String, detail: String) -> NSView {
        let icon = NSImageView()
        icon.image = Style.symbolImage(symbol, pointSize: 12)
        icon.contentTintColor = Style.secondaryText
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let size = Style.scaled(11)
        let text = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: Style.primaryText
        ])
        text.append(NSAttributedString(string: "  " + detail, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: Style.secondaryText
        ]))
        let label = NSTextField(labelWithAttributedString: text)
        label.lineBreakMode = .byTruncatingMiddle

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }
}
