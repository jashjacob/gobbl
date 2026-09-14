import AppKit
import IOKit.pwr_mgt
import Observation

/// Pomodoro: focus, then a short break, then idle. Gob celebrates each
/// finished focus session. Nothing ticks: views draw the remaining time from
/// `endDate`, and one task fires at the end.
@MainActor @Observable
final class FocusTimer {
    static let shared = FocusTimer()

    enum Phase: Equatable {
        case idle, focus, rest
    }

    private(set) var phase: Phase = .idle
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var completedToday = 0

    @ObservationIgnored private var finishTask: Task<Void, Never>?

    var focusMinutes: Int {
        get { UserDefaults.standard.object(forKey: "focusMinutes") as? Int ?? 25 }
        set { UserDefaults.standard.set(newValue, forKey: "focusMinutes") }
    }

    var restMinutes: Int {
        get { UserDefaults.standard.object(forKey: "restMinutes") as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "restMinutes") }
    }

    var isRunning: Bool { endDate != nil }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? duration(of: phase == .idle ? .focus : phase)
    }

    func start() {
        if phase == .idle { phase = .focus }
        let seconds = pausedRemaining ?? duration(of: phase)
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(seconds)
        schedule(seconds)
    }

    func pause() {
        guard isRunning else { return }
        pausedRemaining = remaining()
        endDate = nil
        finishTask?.cancel()
    }

    func toggle() { isRunning ? pause() : start() }

    func reset() {
        finishTask?.cancel()
        phase = .idle
        endDate = nil
        pausedRemaining = nil
    }

    private func duration(of phase: Phase) -> TimeInterval {
        Double(phase == .rest ? restMinutes : focusMinutes) * 60
    }

    private func schedule(_ seconds: TimeInterval) {
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        endDate = nil
        if phase == .focus {
            completedToday += 1
            PetModel.shared.send(.celebrate)
            HUDModel.shared.show(.init(symbol: "checkmark.circle.fill", label: "Break", tint: Palette.accent), for: 4)
            NSSound(named: "Glass")?.play()
            phase = .rest
            start()
        } else {
            phase = .idle
            HUDModel.shared.show(.init(symbol: "timer", label: "Go!", tint: Palette.accent), for: 4)
            NSSound(named: "Hero")?.play()
        }
    }
}

/// Keeps the display awake (like `caffeinate -d`) through a power assertion.
@MainActor @Observable
final class KeepAwake {
    static let shared = KeepAwake()

    private(set) var isOn = false
    @ObservationIgnored private var assertion: IOPMAssertionID = 0

    func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Gobbl: keep awake" as CFString, &assertion)
            isOn = result == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isOn = false
        }
    }

    func toggle() { set(!isOn) }
}
