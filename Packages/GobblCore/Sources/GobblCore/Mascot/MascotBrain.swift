import Foundation

/// What Gob is doing right now. Drives the animation (procedural today, a
/// Rive state machine later — each case maps to one state).
public enum Mood: String, Codable, CaseIterable, Sendable {
    case idle, curious, happy, love, eating, burping, dancing, sleepy, sleeping, alert, celebrating, dizzy
}

/// Things that happen to Gob.
public enum MascotSignal: Equatable, Sendable {
    // One-off events → short reactions.
    case filesDropped(Int)
    case filesDraggedOut
    case clipboardCopied
    case petted
    case shaken
    case celebrate
    case alert
    case pluggedIn
    // Ongoing conditions → the resting mood.
    case musicPlaying(Bool)
    case battery(level: Double, charging: Bool)
    case userIdle(TimeInterval)
    case cursorNear(Bool)
}

/// Lifetime stats: what the pet card shows off, and what levels Gob up.
public struct MascotStats: Codable, Equatable, Sendable {
    public var filesGobbled = 0
    public var burps = 0
    public var pets = 0
    public var xp = 0
    public var hatched: Date?

    public init() {}

    /// 1 at 0 XP, 2 at 10, 3 at 40, 4 at 90… (level n starts at 10·(n−1)² XP).
    public var level: Int { Int((Double(xp) / 10).squareRoot()) + 1 }

    /// Evolution stage: baby, teen, grown-up.
    public var stage: Int { level < 5 ? 0 : (level < 12 ? 1 : 2) }

    /// Progress towards the next level, 0–1.
    public var levelProgress: Double {
        let lo = 10 * (level - 1) * (level - 1), hi = 10 * level * level
        return Double(xp - lo) / Double(hi - lo)
    }
}

/// Gob's state machine. A value type with an explicit clock so it can be
/// unit-tested; the app feeds it signals and asks for the mood to draw.
///
/// Priority: a live reaction beats sleeping, which beats dancing, which beats
/// sleepy, which beats curious. Gob never dies and never nags: needs only
/// change how it looks.
public struct MascotBrain: Equatable, Sendable {
    public static let sleepAfter: TimeInterval = 600
    public static let lowBattery = 0.15

    public var stats: MascotStats
    /// Quiet mode: no playful reactions or dancing; direct actions still register.
    public var quiet = false

    public private(set) var musicPlaying = false
    public private(set) var batteryLow = false
    public private(set) var idleSeconds: TimeInterval = 0
    public private(set) var cursorNear = false
    public private(set) var reaction: Mood?
    public private(set) var reactionUntil = Date.distantPast

    public init(stats: MascotStats = MascotStats()) {
        self.stats = stats
    }

    /// Returns true when the signal levelled Gob up.
    @discardableResult
    public mutating func handle(_ signal: MascotSignal, now: Date = Date()) -> Bool {
        let before = stats.level
        switch signal {
        case .filesDropped(let n):
            guard n > 0 else { break }
            stats.filesGobbled += n
            stats.xp += min(n, 5) * 2
            react(.eating, for: 1.2, now: now)
        case .filesDraggedOut:
            stats.burps += 1
            stats.xp += 1
            react(.burping, for: 0.9, now: now)
        case .clipboardCopied:
            react(.curious, for: 0.8, now: now, playful: true)
        case .petted:
            stats.pets += 1
            stats.xp += 1
            react(.love, for: 1.6, now: now)
        case .shaken:
            react(.dizzy, for: 2, now: now, playful: true)
        case .celebrate:
            react(.celebrating, for: 2.5, now: now, playful: true)
        case .alert:
            react(.alert, for: 3, now: now)
        case .pluggedIn:
            react(.happy, for: 1.5, now: now, playful: true)
        case .musicPlaying(let on):
            musicPlaying = on
        case .battery(let level, let charging):
            batteryLow = level < Self.lowBattery && !charging
        case .userIdle(let seconds):
            idleSeconds = max(0, seconds)
        case .cursorNear(let near):
            cursorNear = near
        }
        guard stats.level > before else { return false }
        react(.celebrating, for: 3, now: now)
        return true
    }

    public func mood(at now: Date = Date()) -> Mood {
        if let reaction, now < reactionUntil { return reaction }
        if idleSeconds >= Self.sleepAfter { return .sleeping }
        if musicPlaying && !quiet { return .dancing }
        if batteryLow { return .sleepy }
        if cursorNear { return .curious }
        return .idle
    }

    /// When the current reaction ends, so the app can redraw then (nil if none is live).
    public func nextChange(after now: Date) -> Date? {
        reaction != nil && now < reactionUntil ? reactionUntil : nil
    }

    private mutating func react(_ mood: Mood, for duration: TimeInterval, now: Date, playful: Bool = false) {
        if playful && quiet { return }
        reaction = mood
        reactionUntil = now.addingTimeInterval(duration)
    }
}
