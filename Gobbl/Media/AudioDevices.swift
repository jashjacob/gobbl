import AudioToolbox
import CoreAudio
import Foundation

/// Output device list and switching, and microphone mute, through CoreAudio.
enum AudioDevices {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func outputs() -> [Device] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { hasStreams($0, scope: kAudioDevicePropertyScopeOutput) }
            .compactMap { id in name(of: id).map { Device(id: id, name: $0) } }
    }

    static var defaultOutput: AudioDeviceID? { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }
    static var defaultInput: AudioDeviceID? { defaultDevice(kAudioHardwarePropertyDefaultInputDevice) }

    static func setDefaultOutput(_ device: AudioDeviceID) {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    // MARK: Microphone

    /// Mute state of the default input, via its mute switch or, failing that, its volume.
    static var micMuted: Bool {
        guard let device = defaultInput else { return false }
        var a = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        if AudioObjectHasProperty(device, &a) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr && value != 0
        }
        return inputVolume(device) == 0
    }

    static func setMicMuted(_ muted: Bool) {
        guard let device = defaultInput else { return }
        var a = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(device, &a), AudioObjectIsPropertySettable(device, &a, &settable) == noErr, settable.boolValue {
            var value: UInt32 = muted ? 1 : 0
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            return
        }
        // No mute switch: remember the level, set it to zero, restore it later.
        if muted {
            if let v = inputVolume(device), v > 0 { UserDefaults.standard.set(v, forKey: "micVolumeBeforeMute") }
            setInputVolume(device, 0)
        } else {
            setInputVolume(device, Float(UserDefaults.standard.object(forKey: "micVolumeBeforeMute") as? Double ?? 0.75))
        }
    }

    // MARK: Private

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var a = address(selector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(system, &a, 0, nil, &size, &id) == noErr && id != 0 ? id : nil
    }

    private static func hasStreams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var a = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var a = address(kAudioObjectPropertyName)
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(device, &a, 0, nil, &size, $0) }
        return status == noErr ? name as String? : nil
    }

    private static func inputVolume(_ device: AudioDeviceID) -> Float? {
        var a = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setInputVolume(_ device: AudioDeviceID, _ volume: Float) {
        var a = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(device, &a) else { return }
        var value = Float32(volume)
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}
