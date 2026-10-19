import AppKit
import Carbon.HIToolbox

/// A call in progress, as far as NotchHover can tell.
struct CallState: Equatable {
    enum Provider: Equatable {
        case zoom, teams, webex, facetime, slack
        /// Google Meet in a browser tab, by the browser's bundle identifier.
        case meet(browser: String)
    }

    let provider: Provider
    let appName: String
    let bundleIdentifier: String
    /// The meeting's own name when the app shows one — a Meet tab's title.
    var title: String?
    /// Nil when the app doesn't say; the controls still toggle.
    var isMuted: Bool?
    var isCameraOff: Bool?
    var startedAt: Date
    /// Meet's state is read with JavaScript from Apple Events, which browsers ship off.
    var needsBrowserSetting = false

    var service: String {
        switch provider {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .slack: return "Slack"
        case .meet: return "Google Meet"
        }
    }

    /// FaceTime and Slack offer nothing reliable to press; their mute is the Mac's own.
    var hasCamera: Bool {
        switch provider {
        case .facetime, .slack: return false
        default: return true
        }
    }

    var canLeave: Bool { hasCamera }
}

/// Mute, camera and leave for the call you're on, from the notch. Everything stays on
/// the Mac: a call is noticed by which app is using the microphone, and controlled the
/// way you would — Zoom through its Meeting menu (which also says whether you're muted),
/// Teams and Webex through their own buttons or shortcuts, Google Meet with a line of
/// JavaScript in its tab, and anything else with the Mac's microphone mute.
///
/// The menus and buttons need Accessibility, which NotchHover already asks for to read
/// notifications. Without it the mute still works, as the system's.
final class MeetingControls {
    static let shared = MeetingControls()

    private(set) var call: CallState?
    private var observers: [UUID: (CallState?) -> Void] = [:]
    private let queue = DispatchQueue(label: "com.notchhover.meetingcontrols", qos: .userInitiated)
    private var timer: Timer?

