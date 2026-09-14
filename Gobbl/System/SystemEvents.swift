import AppKit
import IOBluetooth

/// Small system moments: a wave from Gob when you come back to the Mac, and
/// (opt-in, because it asks for Bluetooth permission) AirPods battery when
/// they connect.
@MainActor
final class SystemEvents: NSObject {
    static let shared = SystemEvents()

    private var lockedAt: Date?
    private var bluetooth: IOBluetoothUserNotification?

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
        applyBluetooth()
    }

    @objc private func screenLocked() {
        lockedAt = Date()
    }

    @objc private func screenUnlocked() {
        defer { lockedAt = nil }
        guard let lockedAt, Date().timeIntervalSince(lockedAt) > 60 else { return }
        PetModel.shared.send(.welcomeBack)
        HUDModel.shared.show(.init(symbol: "hand.wave.fill", label: "Hi!", tint: Palette.accent), for: 2.5)
    }

    // MARK: AirPods

    func applyBluetooth() {
        let on = UserDefaults.standard.bool(forKey: "airpodsHUD")
        if on, bluetooth == nil {
            bluetooth = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        } else if !on {
            bluetooth?.unregister()
            bluetooth = nil
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio) else { return }
        let name = device.name ?? "Headphones"
        // Battery levels arrive a moment after the connection.
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            let level = Self.battery(of: device)
            let label = level.map { "\($0)%" } ?? "Connected"
            HUDModel.shared.show(.init(symbol: name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones",
                                       label: label, tint: Palette.accent), for: 3)
        }
    }

    /// Undocumented IOBluetoothDevice properties that AirPods and Beats report.
    /// Checked with responds(to:) first, so a missing one is just "no number".
    private static func battery(of device: IOBluetoothDevice) -> Int? {
        let keys = ["batteryPercentCombined", "batteryPercentSingle", "batteryPercentLeft", "batteryPercentRight"]
        let values = keys.compactMap { key -> Int? in
            guard device.responds(to: NSSelectorFromString(key)), let n = device.value(forKey: key) as? Int, n > 0 else { return nil }
            return n
        }
        return values.first
    }
}
