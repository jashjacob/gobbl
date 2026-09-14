import Foundation

/// Raw input for the Gobbl key (right ⌥). Times are seconds on a monotonic clock.
public enum GobblKeyEvent: Equatable, Sendable {
    case down(TimeInterval)
    case up(TimeInterval)
    /// Any other key or modifier while the Gobbl key is in play.
    case otherKey(TimeInterval)
    /// A clock tick, so holds and double-tap windows resolve without new input.
    case tick(TimeInterval)
}

public enum GobblKeyAction: Equatable, Sendable {
    /// Write / rewrite.
    case tap
    /// Edit mode.
    case doubleTap
    /// Dictation starts. `locked` for double-tap-and-hold (hands-free).
    case holdBegan(locked: Bool)
    case holdEnded
    /// ⌥ was used as a modifier (⌥E for é…): do nothing.
    case cancelled
}

/// Turns right-⌥ presses into tap / double-tap / hold. A tap only fires once
/// the double-tap window has passed, so a double-tap never also writes.
public struct GobblKeyMachine: Sendable {
    /// Long enough that an unhurried tap isn't taken for a hold.
    public var holdThreshold: TimeInterval = 0.35
    public var doubleTapWindow: TimeInterval = 0.3

    private enum State: Equatable {
        case idle
        case down(TimeInterval)
        case awaitingSecond(TimeInterval)
        case secondDown(TimeInterval)
        case holding
    }

    private var state = State.idle

    public init() {}

    /// Ticks are only needed while a hold or a double-tap window is pending.
    public var needsTicks: Bool {
        switch state {
        case .idle, .holding: false
        default: true
        }
    }

    public var isHolding: Bool { state == .holding }

    public mutating func handle(_ event: GobblKeyEvent) -> GobblKeyAction? {
        switch (state, event) {
        case (.idle, .down(let t)):
            state = .down(t)
            return nil

        case (.down, .otherKey):
            state = .idle
            return .cancelled
        case (.down(let t0), .tick(let t)) where t - t0 >= holdThreshold:
            state = .holding
            return .holdBegan(locked: false)
        case (.down(let t0), .up(let t)):
            if t - t0 >= holdThreshold {
                // Released before a tick noticed the hold: a very short dictation.
                state = .idle
                return .holdEnded
            }
            state = .awaitingSecond(t)
            return nil

        case (.awaitingSecond(let released), .down(let t)):
            if t - released <= doubleTapWindow {
                state = .secondDown(t)
                return nil
            }
            // Too late for a double-tap: the first press was a tap, this one starts fresh.
            state = .down(t)
            return .tap
        case (.awaitingSecond(let released), .tick(let t)) where t - released > doubleTapWindow:
            state = .idle
            return .tap
        case (.awaitingSecond, .otherKey):
            state = .idle
            return .tap

        case (.secondDown, .up):
            state = .idle
            return .doubleTap
        case (.secondDown(let t0), .tick(let t)) where t - t0 >= holdThreshold:
            state = .holding
            return .holdBegan(locked: true)
        case (.secondDown, .otherKey):
            state = .idle
            return .cancelled

        case (.holding, .up):
            state = .idle
            return .holdEnded

        default:
            return nil
        }
    }
}
