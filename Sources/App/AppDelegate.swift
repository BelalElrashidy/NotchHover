import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var poller: NowPlayingPoller?
    private var settingsController: SettingsWindowController?
    private var volumeMonitor: VolumeMonitor?
    private var batteryMonitor: BatteryMonitor?
    private var brightnessMonitor: BrightnessMonitor?
    private var activityCenter: ActivityCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory apps get no menu bar, and without an Edit menu the standard
        // editing shortcuts — including paste — never reach a text field.
        NSApp.mainMenu = Self.makeMainMenu()

        // One hub keeps every AppleScript call on a single serial queue, and one poller
        // owns the only timer that reads the player.
        let mediaController = MediaHub()
        let poller = NowPlayingPoller(mediaController: mediaController)
        self.poller = poller


        let activityCenter = ActivityCenter()
        self.activityCenter = activityCenter
        notchController = NotchController(
            mediaController: mediaController,
            poller: poller,
            permissionBridge: PermissionBridge(),
            activityCenter: activityCenter,
            countdown: CountdownTimer(activityCenter: activityCenter)
        )
        notchController?.start()

        ClipboardHistory.shared.start()

        registerActions()

        // --open-tab notes: opens the panel on a view at launch, to look at it without
        // a hover — for checking a pane's look by hand or by screenshot.
        if let index = CommandLine.arguments.firstIndex(of: "--open-tab"), CommandLine.arguments.count > index + 1,
           let tab = PanelTab.allCases.first(where: { "\($0)".lowercased() == CommandLine.arguments[index + 1].lowercased() }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.notchController?.open(tab) }
        }
        MeetingControls.shared.start()
        ScreenshotStore.shared.onNew = { [weak self] url in self?.notchController?.showScreenshot(url) }
        ScreenshotStore.shared.start()
        FileActionRunner.onReport = { [weak activityCenter] symbol, text in
            activityCenter?.post(.status(symbol: symbol, text: text))
        }

        NotificationWatcher.shared.configure(activityCenter: activityCenter)
        NotificationWatcher.shared.start()

        volumeMonitor = VolumeMonitor(activityCenter: activityCenter)
        volumeMonitor?.start()
        batteryMonitor = BatteryMonitor(activityCenter: activityCenter)
        batteryMonitor?.start()
        brightnessMonitor = BrightnessMonitor(activityCenter: activityCenter)
        brightnessMonitor?.start()
        DeviceBatteryMonitor.shared.announce(to: activityCenter)
        DeviceBatteryMonitor.shared.start()

        // "Claude is done": a session that was working has handed the turn back to you.
        ClaudeSessionMonitor.shared.onFinished = { session in
            activityCenter.post(.claudeDone(project: session.project))
        }
        ClaudeSessionMonitor.shared.start()

        NotificationCenter.default.addObserver(
            forName: .notchHoverOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // ⌘E in the ⌘K list names an action: open Shortcuts on it.
            if let id = note.object as? String {
                self?.showSettings(focusingAction: id)
            } else if let pane = (note.object as? NSNumber)?.intValue, let category = SettingsWindowController.Category(rawValue: pane) {
                // "All settings" and "Edit…" in quick settings land on the right pane.
                self?.showSettings()
                self?.settingsController?.select(category)
            } else {
                self?.showSettings()
            }
        }

        poller.start()

        // NotchHover.app/Contents/MacOS/NotchHover --settings opens straight to settings.
        // --settings 7 opens it on the eighth pane, for checking a pane on screen.
        if let index = CommandLine.arguments.firstIndex(of: "--settings") {
            showSettings()
            if CommandLine.arguments.count > index + 1, let pane = Int(CommandLine.arguments[index + 1]),
               let category = SettingsWindowController.Category(rawValue: pane) {
                settingsController?.select(category)
            }
        }

        // There is no Dock icon and no menu bar icon, so on the very first launch the
        // notch opens for a moment to say where the app lives.
        let isSelfTest = CommandLine.arguments.contains { $0.hasSuffix("-selftest") }
        if isSelfTest == false, UserDefaults.standard.bool(forKey: "HasIntroduced") == false {
            UserDefaults.standard.set(true, forKey: "HasIntroduced")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.notchController?.introduce()
            }
        }

        if CommandLine.arguments.contains("--animation-selftest") {
            AnimationSelfTest.run()
            return
        }

        if CommandLine.arguments.contains("--typing-selftest") {
            TypingSelfTest.run()
            return
        }

        if CommandLine.arguments.contains("--settings-selftest") {
            showSettings()
            settingsController?.runSelfTest()
            exit(0)
        }
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.handleSettingsMenu), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit NotchHover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }

    /// Opening the app again — from Finder, Spotlight or Launchpad — while it is already
    /// running shows Settings. With no icon anywhere, that is the way back in.
    /// `notchhover://add-playlist?url=…&title=…`, from the Share menu's NotchHover.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "notchhover" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard url.host == "add-playlist", let link = items.first(where: { $0.name == "url" })?.value else { continue }
            let title = items.first { $0.name == "title" }?.value
            if let entry = PinnedPlaylists.add(link: link, title: title) {
                Log.media.notice("Pinned from Share: \(entry.name, privacy: .public)")
                // Shown where it now lives, so you see it land.
                notchController?.open(.playlists)
            } else {
                activityCenter?.post(.status(symbol: "exclamationmark.triangle.fill", text: "Not a music link"))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func handleSettingsMenu() {
        showSettings()
    }

    private func showSettings(focusingAction id: String? = nil) {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        if let id {
            settingsController?.show(focusingAction: id)
        } else {
            settingsController?.show()
        }
    }

    /// Everything NotchHover can do by name — for the ⌘K list, the shortcuts table in
    /// Settings, and global hotkeys. ⌃⌥ is NotchHover's prefix: H Home, S the Shelf, N a
    /// note, V the clipboard, M mute, 4 a screenshot. ⌃⌥V rather than ⌥⌘V, which Finder
    /// uses to move files; nothing on ⌃⌥Space, which macOS gives to input sources.
    private func registerActions() {
        func open(_ tab: PanelTab, _ key: Int, _ letter: String, panel: String?) -> NotchAction {
            NotchAction(id: "open.\(tab)", title: "Open \(tab.title)", group: "Panel", symbol: tab.symbol,
                        defaultHotkey: key < 0 ? nil : .controlOption(key, letter), panelKeys: panel, isCustom: false,
                        argumentPrompt: nil, run: { [weak self] _ in self?.notchController?.toggle(tab) })
        }
        func action(_ id: String, _ title: String, _ group: String, _ symbol: String, hotkey: KeyCombo? = nil,
                    panel: String? = nil, _ run: @escaping () -> Void) -> NotchAction {
            NotchAction(id: id, title: title, group: group, symbol: symbol, defaultHotkey: hotkey, panelKeys: panel,
                        isCustom: false, argumentPrompt: nil, run: { _ in run() })
        }
        ActionRegistry.shared.register([
            open(.home, kVK_ANSI_H, "H", panel: "⌘1"),
            open(.shelf, kVK_ANSI_S, "S", panel: "⌘2"),
            open(.notes, kVK_ANSI_N, "N", panel: "⌘3"),
            open(.clipboard, kVK_ANSI_V, "V", panel: "⌘4"),
            open(.screenshots, -1, "", panel: "⌘6"),
            open(.calendar, -1, "", panel: nil),
            open(.mirror, -1, "", panel: "⌘5"),
            action("media.playPause", "Play or pause", "Media", "playpause.fill", panel: "Space") { [weak self] in
                self?.notchController?.performMedia(.playPause)
            },
            action("media.next", "Next track", "Media", "forward.fill", panel: "⌘→") { [weak self] in
                self?.notchController?.performMedia(.nextTrack)
            },
            action("media.previous", "Previous track", "Media", "backward.fill", panel: "⌘←") { [weak self] in
                self?.notchController?.performMedia(.previousTrack)
            },
            action("call.mute", "Mute the call, or the mic", "Calls", "mic.slash.fill",
                   hotkey: .controlOption(kVK_ANSI_M, "M"), panel: "⌘⇧M") {
                MeetingControls.shared.toggleMute()
            },
            action("call.camera", "Camera on or off", "Calls", "video.slash.fill") { MeetingControls.shared.toggleCamera() },
            action("call.join", "Join the next call", "Calls", "video.fill", panel: "⌘J") {
                CalendarService.shared.joinableMeeting()?.link.open()
            },
            action("screenshot.area", "Screenshot an area", "Screenshots", "crop", hotkey: .controlOption(kVK_ANSI_4, "4")) { [weak self] in
                self?.notchController?.capture(.area)
            },
            action("screenshot.window", "Screenshot a window", "Screenshots", "macwindow") { [weak self] in
                self?.notchController?.capture(.window)
            },
            action("screenshot.screen", "Screenshot the screen", "Screenshots", "display") { [weak self] in
                self?.notchController?.capture(.screen)
            },
            action("clipboard.clear", "Clear clipboard history", "Clipboard", "trash") { ClipboardHistory.shared.clear() },
            action("app.settings", "Open Settings", "NotchHover", "gearshape", panel: "⌘,") {
                NotificationCenter.default.post(name: .notchHoverOpenSettings, object: nil)
            }
        ])
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller?.stop()
        ClipboardHistory.shared.stop()
        HotKeys.shared.unregisterAll()
        NotificationWatcher.shared.stop()
        volumeMonitor?.stop()
        batteryMonitor?.stop()
        brightnessMonitor?.stop()
        DeviceBatteryMonitor.shared.stop()
        ClaudeSessionMonitor.shared.stop()
        notchController?.stop()
    }
}
