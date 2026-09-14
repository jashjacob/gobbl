import CoreGraphics
import Foundation

/// Spots a quick side-to-side shake of the pointer: several direction
/// reversals, each after a real stroke, inside a short window. Then a
/// cooldown, so one shake fires once.
public struct ShakeDetector: Sendable {
    public var minReversals = 4
    public var window: TimeInterval = 0.7
    /// A stroke shorter than this (points) doesn't count, so jitter isn't a shake.
    public var minTravel: CGFloat = 30
    public var cooldown: TimeInterval = 1.5

    private var lastX: CGFloat?
    private var direction = 0
    private var strokeStart: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var quietUntil: TimeInterval = 0

    public init() {}

    /// Feed every pointer x position; returns true when a shake completes.
    public mutating func feed(x: CGFloat, time: TimeInterval) -> Bool {
        defer { lastX = x }
        guard let lastX else {
            strokeStart = x
            return false
        }
        let dx = x - lastX
        guard abs(dx) > 0.5 else { return false }
        let dir = dx > 0 ? 1 : -1
        if direction == 0 {
            direction = dir
            strokeStart = lastX
            return false
        }
        guard dir != direction else { return false }
        if abs(lastX - strokeStart) >= minTravel { reversals.append(time) }
        direction = dir
        strokeStart = lastX
        reversals.removeAll { time - $0 > window }
        guard reversals.count >= minReversals, time >= quietUntil else { return false }
        reversals.removeAll()
        quietUntil = time + cooldown
        return true
    }
}
