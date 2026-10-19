import AppKit
import CoreAudio
import os

/// The level meter's bars, driven by the sound itself rather than a loop — the way Atoll
/// does it: a Core Audio process tap on the app that's playing, mixed to mono, split
/// into low, middle and high bands, each smoothed to rise fast and fall slowly.
///
/// Nothing is recorded or kept: each block of samples is reduced to three numbers and
/// dropped. macOS still asks for **System Audio Recording**, because that is what a tap
/// is, so this is off until switched on in Settings. With it off, denied, or on
/// Bluetooth output, the meter falls back to its animation.
final class AudioLevels {
    static let shared = AudioLevels()
    static let defaultsKey = "LiveVisualizer"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            shared.retarget(force: true)
        }
    }

    /// Low, middle, high, each 0…1 — or nil when the meter should animate on its own.
    private(set) var levels: [Float]?
    private var observers: [UUID: ([Float]?) -> Void] = [:]

    private var target: String?
    private var tap: AnyObject?
    private var analyzer = BandAnalyzer()
    private var displayTimer: Timer?
    private var smoothed: [Float] = [0, 0, 0]
    private var silentSince: Date?
    /// A target that turned out silent — no permission, most likely — isn't retried
    /// until something changes.
    private var gaveUpOn: String?
    private let queue = DispatchQueue(label: "com.notchhover.audiolevels", qos: .userInteractive)

    @discardableResult
    func addObserver(_ handler: @escaping ([Float]?) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    /// Called whenever what's playing changes: the app whose sound the bars should follow.
    func follow(_ bundleIdentifier: String?) {
        guard bundleIdentifier != target else { return }
        target = bundleIdentifier
        gaveUpOn = nil
        retarget(force: false)
    }

    private func retarget(force: Bool) {
        stopTap()
        guard Self.isEnabled, let target, gaveUpOn != target else {
            publish(nil)
            return
        }
        guard Self.outputIsBluetooth == false else {
            // Tapping a player that's on AirPods takes over its Now Playing session, and
            // the AirPods' own pause turns into Siri — Atoll found this. Not worth it.
            Log.media.notice("Live visualizer: Bluetooth output, using the animation")
            publish(nil)
            return
        }
        guard #available(macOS 14.4, *) else { return }

        queue.async { [weak self] in
            let processes = AudioSourceProbe.outputProcessObjects(of: target)
            guard let self, processes.isEmpty == false else { return }
            let analyzer = BandAnalyzer()
            let tap = ProcessTap(processes: processes, queue: self.queue) { samples, count, rate in
                analyzer.process(samples, count: count, sampleRate: rate)
            }
            DispatchQueue.main.async {
                guard let tap, self.target == target else {
                    tap?.stop()
                    if tap == nil { Log.media.error("Live visualizer: couldn't tap \(target, privacy: .public)") }
                    return
                }
                self.tap = tap
                self.analyzer = analyzer
                self.silentSince = nil
                self.startDisplay()
                Log.media.notice("Live visualizer: listening to \(target, privacy: .public)")
            }
        }
    }

    private func stopTap() {
        if #available(macOS 14.4, *) { (tap as? ProcessTap)?.stop() }
        tap = nil
        displayTimer?.invalidate()
        displayTimer = nil
        smoothed = [0, 0, 0]
    }

    /// Thirty times a second: read the bands, ease them, hand them to the meters.
    private func startDisplay() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let reading = analyzer.read()
        // Exact zeros for a few seconds means macOS is handing over silence: the
        // permission was refused, or never asked. Back to the animation.
        if reading.peak == 0 {
            if silentSince == nil { silentSince = Date() }
            if let since = silentSince, Date().timeIntervalSince(since) > 4, let target {
                Log.media.notice("Live visualizer: only silence from \(target, privacy: .public) — is System Audio Recording allowed?")
                gaveUpOn = target
                stopTap()
                publish(nil)
                return
            }
        } else {
            silentSince = nil
        }
        for index in 0..<3 {
            let value = reading.bands[index]
            // Up at once, down gently: the bars land on the beat and settle after it.
            smoothed[index] = value > smoothed[index] ? value : smoothed[index] * 0.82 + value * 0.18
        }
        publish(smoothed)
    }

    private func publish(_ levels: [Float]?) {
        if levels == nil, self.levels == nil { return }
        self.levels = levels
        observers.values.forEach { $0(levels) }
    }

    private static var outputIsBluetooth: Bool {
        guard let device = SystemControls.defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

/// Splits sound into three bands with cascaded one-pole filters (12 dB an octave) — far
/// cheaper than an FFT, and three bars is all there is to fill. Runs on the tap's queue; `read()` takes the
/// latest values from any thread.
final class BandAnalyzer: @unchecked Sendable {
    /// Filter states: the low band's two stages, the low cut ahead of the middle band, the
    /// middle band's two stages, and the high band's two high-pass stages.
    private var low1 = Float(0), low2 = Float(0)
    private var cut1 = Float(0), cut2 = Float(0)
    private var mid1 = Float(0), mid2 = Float(0)
    private var high1 = Float(0), high2 = Float(0)
    private var sums: [Float] = [0, 0, 0]
    private var count = 0
    private var peak = Float(0)
    private var latest = (bands: [Float](repeating: 0, count: 3), peak: Float(0))
    private var lock = os_unfair_lock()

    func process(_ samples: UnsafePointer<Float>, count frames: Int, sampleRate: Double) {
        let lowCoefficient = Float(1 - exp(-2 * Double.pi * 180 / sampleRate))
        let midCoefficient = Float(1 - exp(-2 * Double.pi * 2500 / sampleRate))
        let highCoefficient = Float(1 - exp(-2 * Double.pi * 4000 / sampleRate))
        for index in 0..<frames {
            let x = samples[index]
            // Low: under ~180 Hz.
            low1 += lowCoefficient * (x - low1)
            low2 += lowCoefficient * (low1 - low2)
            // Middle: above ~180 Hz, under ~2.5 kHz.
            cut1 += lowCoefficient * (x - cut1)
            let cutPass = x - cut1
            cut2 += lowCoefficient * (cutPass - cut2)
            let aboveLow = cutPass - cut2
            mid1 += midCoefficient * (aboveLow - mid1)
            mid2 += midCoefficient * (mid1 - mid2)
            // High: over ~4 kHz.
            high1 += highCoefficient * (x - high1)
            let firstPass = x - high1
            high2 += highCoefficient * (firstPass - high2)
            let bands = (low2, mid2, firstPass - high2)
            sums[0] += bands.0 * bands.0
            sums[1] += bands.1 * bands.1
            sums[2] += bands.2 * bands.2
            peak = max(peak, abs(x))
        }
        count += frames
        // About twenty readings a second.
        guard Double(count) >= sampleRate / 20 else { return }

        // Loudness in dB, mapped from -54…-6 dBFS onto 0…1; the high band is naturally
        // quieter in music, so it gets a lift.
        let gains: [Float] = [0, 3, 8]
        let bands = (0..<3).map { index -> Float in
            let rms = (sums[index] / Float(count)).squareRoot()
            let decibels = 20 * log10(max(rms, 1e-7)) + gains[index]
            return min(1, max(0, (decibels + 54) / 48))
        }
        os_unfair_lock_lock(&lock)
        latest = (bands, peak)
        os_unfair_lock_unlock(&lock)
        sums = [0, 0, 0]
        count = 0
        peak = 0
    }

    func read() -> (bands: [Float], peak: Float) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return latest
    }
}

/// A private process tap and the aggregate device that delivers its samples. Built the
/// way Apple's sample code and AudioCap do it; torn down completely on `stop()`.
@available(macOS 14.4, *)
final class ProcessTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(processes: [AudioObjectID], queue: DispatchQueue, onSamples: @escaping (UnsafePointer<Float>, Int, Double) -> Void) {
        let description = CATapDescription(monoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return nil }

        guard let outputUID = Self.defaultOutputUID() else {
            stop()
            return nil
        }
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchHover levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString
            ]]
        ]
        guard AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregateID) == noErr else {
            stop()
            return nil
        }

        let sampleRate = Self.sampleRate(of: aggregateID) ?? 48_000
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData else { continue }
                let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / Int(max(1, buffer.mNumberChannels))
                onSamples(data.assumingMemoryBound(to: Float.self), frames, sampleRate)
            }
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            stop()
            return nil
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func defaultOutputUID() -> String? {
        guard let device = SystemControls.defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func sampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }
}
