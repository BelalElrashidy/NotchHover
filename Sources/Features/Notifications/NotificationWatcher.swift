import AppKit
import ApplicationServices
import AVFoundation

struct CapturedNotification: Equatable {
    let appName: String
    let title: String
    let body: String
    let date: Date

    var summary: String {
        body.isEmpty ? title : "\(title) — \(body)"
    }
}

/// Reads notification banners as they appear.
///
/// macOS has no public API for observing another app's notifications: the Notification
/// Center database is behind Full Disk Access, and nothing is broadcast. This reads the
/// banner windows through the Accessibility API instead, which needs a one-time grant
/// in System Settings › Privacy & Security › Accessibility.
final class NotificationWatcher {
    static let bannerHostBundleIdentifier = "com.apple.notificationcenterui"

    static let shared = NotificationWatcher()

    private var activityCenter: ActivityCenter?
    private var timer: Timer?
    private var trustTimer: Timer?
    private var seen: [String: Date] = [:]
    private let speech = AVSpeechSynthesizer()

    private(set) var recent: [CapturedNotification] = []
    var onCapture: ((CapturedNotification) -> Void)?

    func configure(activityCenter: ActivityCenter) {
        self.activityCenter = activityCenter
    }

    /// Whether this app may read other processes' UI.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open the Accessibility settings.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func start() {
        guard Self.isTrusted else {
            Log.system.notice("Notifications need Accessibility access; watcher idle")
            // Access is granted in System Settings, with no callback, so check back.
            startTrustWatch()
            return
        }
        trustTimer?.invalidate()
        trustTimer = nil

        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.poll()
        }
        Log.system.notice("Notification watcher started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        trustTimer?.invalidate()
        trustTimer = nil
    }

    private func startTrustWatch() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard Self.isTrusted else { return }
            self?.start()
        }
    }

    // MARK: - Reading banners

    private func poll() {
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bannerHostBundleIdentifier)
            .first?.processIdentifier else { return }

        let host = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(host, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        prune()

        for window in windows {
            let texts = staticTexts(in: window)
            guard texts.isEmpty == false else { continue }

            let key = texts.joined(separator: "␟")
            guard seen[key] == nil else { continue }
            seen[key] = Date()

            // Banners read as app name, then title, then body — with the app name
            // sometimes missing for system alerts.
            let appName = texts.count > 2 ? texts[0] : "Notification"
            let title = texts.count > 2 ? texts[1] : texts[0]
            let body = texts.count > 2 ? texts.dropFirst(2).joined(separator: " ") : texts.dropFirst().joined(separator: " ")

            let captured = CapturedNotification(appName: appName, title: title, body: body, date: Date())
            recent.insert(captured, at: 0)
            if recent.count > 12 { recent.removeLast() }

            Log.system.notice("Notification: \(appName, privacy: .public) — \(title, privacy: .public)")
            activityCenter?.post(.notification(app: appName, title: title))
            onCapture?(captured)
            speakIfEnabled(captured)
        }
    }

    /// Banners are reused, so keys are forgotten after a while rather than for ever.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-120)
        seen = seen.filter { $0.value > cutoff }
    }

    private func staticTexts(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }

        var collected: [String] = []
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)

        if roleValue as? String == kAXStaticTextRole as String {
            var textValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
               let text = textValue as? String,
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                collected.append(text)
            }
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                collected.append(contentsOf: staticTexts(in: child, depth: depth + 1))
            }
        }

        return collected
    }

    // MARK: - Speaking

    private func speakIfEnabled(_ notification: CapturedNotification) {
        guard UserDefaults.standard.bool(forKey: "SpeakNotifications") else { return }
        let utterance = AVSpeechUtterance(string: "\(notification.appName). \(notification.title)")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.speak(utterance)
    }
}
