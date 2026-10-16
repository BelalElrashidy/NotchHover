import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts. Uses Carbon's hot key API, which — unlike watching
/// every key press — needs no Accessibility permission and sees only its own shortcuts.
final class HotKeys {
    static let shared = HotKeys()

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// `keyCode` is a `kVK_…` value; `modifiers` combine `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        handlers[id] = handler

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E484F56), id: id) // "NHOV"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &reference)

        if status == noErr, let reference {
            references.append(reference)
        } else {
            // Another app already owns this combination.
            Log.system.error("Hot key \(keyCode, privacy: .public) unavailable: \(status, privacy: .public)")
        }
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async {
                HotKeys.shared.handlers[id]?()
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
