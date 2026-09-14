import AppKit
import IOKit.ps

enum Battery {
    struct State: Equatable {
        var level: Double
        var charging: Bool
    }

    /// nil on Macs without a battery.
    static func read() -> State? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return State(level: Double(current) / Double(max),
                         charging: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }

    static func symbol(_ s: State) -> String {
        if s.charging { return "battery.100percent.bolt" }
        switch s.level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Power-source change notifications: a HUD when the charger is connected or
/// removed and when the battery crosses 20% / 10%, and Gob's battery mood.
@MainActor
final class PowerMonitor {
    static let shared = PowerMonitor()

    private var source: CFRunLoopSource?
    private var last: Battery.State?

    func start() {
        guard source == nil else { return }
        last = Battery.read()
        guard last != nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.changed() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        source = src
    }

    private func changed() {
        guard let now = Battery.read() else { return }
        defer { last = now }
        PetModel.shared.send(.battery(level: now.level, charging: now.charging))
        guard let last else { return }
        let percent = "\(Int((now.level * 100).rounded()))%"
        if last.charging != now.charging {
            HUDModel.shared.show(.init(symbol: Battery.symbol(now), label: percent,
                                       tint: now.charging ? Palette.accent : nil), for: 2.2)
            if now.charging { PetModel.shared.send(.pluggedIn) }
        } else if !now.charging, [0.2, 0.1].contains(where: { last.level > $0 && now.level <= $0 }) {
            HUDModel.shared.show(.init(symbol: Battery.symbol(now), label: percent, tint: Color.red), for: 4)
            PetModel.shared.send(.alert)
        }
    }
}

import SwiftUI
