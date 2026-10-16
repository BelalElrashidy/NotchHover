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

    private func row(symbol: String, name: String, detail: String) -> NSView {
        let icon = NSImageView()
        icon.image = Style.symbolImage(symbol, pointSize: 12)
        icon.contentTintColor = Style.secondaryText
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let title = Style.label(name, size: 11, weight: .medium)
        let value = Style.label(detail, size: 11, color: Style.secondaryText)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [icon, title, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }
}
