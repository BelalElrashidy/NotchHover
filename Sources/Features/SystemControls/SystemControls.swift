import AppKit
import AudioToolbox
import CoreAudio

/// Reading and setting the three things the notch HUD covers: output volume,
/// display brightness, and keyboard backlight.
///
/// Volume is public CoreAudio. Brightness and backlight have no public API, so they
/// go through private symbols resolved at runtime — every call degrades to a no-op
/// if a future macOS drops them.
enum SystemControls {

    // MARK: - Output volume (CoreAudio)

    static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    static func volume() -> Double? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = volumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? Double(value) : nil
    }

    static func setVolume(_ level: Double) {
        guard let device = defaultOutputDevice() else { return }
        var address = volumeAddress
        var value = Float32(max(0, min(1, level)))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        // Nudging the slider up should also take it off mute.
        if value > 0, isMuted() { setMuted(false) }
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = muteAddress
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value == 1
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = muteAddress
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    // MARK: - Microphone input (CoreAudio)

    private static var inputVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var inputMuteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    /// Plenty of inputs have no gain control at all — most USB interfaces, some
    /// Bluetooth headsets — so the pane asks before it offers a slider.
    static var supportsInputVolume: Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = inputVolumeAddress
        return AudioObjectHasProperty(device, &address)
    }

    static var supportsInputMute: Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = inputMuteAddress
        return AudioObjectHasProperty(device, &address)
    }

    static func inputVolume() -> Double? {
        guard let device = defaultInputDevice() else { return nil }
        var address = inputVolumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? Double(value) : nil
    }

    static func setInputVolume(_ level: Double) {
        guard let device = defaultInputDevice() else { return }
        var address = inputVolumeAddress
        var value = Float32(max(0, min(1, level)))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        // Dragging the mic up should also take it off mute, as the output slider does.
        if value > 0, isInputMuted() { setInputMuted(false) }
    }

    static func isInputMuted() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = inputMuteAddress
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value == 1
    }

    static func setInputMuted(_ muted: Bool) {
        guard let device = defaultInputDevice() else { return }
        var address = inputMuteAddress
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    /// What the input is called, for the row's tooltip — "MacBook Air Microphone".
    static func inputDeviceName() -> String? {
        guard let device = defaultInputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        return status == noErr ? (name as String) : nil
    }

    // MARK: - Display brightness (DisplayServices)

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let displayServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    private static let getBrightness: GetBrightnessFn? = displayServices
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetBrightnessFn.self) }

    private static let setBrightnessFn: SetBrightnessFn? = displayServices
        .flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetBrightnessFn.self) }

    static var supportsDisplayBrightness: Bool { getBrightness != nil }

    static func displayBrightness() -> Double? {
        guard let getBrightness else { return nil }
        var level: Float = 0
        return getBrightness(CGMainDisplayID(), &level) == 0 ? Double(level) : nil
    }

    static func setDisplayBrightness(_ level: Double) {
        guard let setBrightnessFn else { return }
        _ = setBrightnessFn(CGMainDisplayID(), Float(max(0, min(1, level))))
    }

    // MARK: - Keyboard backlight (CoreBrightness)

    private static let keyboardClient: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            Log.system.notice("Keyboard backlight control unavailable")
            return nil
        }
        return type.init()
    }()

    /// The built-in keyboard is device 1.
    private static let keyboardID: UInt64 = 1

    static var supportsKeyboardBacklight: Bool { keyboardClient != nil }

    static func keyboardBacklight() -> Double? {
        guard let client = keyboardClient else { return nil }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard client.responds(to: selector), let method = client.method(for: selector) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Float
        return Double(unsafeBitCast(method, to: Fn.self)(client, selector, keyboardID))
    }

    static func setKeyboardBacklight(_ level: Double) {
        guard let client = keyboardClient else { return }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard client.responds(to: selector), let method = client.method(for: selector) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Void
        unsafeBitCast(method, to: Fn.self)(client, selector, Float(max(0, min(1, level))), keyboardID)
    }
}
