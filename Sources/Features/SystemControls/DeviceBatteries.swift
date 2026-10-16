import AppKit
import CoreAudio

/// A connected accessory and its charge.
struct DeviceBattery: Equatable {
    let name: String
    let kind: Kind
    /// A single level for most devices; AirPods report each bud and the case.
    let main: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?

    enum Kind: Equatable {
        case earbuds, headphones, speaker, keyboard, mouse, trackpad, other

        var symbol: String {
            switch self {
            case .earbuds: return "airpodspro"
            case .headphones: return "headphones"
            case .speaker: return "hifispeaker.fill"
            case .keyboard: return "keyboard.fill"
            case .mouse: return "computermouse.fill"
            case .trackpad: return "rectangle.and.hand.point.up.left.fill"
            case .other: return "dot.radiowaves.left.and.right"
            }
        }
    }

    /// The lowest level it reports — what matters when deciding to warn.
    var lowest: Int? {
        [main, left, right].compactMap { $0 }.min()
    }

    /// "L 80% · R 78% · Case 60%", or "64%".
    var summary: String {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if left == nil, right == nil, let main { parts.append("\(main)%") }
        if let caseLevel { parts.append("Case \(caseLevel)%") }
        return parts.joined(separator: " · ")
    }
}

/// Battery levels of connected Bluetooth accessories, read from what macOS already
/// knows: `system_profiler` for headphones, speakers and anything Bluetooth, and the
/// I/O registry for Apple's own keyboard, mouse and trackpad. Nothing leaves the Mac,
/// and no private API is called.
///
/// The Bluetooth report takes about a second, so it isn't polled constantly: it is read
/// when an audio device comes or goes — which is what AirPods connecting looks like —
/// and every ten minutes while anything is connected.
final class DeviceBatteryMonitor {
    static let shared = DeviceBatteryMonitor()

    private(set) var devices: [DeviceBattery] = []
    private var observers: [UUID: ([DeviceBattery]) -> Void] = [:]
    private let queue = DispatchQueue(label: "com.notchhover.devicebatteries", qos: .utility)
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var deviceListListener: AudioObjectPropertyListenerBlock?

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// Turns changes into live activities: a device that connects pops once with its
    /// levels, and one running low pops at 20% and again at 10%. What was already
    /// connected when the app started stays quiet.
    func announce(to activityCenter: ActivityCenter) {
        var known: [String: DeviceBattery]?
        var warnedAt: [String: Int] = [:]
        addObserver { devices in
            defer { known = Dictionary(devices.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }) }
            guard let previous = known else { return }
            for device in devices {
                if previous[device.name] == nil {
                    activityCenter.post(.device(device))
                    continue
                }
                guard let lowest = device.lowest,
                      let threshold = [10, 20].first(where: { lowest <= $0 }),
                      threshold < (warnedAt[device.name] ?? 100) else { continue }
                warnedAt[device.name] = threshold
                activityCenter.post(.device(device))
            }
        }
    }

    @discardableResult
    func addObserver(_ handler: @escaping ([DeviceBattery]) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func start() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // The battery level arrives a few seconds after the device does.
            self?.refresh(after: 4)
        }
        deviceListListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddress, .main, listener)

        timer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            guard let self, self.devices.isEmpty == false else { return }
            self.refresh()
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        if let listener = deviceListListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddress, .main, listener)
        }
    }

    func refresh(after delay: TimeInterval = 0) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let found = Self.readBluetooth() + Self.readRegistry()
            // One entry per name: a Magic Keyboard shows up in both places.
            var seen = Set<String>()
            let unique = found.filter { seen.insert($0.name).inserted }
            DispatchQueue.main.async { self.publish(unique) }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Hands a new reading to everything watching. Separate so the self-test can feed it.
    func publish(_ found: [DeviceBattery]) {
        guard found != devices else { return }
        devices = found
        Log.system.notice("Accessories with a battery: \(found.map { "\($0.name) \($0.summary)" }.joined(separator: ", "), privacy: .public)")
        observers.values.forEach { $0(found) }
    }

    // MARK: - Reading

    private static func readBluetooth() -> [DeviceBattery] {
        guard let data = run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]) else { return [] }
        return parseBluetooth(data)
    }

    /// The shape `system_profiler -json` uses: connected devices, each a one-key
    /// dictionary of name to properties, with levels as strings like "80%".
    static func parseBluetooth(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        return blocks
            .flatMap { $0["device_connected"] as? [[String: Any]] ?? [] }
            .flatMap { $0 }
            .compactMap { name, value -> DeviceBattery? in
                guard let info = value as? [String: Any] else { return nil }
                func level(_ key: String) -> Int? {
                    (info[key] as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
                }
                let battery = DeviceBattery(
                    name: name,
                    kind: kind(minorType: info["device_minorType"] as? String, name: name, hasBuds: level("device_batteryLevelLeft") != nil),
                    main: level("device_batteryLevelMain"),
                    left: level("device_batteryLevelLeft"),
                    right: level("device_batteryLevelRight"),
                    caseLevel: level("device_batteryLevelCase")
                )
                // A device that reports no battery has nothing to show.
                return battery.lowest == nil && battery.caseLevel == nil ? nil : battery
            }
    }

    /// Apple's keyboards, mice and trackpads publish their charge in the I/O registry.
    private static func readRegistry() -> [DeviceBattery] {
        guard let data = run("/usr/sbin/ioreg", ["-r", "-k", "BatteryPercent", "-a"]),
              let entries = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let name = entry["Product"] as? String, let percent = entry["BatteryPercent"] as? Int else { return nil }
            return DeviceBattery(name: name, kind: kind(minorType: nil, name: name, hasBuds: false), main: percent, left: nil, right: nil, caseLevel: nil)
        }
    }

    private static func kind(minorType: String?, name: String, hasBuds: Bool) -> DeviceBattery.Kind {
        let type = (minorType ?? "").lowercased()
        let lower = name.lowercased()
        if hasBuds || lower.contains("airpods") || lower.contains("buds") { return .earbuds }
        if type.contains("headphone") || type.contains("headset") { return .headphones }
        if type.contains("speaker") { return .speaker }
        if type.contains("keyboard") || lower.contains("keyboard") { return .keyboard }
        if lower.contains("trackpad") { return .trackpad }
        if type.contains("mouse") || lower.contains("mouse") { return .mouse }
        return .other
    }

    private static func run(_ path: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
