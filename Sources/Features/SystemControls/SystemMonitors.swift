import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps

/// Watches the system output volume and reports changes as they happen.
final class VolumeMonitor {
    private let activityCenter: ActivityCenter
    private var deviceID = AudioDeviceID(0)
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastLevel: Double = -1
    private var hasBaseline = false

    init(activityCenter: ActivityCenter) {
        self.activityCenter = activityCenter
    }

    func start() {
        guard let device = SystemControls.defaultOutputDevice() else {
            Log.system.error("No default output device; volume activity disabled")
            return
        }
        deviceID = device

        var address = SystemControls.volumeAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.emitCurrentVolume()
        }
        listener = block

        let status = AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
        guard status == noErr else {
            Log.system.error("Volume listener failed: \(status, privacy: .public)")
            return
        }

        var muteAddress = SystemControls.muteAddress
        AudioObjectAddPropertyListenerBlock(device, &muteAddress, DispatchQueue.main, block)

        // Prime the baseline so the first real change is not reported as a jump.
        lastLevel = SystemControls.volume() ?? 0
        hasBaseline = true
    }

    func stop() {
        guard let listener else { return }
        var address = SystemControls.volumeAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, listener)
        var muteAddress = SystemControls.muteAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, listener)
        self.listener = nil
    }

    private func emitCurrentVolume() {
        guard let level = SystemControls.volume() else { return }
        let muted = SystemControls.isMuted()
        guard hasBaseline == false || abs(level - lastLevel) > 0.001 || muted else {
            return
        }
        lastLevel = level
        activityCenter.post(.volume(level: level, isMuted: muted))
    }

}

/// Reports charge level and plug/unplug events.
final class BatteryMonitor {
    private let activityCenter: ActivityCenter
    private var timer: Timer?
    private var lastState: (percent: Int, isCharging: Bool)?

    init(activityCenter: ActivityCenter) {
        self.activityCenter = activityCenter
    }

    func start() {
        poll(announce: false)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.poll(announce: true)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Current charge, for panes that want to show it without waiting for a change.
    static func currentState() -> (percent: Int, isCharging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (Int(Double(current) / Double(max) * 100), charging)
        }
        return nil
    }

    private func poll(announce: Bool) {
        guard let state = Self.currentState() else { return }
        defer { lastState = state }

        guard announce, let previous = lastState else { return }
        // Only plug/unplug and 10% crossings are worth interrupting for.
        let crossedTen = previous.percent / 10 != state.percent / 10
        guard previous.isCharging != state.isCharging || crossedTen else { return }
        activityCenter.post(.battery(percent: state.percent, isCharging: state.isCharging))
    }
}

/// Display brightness has no public read API, so this uses the private
/// DisplayServices symbol when it resolves and stays silent when it does not.
final class BrightnessMonitor {
    private let activityCenter: ActivityCenter
    private var timer: Timer?
    private var lastDisplay: Double = -1
    private var lastKeyboard: Double = -1

    init(activityCenter: ActivityCenter) {
        self.activityCenter = activityCenter
    }

    func start() {
        guard SystemControls.supportsDisplayBrightness || SystemControls.supportsKeyboardBacklight else {
            Log.system.notice("Brightness unavailable on this system; activity disabled")
            return
        }

        lastDisplay = SystemControls.displayBrightness() ?? -1
        lastKeyboard = SystemControls.keyboardBacklight() ?? -1

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        if let level = SystemControls.displayBrightness(), abs(level - lastDisplay) > 0.005 {
            lastDisplay = level
            activityCenter.post(.brightness(level: level))
        }
        if let level = SystemControls.keyboardBacklight(), abs(level - lastKeyboard) > 0.005 {
            lastKeyboard = level
            activityCenter.post(.keyboardBacklight(level: level))
        }
    }
}

/// Whether anything is actually coming out of the speakers right now — a track, a
/// video in a browser, a call — which is the part `NowPlayingPoller` cannot see,
/// since it can only ask Spotify and Music.
///
/// CoreAudio reports one thing: the output device is running somewhere. An alert
/// sound trips that too, so a short lead-in ignores blips and a longer tail rides
/// over the gaps between tracks, and what comes out is a usable "something is
/// playing" signal rather than a flicker.
final class AudioActivityMonitor {
    /// Called on the main queue whenever the settled answer changes.
    var onChange: ((Bool) -> Void)?
    private(set) var isActive = false

    private var deviceID: AudioDeviceID?
    private var listener: AudioObjectPropertyListenerBlock?
    private var timer: Timer?
    private var settle: DispatchWorkItem?

    private enum Delay {
        /// Long enough that a notification chime never lights the bar up.
        static let start: TimeInterval = 0.6
        /// Long enough to ride over a track change or a buffering video.
        static let stop: TimeInterval = 2.5
    }

    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        bind(to: SystemControls.defaultOutputDevice())
        // The listener covers playback starting and stopping; the poll covers the
        // output device being switched out from under us (AirPods, a display).
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = SystemControls.defaultOutputDevice()
            if current != self.deviceID { self.bind(to: current) }
            self.evaluate()
        }
        // No debounce for the first read: whatever is true at launch is already settled.
        isActive = isRunning
        Log.system.notice("Audio activity at launch: \(self.isActive, privacy: .public)")
        onChange?(isActive)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        settle?.cancel()
        settle = nil
        unbind()
    }

    private var isRunning: Bool {
        guard let deviceID else { return false }
        var address = Self.runningAddress
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
        guard status == noErr, running != 0 else { return false }

        // The device being busy isn't enough. macOS's own daemons — corespeechd, for
        // dictation and Siri — hold it open in silence, which lit the resting bar with
        // nothing playing. Only an app making sound counts. Before 14.4 there is no way
        // to ask which process holds it, so the device has to do.
        guard #available(macOS 14.4, *) else { return true }
        return AudioSourceProbe.current() != nil
    }

    private func bind(to device: AudioDeviceID?) {
        unbind()
        guard let device else {
            Log.system.error("No default output device; audio activity disabled")
            return
        }
        deviceID = device

        var address = Self.runningAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.evaluate()
        }
        let status = AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
        guard status == noErr else {
            Log.system.error("Audio activity listener failed: \(status, privacy: .public)")
            return
        }
        listener = block
    }

    private func unbind() {
        guard let listener, let deviceID else { return }
        var address = Self.runningAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, listener)
        self.listener = nil
    }

    /// Debounced both ways, so neither a chime nor a gap between tracks moves the bar.
    private func evaluate() {
        let running = isRunning
        guard running != isActive else {
            settle?.cancel()
            settle = nil
            return
        }
        guard settle == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.settle = nil
            let settled = self.isRunning
            guard settled != self.isActive else { return }
            self.isActive = settled
            Log.system.notice("Audio activity: \(settled, privacy: .public)")
            self.onChange?(settled)
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (running ? Delay.start : Delay.stop), execute: work)
    }
}
