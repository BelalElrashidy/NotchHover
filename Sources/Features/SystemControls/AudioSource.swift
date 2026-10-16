import AppKit
import CoreAudio

/// The app making the sound, when it is not one we can talk to. Spotify and Music
/// answer for themselves through AppleScript, with a track and artwork; everything
/// else — a video in a browser, a call, a game — can only be identified by who owns
/// the audio, and shown by its icon.
struct AudioSource: Equatable {
    let name: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    /// For a browser, the page it is playing — read from the browser's own session
    /// file, so a video reads as the site it is on rather than as the browser.
    var page: BrowserPage?

    /// What to call it: the page, when we know which one, otherwise the app.
    var displayName: String { page?.title ?? name }

    /// Where it is coming from, under the name — "youtube.com", or the app itself.
    var detail: String { page?.shortHost ?? name }

    /// The site's own favicon when there is one, the app's icon otherwise.
    var displayIcon: NSImage? { page?.icon ?? icon }

    var icon: NSImage? {
        let icon = NSRunningApplication(processIdentifier: processIdentifier)?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        // A copy: the running application hands out an icon it keeps, and resizing that
        // one would resize it for everything else holding it too.
        guard let sized = icon?.copy() as? NSImage else { return icon }
        sized.size = NSSize(width: 32, height: 32)
        return sized
    }
}

/// Asks CoreAudio which processes are playing right now and turns that into an app.
///
/// The process that holds the audio is usually not the app you would name: a browser
/// plays through a content or GPU helper, which has its own bundle id and no icon of
/// its own. So every candidate is walked up its parent chain until it reaches
/// something the Dock would show, and daemons that never get there are dropped.
enum AudioSourceProbe {
    /// Processes that are playing but are never the answer: our own panel, and the
    /// system's own sound plumbing.
    private static let ignoredBundleIdentifiers: Set<String> = [
        Bundle.main.bundleIdentifier ?? "com.notchhover.NotchHover",
        "com.apple.controlcenter",
        "com.apple.PowerChime",
        "systemsoundserverd"
    ]

    static func current() -> AudioSource? {
        guard #available(macOS 14.4, *) else { return nil }

        for pid in playingProcessIdentifiers() {
            guard let app = owningApplication(of: pid),
                  let bundleIdentifier = app.bundleIdentifier,
                  ignoredBundleIdentifiers.contains(bundleIdentifier) == false else { continue }

            // A browser with nothing open isn't playing, even if its audio helper still
            // holds the output. Its tabs stay watched, so a window reopened and played
            // counts again on the next look.
            if BrowserPageReader.handles(bundleIdentifier) {
                BrowserPageReader.shared.refresh(for: bundleIdentifier, current: nil) { _ in }
                if BrowserPageReader.shared.hasNoOpenTabs(bundleIdentifier) { continue }
            }

            return AudioSource(
                name: app.localizedName ?? bundleIdentifier,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: app.processIdentifier,
                // Filled in separately: reading it is file work, and this runs on the
                // main thread every time the bar is asked what is playing.
                page: BrowserPageReader.shared.cachedPage(for: bundleIdentifier)
            )
        }
        return nil
    }

    /// Every process CoreAudio says is running output right now.
    @available(macOS 14.4, *)
    private static func playingProcessIdentifiers() -> [pid_t] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr else {
            return []
        }

        return objects.compactMap { object in
            guard property(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1 else { return nil }
            return property(object, kAudioProcessPropertyPID, pid_t(0))
        }
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// The app macOS holds responsible for a process. XPC helpers are started by
    /// launchd, so their parent says nothing — Safari's audio comes out of
    /// `com.apple.WebKit.GPU`, whose parent is launchd — but the system still records
    /// which app they work for. Private, long-stable, and resolved at runtime so a
    /// future macOS without it only loses the shortcut, not the feature.
    private static let responsiblePID: ResponsibleFunction? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    /// The app a process belongs to: the app responsible for it, then itself, then
    /// whichever ancestor is one. Four levels is more than any helper chain in practice
    /// and keeps a broken parent link from looping.
    private static func owningApplication(of pid: pid_t) -> NSRunningApplication? {
        if let owner = responsiblePID?(pid), owner > 0, owner != pid,
           let app = NSRunningApplication(processIdentifier: owner), app.activationPolicy != .prohibited {
            return app
        }

        var current: pid_t? = pid
        for _ in 0..<4 {
            guard let candidate = current else { return nil }
            if let app = NSRunningApplication(processIdentifier: candidate), app.activationPolicy != .prohibited {
                return app
            }
            current = parentProcessIdentifier(of: candidate)
        }
        return nil
    }

    private static func parentProcessIdentifier(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        // launchd owns everything; arriving there means nothing owns this but the system.
        return parent > 1 ? parent : nil
    }
}
