import Foundation

/// What Gob is doing right now. Drives the animation (procedural today, a
/// Rive state machine later — each case maps to one state).
public enum Mood: String, Codable, CaseIterable, Sendable {
    case idle, curious, happy, love, eating, burping, dancing, sleepy, sleeping, alert, celebrating, dizzy
    /// An AI agent (Claude Code, Codex) is busy.
    case working
    /// The Mac's CPU is pegged.
    case sweaty
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
    case welcomeBack
    case milestone
    case agentDone
    case agentNeedsInput
    // Ongoing conditions → the resting mood.
    case musicPlaying(Bool)
    case battery(level: Double, charging: Bool)
    case userIdle(TimeInterval)
    case cursorNear(Bool)
    case cpuLoad(Double)
    case agentsWorking(Bool)
}

/// Lifetime stats: what the pet card shows off, and what levels Gob up and unlocks hats.
public struct MascotStats: Codable, Equatable, Sendable {
    public var filesGobbled = 0
    public var burps = 0
    public var pets = 0
    public var xp = 0
    /// Times music started while Gob was watching.
    public var songs = 0
    /// Claude Code / Codex turns Gob saw finish.
    public var agentTasks = 0
    /// Consecutive days with Gobbl in use, and the best run.
    public var streak = 0
    public var longestStreak = 0
    /// "yyyy-MM-dd" of the last active day.
    public var lastActiveDay: String?
    /// Hats unlocked so far (Hat raw values); seasonal ones stay once earned.
    public var collected: [String] = []
    public var hatched: Date?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case filesGobbled, burps, pets, xp, songs, agentTasks, streak, longestStreak, lastActiveDay, collected, hatched
    }

    /// Tolerates missing keys so stats saved by older versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filesGobbled = try c.decodeIfPresent(Int.self, forKey: .filesGobbled) ?? 0
        burps = try c.decodeIfPresent(Int.self, forKey: .burps) ?? 0
        pets = try c.decodeIfPresent(Int.self, forKey: .pets) ?? 0
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        songs = try c.decodeIfPresent(Int.self, forKey: .songs) ?? 0
        agentTasks = try c.decodeIfPresent(Int.self, forKey: .agentTasks) ?? 0
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        longestStreak = try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        lastActiveDay = try c.decodeIfPresent(String.self, forKey: .lastActiveDay)
        collected = try c.decodeIfPresent([String].self, forKey: .collected) ?? []
        hatched = try c.decodeIfPresent(Date.self, forKey: .hatched)
    }

    /// 1 at 0 XP, 2 at 10, 3 at 40, 4 at 90… (level n starts at 10·(n−1)² XP).
    public var level: Int { Int((Double(xp) / 10).squareRoot()) + 1 }

    /// Evolution stage: baby, teen, grown-up.
    public var stage: Int { level < 5 ? 0 : (level < 12 ? 1 : 2) }

    /// Progress towards the next level, 0–1.
    public var levelProgress: Double {
        let lo = 10 * (level - 1) * (level - 1), hi = 10 * level * level
        return Double(xp - lo) / Double(hi - lo)
    }

    /// Counts `date`'s day towards the streak. Returns true the first time each day.
    @discardableResult
    public mutating func recordActiveDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let today = Self.dayString(date, calendar)
        guard lastActiveDay != today else { return false }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))
        if let last = lastActiveDay, let yesterday, last == Self.dayString(yesterday, calendar) {
            streak += 1
        } else {
            streak = 1
        }
        longestStreak = max(longestStreak, streak)
        lastActiveDay = today
        return true
    }

    static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Gob's state machine. A value type with an explicit clock so it can be
/// unit-tested; the app feeds it signals and asks for the mood to draw.
///
/// Priority: a live reaction beats working (an agent is busy), which beats
/// sleeping, dancing, sweaty, sleepy, then curious. Gob never dies and never
/// nags: needs only change how it looks.
public struct MascotBrain: Equatable, Sendable {
    public static let sleepAfter: TimeInterval = 600
    public static let lowBattery = 0.15
    public static let hotCPU = 0.85
    public static let milestones = [10, 50, 100, 250, 500, 1000, 2500, 5000, 10000]

    public var stats: MascotStats
    /// Quiet mode: no playful reactions or dancing; direct actions still register.
    public var quiet = false

    public private(set) var musicPlaying = false
    public private(set) var batteryLow = false
    public private(set) var idleSeconds: TimeInterval = 0
    public private(set) var cursorNear = false
    public private(set) var cpuHot = false
    public private(set) var agentsBusy = false
    public private(set) var reaction: Mood?
    public private(set) var reactionUntil = Date.distantPast

    public init(stats: MascotStats = MascotStats()) {
        self.stats = stats
    }

    /// The files-gobbled milestone crossed going from `old` to `new`, if any.
    public static func milestone(from old: Int, to new: Int) -> Int? {
        milestones.last { old < $0 && new >= $0 }
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
        case .welcomeBack:
            idleSeconds = 0
            react(.happy, for: 1.8, now: now, playful: true)
        case .milestone:
            react(.celebrating, for: 3, now: now)
        case .agentDone:
            stats.agentTasks += 1
            stats.xp += 2
            react(.celebrating, for: 2.5, now: now)
        case .agentNeedsInput:
            react(.alert, for: 6, now: now)
        case .musicPlaying(let on):
            if on && !musicPlaying {
                stats.songs += 1
                stats.xp += 1
            }
            musicPlaying = on
        case .battery(let level, let charging):
            batteryLow = level < Self.lowBattery && !charging
        case .userIdle(let seconds):
            idleSeconds = max(0, seconds)
        case .cursorNear(let near):
            cursorNear = near
        case .cpuLoad(let load):
            cpuHot = load >= Self.hotCPU
        case .agentsWorking(let busy):
            agentsBusy = busy
        }
        guard stats.level > before else { return false }
        react(.celebrating, for: 3, now: now)
        return true
    }

    public func mood(at now: Date = Date()) -> Mood {
        if let reaction, now < reactionUntil { return reaction }
        if agentsBusy { return .working }
        if idleSeconds >= Self.sleepAfter { return .sleeping }
        if musicPlaying && !quiet { return .dancing }
        if cpuHot { return .sweaty }
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
