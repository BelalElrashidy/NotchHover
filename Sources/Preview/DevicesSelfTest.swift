import Foundation

/// Accessory batteries, without needing the accessories: --devices-selftest
enum DevicesSelfTest {
    static func run() {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }

        // The shape system_profiler -json uses for connected devices.
        let sample = """
        {"SPBluetoothDataType":[{
          "device_connected":[
            {"Bilal’s AirPods Pro":{"device_batteryLevelLeft":"80%","device_batteryLevelRight":"78%","device_batteryLevelCase":"60%","device_minorType":"Headphones"}},
            {"JBL Go 3":{"device_batteryLevelMain":"45 %","device_minorType":"Speaker"}},
            {"Car Kit":{"device_minorType":"Headset"}}
          ],
          "device_not_connected":[{"Mine Ear":{"device_minorType":"Headset"}}]
        }]}
        """
        let parsed = DeviceBatteryMonitor.parseBluetooth(Data(sample.utf8))
        expect("connected devices with a battery, and only those", parsed.map(\.name) == ["Bilal’s AirPods Pro", "JBL Go 3"])
        expect("AirPods read as earbuds, both buds and the case", parsed.first?.kind == .earbuds && parsed.first?.summary == "L 80% · R 78% · Case 60%")
        expect("a single level, with a stray space", parsed.last?.main == 45 && parsed.last?.kind == .speaker)
        expect("the lowest level is what warns", parsed.first?.lowest == 78)

        let center = ActivityCenter()
        var posted: [String] = []
        center.addObserver { activity in
            if case .device(let device) = activity { posted.append("\(device.name) \(device.lowest ?? -1)") }
        }
        let monitor = DeviceBatteryMonitor()
        monitor.announce(to: center)
        func buds(_ level: Int) -> DeviceBattery {
            DeviceBattery(name: "AirPods", kind: .earbuds, main: nil, left: level, right: level, caseLevel: 50)
        }
        let speaker = DeviceBattery(name: "Speaker", kind: .speaker, main: 90, left: nil, right: nil, caseLevel: nil)

        monitor.publish([speaker])                 // already there at launch
        monitor.publish([speaker, buds(70)])       // AirPods connect
        monitor.publish([speaker, buds(19)])       // under 20%
        monitor.publish([speaker, buds(18)])       // still under 20%: once is enough
        monitor.publish([speaker, buds(9)])        // under 10%
        monitor.publish([speaker])                 // disconnect
        monitor.publish([speaker, buds(9)])        // back again

        // ActivityCenter delivers on the next turn of the main queue.
        DispatchQueue.main.async {
            expect("quiet at launch, then connect, 20%, 10%, reconnect", posted == ["AirPods 70", "AirPods 19", "AirPods 9", "AirPods 9"])
            let failed = results.filter { $0.hasPrefix("✗") }.count
            FileHandle.standardError.write(Data(("devices: " + results.joined(separator: "  ") + "\n").utf8))
            if failed > 0 { FileHandle.standardError.write(Data(("posted: \(posted)\n").utf8)) }
            exit(failed == 0 ? 0 : 1)
        }
        RunLoop.main.run()
    }
}
