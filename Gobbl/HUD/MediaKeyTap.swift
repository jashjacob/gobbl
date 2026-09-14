import AppKit
import ApplicationServices

/// Replaces the system volume / brightness HUD: a session event tap swallows
/// the media keys, Gobbl applies the change and shows it in the notch. Needs
/// Accessibility. Also watches Caps Lock (a global flagsChanged monitor, which
/// needs the same permission).
@MainActor
final class MediaKeyTap {
    static let shared = MediaKeyTap()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var flagsMonitor: Any?
    private var capsOn = NSEvent.modifierFlags.contains(.capsLock)
    /// Keys whose key-down we swallowed: swallow their key-up too.
    private var swallowed: Set<Int> = []

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard tap == nil, Self.isTrusted else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED: media keys
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mediaKeyCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.flagsChanged(event) }
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        swallowed.removeAll()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Only re-enable while still trusted: a dead tap that keeps
            // re-enabling itself can stall input.
            if let tap, Self.isTrusted { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
        let key = (ns.data1 & 0xFFFF_0000) >> 16
        let down = (ns.data1 & 0xFF00) >> 8 == 0xA
        // NX_KEYTYPE_SOUND_UP 0, SOUND_DOWN 1, MUTE 7, BRIGHTNESS_UP 2, BRIGHTNESS_DOWN 3
        let isVolume = [0, 1, 7].contains(key)
        let isBrightness = [2, 3].contains(key)
        guard isVolume || isBrightness else { return pass }
        guard down else { return swallowed.remove(key) != nil ? nil : pass }
        let fine = ns.modifierFlags.contains([.option, .shift])
        let handled = isVolume ? SystemHUD.volumeKey(key, fine: fine) : SystemHUD.brightnessKey(up: key == 2, fine: fine)
        guard handled else { return pass }
        swallowed.insert(key)
        return nil
    }

    private func flagsChanged(_ event: NSEvent) {
        let on = event.modifierFlags.contains(.capsLock)
        guard on != capsOn else { return }
        capsOn = on
        HUDModel.shared.show(.init(symbol: on ? "capslock.fill" : "capslock", label: on ? "On" : "Off",
                                   tint: on ? Palette.accent : nil))
    }
}

/// The tap's run loop source is on the main run loop, so this runs on the main thread.
private let mediaKeyCallback: CGEventTapCallBack = { _, type, event, info in
    guard let info else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue()
    return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
}

/// Turns the media-key tap on or off to match settings and permission.
@MainActor
enum HUDService {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "hudReplace") }

    static func apply() {
        if enabled && MediaKeyTap.isTrusted { MediaKeyTap.shared.start() } else { MediaKeyTap.shared.stop() }
    }
}
