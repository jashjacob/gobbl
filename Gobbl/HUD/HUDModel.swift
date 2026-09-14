import SwiftUI

/// A transient readout shown in the collapsed notch's wings: volume,
/// brightness, battery, Caps Lock, "Copied"…
@MainActor @Observable
final class HUDModel {
    static let shared = HUDModel()

    struct HUD: Equatable {
        var symbol: String
        /// 0–1: drawn as a bar.
        var value: Double?
        /// Short text when there is no bar.
        var label: String?
        var tint: Color?

        init(symbol: String, value: Double? = nil, label: String? = nil, tint: Color? = nil) {
            self.symbol = symbol
            self.value = value
            self.label = label
            self.tint = tint
        }
    }

    private(set) var current: HUD?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ hud: HUD, for seconds: Double = 1.6) {
        current = hud
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        hideTask?.cancel()
        current = nil
    }
}
