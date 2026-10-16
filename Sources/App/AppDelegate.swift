import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var poller: NowPlayingPoller?
    private var settingsController: SettingsWindowController?
    private var volumeMonitor: VolumeMonitor?
    private var batteryMonitor: BatteryMonitor?
    private var brightnessMonitor: BrightnessMonitor?

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
        notchController = NotchController(
            mediaController: mediaController,
            poller: poller,
            permissionBridge: PermissionBridge(),
            activityCenter: activityCenter,
            countdown: CountdownTimer(activityCenter: activityCenter)
        )
        notchController?.start()

        ClipboardHistory.shared.start()

        // ⌃⌥ is NotchHover's prefix everywhere: H for Home, S the Shelf, N a note,
        // V the clipboard. Each opens its view or, pressed again, closes the panel.
        // ⌃⌥V rather than ⌥⌘V, which Finder uses to move files; nothing on ⌃⌥Space,
        // which macOS gives to switching input sources.
        let hotKeys: [(Int, PanelTab)] = [
            (kVK_ANSI_H, .home), (kVK_ANSI_S, .shelf), (kVK_ANSI_N, .notes), (kVK_ANSI_V, .clipboard)
        ]
        for (keyCode, tab) in hotKeys {
            HotKeys.shared.register(keyCode: keyCode, modifiers: controlKey | optionKey) { [weak self] in
                self?.notchController?.toggle(tab)
            }
        }

        NotificationWatcher.shared.configure(activityCenter: activityCenter)
        NotificationWatcher.shared.start()

        volumeMonitor = VolumeMonitor(activityCenter: activityCenter)
        volumeMonitor?.start()
        batteryMonitor = BatteryMonitor(activityCenter: activityCenter)
        batteryMonitor?.start()
        brightnessMonitor = BrightnessMonitor(activityCenter: activityCenter)
        brightnessMonitor?.start()

        NotificationCenter.default.addObserver(
            forName: .notchHoverOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showSettings()
        }

        poller.start()

        // NotchHover.app/Contents/MacOS/NotchHover --settings opens straight to settings.
        if CommandLine.arguments.contains("--settings") {
            showSettings()
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
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func handleSettingsMenu() {
        showSettings()
    }

    private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller?.stop()
        ClipboardHistory.shared.stop()
        HotKeys.shared.unregisterAll()
        NotificationWatcher.shared.stop()
        volumeMonitor?.stop()
        batteryMonitor?.stop()
        brightnessMonitor?.stop()
        notchController?.stop()
    }
}
