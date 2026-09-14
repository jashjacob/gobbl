import Carbon.HIToolbox

/// A global keyboard shortcut through Carbon's RegisterEventHotKey, which —
/// unlike an event tap — needs no permission.
@MainActor
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// `keyCode` is a kVK_ constant; `modifiers` a mask of cmdKey, shiftKey, optionKey, controlKey.
    init?(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        Self.installHandler()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: 0x4742_4C21 /* GBL! */, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        self.ref = ref
        self.id = id
        Self.handlers[id] = action
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let id = hotKey.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.handlers[id]?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