    static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.apple.Safari"
    ]

    @discardableResult
    func addObserver(_ handler: @escaping (CallState?) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
    }

    func refresh() {
        let previous = call
        queue.async { [weak self] in
            let found = Self.detect(previous: previous)
            DispatchQueue.main.async { self?.publish(found) }
        }
    }

    private func publish(_ found: CallState?) {
        guard found != call else { return }
        if (found == nil) != (call == nil) {
            Log.ui.notice("Call: \(found.map { "\($0.service) started" } ?? "ended", privacy: .public)")
        }
        call = found
        observers.values.forEach { $0(found) }
    }

    /// Preview hook.
    func publishForPreview(_ state: CallState?) {
        publish(state)
    }

    // MARK: - Controls

    func toggleMute() {
        guard let call else {
            SystemControls.setInputMuted(SystemControls.isInputMuted() == false)
            return
        }
        perform(call) { call in
            switch call.provider {
            case .zoom:
                return Self.pressMenuItem(in: call, menu: "Meeting", titles: ["Unmute Audio", "Mute Audio"])
            case .teams:
                return Self.pressButton(in: call, matching: ["Unmute", "Mute"]) || Self.sendKey(kVK_ANSI_M, [.maskCommand, .maskShift], to: call)
            case .webex:
                return Self.sendKey(kVK_ANSI_M, [.maskCommand, .maskShift], to: call)
            case .meet(let browser):
                return Self.runMeetScript(browser: browser, action: "mic") != nil
            case .facetime, .slack:
                return false
            }
        } fallback: {
            SystemControls.setInputMuted(SystemControls.isInputMuted() == false)
        }
    }

    func toggleCamera() {
        guard let call, call.hasCamera else { return }
        perform(call) { call in
            switch call.provider {
            case .zoom:
                return Self.pressMenuItem(in: call, menu: "Meeting", titles: ["Start Video", "Stop Video"])
            case .teams:
                return Self.pressButton(in: call, matching: ["Turn camera on", "Turn camera off", "Camera"])
                    || Self.sendKey(kVK_ANSI_O, [.maskCommand, .maskShift], to: call)
            case .webex:
                return Self.sendKey(kVK_ANSI_V, [.maskControl, .maskShift], to: call)
            case .meet(let browser):
                return Self.runMeetScript(browser: browser, action: "camera") != nil
            case .facetime, .slack:
                return false
            }
        } fallback: {}
    }

    func leave() {
        guard let call, call.canLeave else { return }
        perform(call) { call in
            switch call.provider {
            case .zoom:
                // Zoom asks "Leave meeting?" itself, so a stray click can't drop the call.
                return Self.pressMenuItem(in: call, menu: "Meeting", titles: ["Leave Meeting", "End Meeting"])
                    || Self.sendKey(kVK_ANSI_W, [.maskCommand], to: call)
            case .teams:
                return Self.pressButton(in: call, matching: ["Leave"]) || Self.sendKey(kVK_ANSI_H, [.maskCommand, .maskShift], to: call)
            case .webex:
                return Self.sendKey(kVK_ANSI_L, [.maskCommand], to: call)
            case .meet(let browser):
                return Self.runMeetScript(browser: browser, action: "leave") != nil
            case .facetime, .slack:
                return false
            }
        } fallback: {}
    }

    private func perform(_ call: CallState, _ action: @escaping (CallState) -> Bool, fallback: @escaping () -> Void) {
        queue.async { [weak self] in
            let worked = action(call)
            DispatchQueue.main.async {
                if worked == false { fallback() }
                Haptics.tick()
                // The app needs a moment to redraw before its state reads true.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refresh() }
            }
        }
    }

    // MARK: - Finding the call

    private static func detect(previous: CallState?) -> CallState? {
        let running = NSWorkspace.shared.runningApplications
        let recording = AudioSourceProbe.recordingApplications()
        let recordingIDs = Set(recording.compactMap(\.bundleIdentifier))
        func started(_ provider: CallState.Provider) -> Date {
            previous?.provider == provider ? previous!.startedAt : Date()
        }

        // Zoom's Meeting menu exists only in a meeting, muted or not — better than the
        // microphone, which Zoom may let go of while muted.
        if let zoom = running.first(where: { $0.bundleIdentifier == "us.zoom.xos" }),
           let items = menuItemTitles(of: zoom, menu: "Meeting") {
            return CallState(
                provider: .zoom, appName: "Zoom", bundleIdentifier: "us.zoom.xos",
                isMuted: items.contains("Unmute Audio") ? true : (items.contains("Mute Audio") ? false : nil),
                isCameraOff: items.contains("Start Video") ? true : (items.contains("Stop Video") ? false : nil),
                startedAt: started(.zoom)
            )
        }

        for app in recording {
            guard let id = app.bundleIdentifier else { continue }
            switch id {
            case "com.microsoft.teams2", "com.microsoft.teams":
                let labels = buttonLabels(of: app)
                return CallState(
                    provider: .teams, appName: "Teams", bundleIdentifier: id,
                    isMuted: labels.contains { $0.hasPrefix("Unmute") } ? true : (labels.contains { $0.hasPrefix("Mute") } ? false : nil),
                    isCameraOff: labels.contains { $0.hasPrefix("Turn camera on") } ? true : (labels.contains { $0.hasPrefix("Turn camera off") } ? false : nil),
                    startedAt: started(.teams)
                )
            case "Cisco-Systems.Spark", "com.webex.meetingmanager", "com.cisco.webexmeetingsapp":
                return CallState(provider: .webex, appName: "Webex", bundleIdentifier: id, startedAt: started(.webex))
            case "com.apple.FaceTime":
                return CallState(provider: .facetime, appName: "FaceTime", bundleIdentifier: id,
                                 isMuted: SystemControls.isInputMuted(), startedAt: started(.facetime))
            case "com.tinyspeck.slackmacgap":
                return CallState(provider: .slack, appName: "Slack", bundleIdentifier: id,
                                 isMuted: SystemControls.isInputMuted(), startedAt: started(.slack))
            default:
                break
            }
        }

        // A browser with the microphone: a Meet tab, if it has one.
        for id in recordingIDs.intersection(browsers) {
            guard let answer = runMeetScript(browser: id, action: "state") else { continue }
            let provider = CallState.Provider.meet(browser: id)
            let name = running.first { $0.bundleIdentifier == id }?.localizedName ?? "Browser"
            if answer == "JS-OFF" {
                return CallState(provider: provider, appName: name, bundleIdentifier: id, title: "Google Meet",
                                 isMuted: SystemControls.isInputMuted(), startedAt: started(provider), needsBrowserSetting: true)
            }
            let parts = answer.components(separatedBy: "\u{1F}")
            guard parts.count >= 3, parts[0] != "x" else { continue }
            return CallState(
                provider: provider, appName: name, bundleIdentifier: id,
                title: parts[2].replacingOccurrences(of: "Meet - ", with: "").replacingOccurrences(of: "Meet – ", with: ""),
                isMuted: parts[0] == "true", isCameraOff: parts[1] == "x" ? nil : parts[1] == "true",
                startedAt: started(provider)
            )
        }
        return nil
    }

    // MARK: - Accessibility

    private static func menuBar(of app: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute as CFString, &value) == .success else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// The items of a top-level menu, or nil when the app has no such menu.
    private static func menuItems(of app: NSRunningApplication, menu title: String) -> [AXUIElement]? {
        guard let bar = menuBar(of: app),
              let menu = children(bar).first(where: { string($0, kAXTitleAttribute) == title }) else { return nil }
        return children(menu).flatMap(children)
    }

    private static func menuItemTitles(of app: NSRunningApplication, menu: String) -> [String]? {
        menuItems(of: app, menu: menu)?.compactMap { string($0, kAXTitleAttribute) }
    }

    /// Presses whichever of `titles` the menu has — a toggle shows one or the other.
    private static func pressMenuItem(in call: CallState, menu: String, titles: [String]) -> Bool {
        guard let app = application(of: call), let items = menuItems(of: app, menu: menu),
              let item = items.first(where: { titles.contains(string($0, kAXTitleAttribute) ?? "") }) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Button labels in the app's windows, a few levels deep — enough for Teams' call bar.
    private static func buttonLabels(of app: NSRunningApplication) -> [String] {
        buttons(of: app).compactMap { label(of: $0) }
    }

    private static func buttons(of app: NSRunningApplication) -> [AXUIElement] {
        guard AXIsProcessTrusted() else { return [] }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        var found: [AXUIElement] = []
        var budget = 4000
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 40, budget > 0 else { return }
            budget -= 1
            if string(element, kAXRoleAttribute) == kAXButtonRole as String { found.append(element) }
            children(element).forEach { walk($0, depth: depth + 1) }
        }
        windows.forEach { walk($0, depth: 0) }
        return found
    }

    private static func label(of element: AXUIElement) -> String? {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].lazy.compactMap { string(element, $0) }.first { $0.isEmpty == false }
    }

    private static func pressButton(in call: CallState, matching prefixes: [String]) -> Bool {
        guard let app = application(of: call),
              let button = buttons(of: app).first(where: { element in
                  guard let label = label(of: element) else { return false }
                  return prefixes.contains { label.hasPrefix($0) }
              }) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// A keystroke straight to the app, without bringing it to the front.
    private static func sendKey(_ key: Int, _ flags: CGEventFlags, to call: CallState) -> Bool {
        guard AXIsProcessTrusted(), let app = application(of: call) else { return false }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: isDown) else { return false }
            event.flags = flags
            event.postToPid(app.processIdentifier)
        }
        return true
    }

    private static func application(of call: CallState) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: call.bundleIdentifier).first
    }

    // MARK: - Google Meet

    /// Meet's buttons carry `data-is-muted`, which is what a person sees as the red mic.
    private static func meetJavaScript(_ action: String) -> String {
        """
        (function(){var mic=document.querySelector('[data-is-muted][aria-label*="microphone" i]');\
        var cam=document.querySelector('[data-is-muted][aria-label*="camera" i]');\
        var act='\(action)';\
        if(act==='mic'&&mic){mic.click();}\
        if(act==='camera'&&cam){cam.click();}\
        if(act==='leave'){var l=document.querySelector('[aria-label="Leave call" i]');if(l){l.click();}}\
        return (mic?mic.getAttribute('data-is-muted'):'x')+'\\u001f'+(cam?cam.getAttribute('data-is-muted'):'x')+'\\u001f'+document.title;})()
        """
    }

    /// Self-test: whether the Meet script compiles against an installed browser's
    /// scripting dictionary — the check that it would run there — without running it.
    static func meetScriptCompiles(browser: String) -> Bool? {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) != nil else { return nil }
        let source = meetSource(browser: browser, action: "state")
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        return script.compileAndReturnError(&error)
    }

    /// Runs the Meet script in the first Meet tab. Nil when there is none; "JS-OFF" when
    /// the browser doesn't allow JavaScript from Apple Events.
    static func runMeetScript(browser: String, action: String) -> String? {
        guard let script = NSAppleScript(source: meetSource(browser: browser, action: action)) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error).stringValue ?? ""
        return result.isEmpty ? nil : result
    }

    private static func meetSource(browser: String, action: String) -> String {
        let js = meetJavaScript(action).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let isSafari = browser == "com.apple.Safari"
        let run = isSafari ? "do JavaScript \"\(js)\" in t" : "execute t javascript \"\(js)\""
        return """
        tell application id "\(browser)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "meet.google.com/" and u does not end with "meet.google.com/" and u does not contain "/landing" then
                        try
                            return \(run)
                        on error errorMessage number errorNumber
                            return "JS-OFF"
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
    }
}
