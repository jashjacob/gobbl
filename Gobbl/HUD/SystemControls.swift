import AppKit
import AudioToolbox
import CoreAudio

/// Default output device volume and mute through CoreAudio.
enum AudioOutput {
    static func defaultDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func volume(_ device: AudioDeviceID) -> Float? {
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    /// HDMI and some USB outputs have no software volume: leave their keys to the system.
    static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &a) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &a, &settable) == noErr && settable.boolValue
    }

    static func setVolume(_ volume: Float, _ device: AudioDeviceID) {
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(max(0, min(1, volume)))
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var a = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &a) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr && value != 0
    }

    static func setMuted(_ muted: Bool, _ device: AudioDeviceID) {
        var a = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &a) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

/// Built-in display brightness through the private DisplayServices framework,
/// loaded at runtime so a missing symbol degrades to "leave it to the system".
enum DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static var builtin: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getFn, getFn(display, &value) == 0 else { return nil }
        return value
    }

    static func set(_ value: Float, _ display: CGDirectDisplayID) -> Bool {
        setFn?(display, max(0, min(1, value))) == 0
    }
}

/// What a volume / brightness key does when Gobbl owns the HUD.
@MainActor
enum SystemHUD {
    /// Returns false to let the system handle the key (no controllable device).
    static func volumeKey(_ key: Int, fine: Bool) -> Bool {
        guard let device = AudioOutput.defaultDevice(), AudioOutput.canSetVolume(device),
              var volume = AudioOutput.volume(device) else { return false }
        var muted = AudioOutput.isMuted(device)
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case 7:
            muted.toggle()
            AudioOutput.setMuted(muted, device)
        case 0:
            volume = min(1, (volume / step).rounded() * step + step)
            AudioOutput.setVolume(volume, device)
            if muted {
                muted = false
                AudioOutput.setMuted(false, device)
            }
        default:
            volume = max(0, (volume / step).rounded() * step - step)
            AudioOutput.setVolume(volume, device)
        }
        let shown = muted ? 0 : Double(volume)
        HUDModel.shared.show(.init(symbol: volumeSymbol(shown, muted: muted), value: shown))
        return true
    }

    static func brightnessKey(up: Bool, fine: Bool) -> Bool {
        guard let display = DisplayBrightness.builtin, let current = DisplayBrightness.get(display) else { return false }
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        let value = max(0, min(1, (current / step).rounded() * step + (up ? step : -step)))
        guard DisplayBrightness.set(value, display) else { return false }
        HUDModel.shared.show(.init(symbol: value < 0.5 ? "sun.min.fill" : "sun.max.fill", value: Double(value), tint: Palette.gold))
        return true
    }

    static func volumeSymbol(_ value: Double, muted: Bool) -> String {
        if muted || value == 0 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.wave.1.fill" }
        if value < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
