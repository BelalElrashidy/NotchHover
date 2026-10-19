import AppKit
import ApplicationServices
import CoreBluetooth
import EventKit

/// Every permission NotchHover may ask for, whether it has it, and where to grant it —
/// Droppy's and Boring Notch's permissions page. Each one is asked for only when the
/// feature that needs it is used; this is where to see them all at once.
enum Permission: CaseIterable {
    case accessibility, automation, calendars, bluetooth, screenRecording, audioRecording, files

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .automation: return "Automation"
        case .calendars: return "Calendars"
        case .bluetooth: return "Bluetooth"
        case .screenRecording: return "Screen Recording"
        case .audioRecording: return "System Audio Recording"
        case .files: return "Files and folders"
        }
    }

    var reason: String {
        switch self {
        case .accessibility: return "Mirroring notification banners, pressing a call's mute and leave, pasting from the clipboard"
        case .automation: return "Reading and controlling Spotify and Music; the page Safari or Chrome is playing; Google Meet's buttons"
        case .calendars: return "The schedule, the peek's next event, and Join buttons"
        case .bluetooth: return "AirPods and accessory batteries"
        case .screenRecording: return "Taking screenshots from the notch"
        case .audioRecording: return "The live visualizer, when it's on"
        case .files: return "Seeing new screenshots, if they're saved to Desktop or Documents"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .automation: return "gearshape.2"
        case .calendars: return "calendar"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .audioRecording: return "waveform"
        case .files: return "folder"
        }
    }

    /// True, false, or nil when macOS gives no way to ask without prompting.
    var isGranted: Bool? {
        switch self {
        case .accessibility:
            return AXIsProcessTrusted()
        case .automation:
            return Self.automationStatus("com.spotify.client") ?? Self.automationStatus("com.apple.Music")
        case .calendars:
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return true
            case .denied, .restricted: return false
            default: return nil
            }
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .audioRecording, .files:
            return nil
        }
    }

    /// Whether NotchHover may script an app, without asking. Nil when the app isn't
    /// running or hasn't been asked yet.
    private static func automationStatus(_ bundleIdentifier: String) -> Bool? {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false else { return nil }
        var target = AEAddressDesc()
        guard let data = bundleIdentifier.data(using: .utf8) else { return nil }
        let created = data.withUnsafeBytes { bytes in
            AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress, data.count, &target)
        }
        guard created == noErr else { return nil }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false) {
        case noErr: return true
        case OSStatus(errAEEventNotPermitted): return false
        default: return nil
        }
    }

    /// The page in System Settings where it's switched on.
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .automation: anchor = "Privacy_Automation"
        case .calendars: anchor = "Privacy_Calendars"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .audioRecording: anchor = "Privacy_AudioCapture"
        case .files: anchor = "Privacy_FilesAndFolders"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    /// Asks where macOS lets an app ask; otherwise opens the page.
    func request() {
        switch self {
        case .accessibility:
            NotificationWatcher.requestTrust()
        case .calendars:
            CalendarService.shared.requestAccessIfNeeded { _ in }
        case .screenRecording:
            if CGRequestScreenCaptureAccess() == false, let url = settingsURL { NSWorkspace.shared.open(url) }
        default:
            if let url = settingsURL { NSWorkspace.shared.open(url) }
        }
    }
}
