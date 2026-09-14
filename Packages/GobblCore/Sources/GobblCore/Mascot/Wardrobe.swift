import Foundation

/// Hats Gob can wear. Each is earned by doing something (a streak, a level,
/// petting) or by being around during its season; once earned it stays.
public enum Hat: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, party, bow, beanie, headphones, sunglasses, halo, crown, flower, pumpkin, diya, santa

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "No hat"
        case .party: "Party hat"
        case .bow: "Bow"
        case .beanie: "Beanie"
        case .headphones: "Headphones"
        case .sunglasses: "Sunglasses"
        case .halo: "Halo"
        case .crown: "Crown"
        case .flower: "Spring flower"
        case .pumpkin: "Pumpkin"
        case .diya: "Diya"
        case .santa: "Santa hat"
        }
    }

    /// How to earn it, shown on locked hats.
    public var requirement: String {
        switch self {
        case .none: ""
        case .party: "Reach level 2"
        case .bow: "Pet Gob 25 times"
        case .beanie: "3-day streak"
        case .headphones: "Play music 10 times"
        case .sunglasses: "7-day streak"
        case .halo: "Watch 10 AI agent tasks finish"
        case .crown: "Reach level 12"
        case .flower: "Spring (March to May)"
        case .pumpkin: "Halloween season (October)"
        case .diya: "Diwali season (mid-October to November)"
        case .santa: "December holidays"
        }
    }

    public var isSeasonal: Bool { [.flower, .pumpkin, .diya, .santa].contains(self) }

    public func isUnlocked(stats: MascotStats, date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        let md = (c.month ?? 0) * 100 + (c.day ?? 0) // 1015 = Oct 15
        switch self {
        case .none: return true
        case .party: return stats.level >= 2
        case .bow: return stats.pets >= 25
        case .beanie: return stats.longestStreak >= 3
        case .headphones: return stats.songs >= 10
        case .sunglasses: return stats.longestStreak >= 7
        case .halo: return stats.agentTasks >= 10
        case .crown: return stats.level >= 12
        case .flower: return (301...531).contains(md)
        case .pumpkin: return (1001...1102).contains(md)
        case .diya: return (1015...1120).contains(md)
        case .santa: return md >= 1201 || md <= 106
        }
    }
}

public enum Wardrobe {
    /// Hats Gob owns: every collected hat plus anything unlocked right now.
    public static func owned(stats: MascotStats, date: Date, calendar: Calendar = .current) -> [Hat] {
        Hat.allCases.filter { $0 == .none || stats.collected.contains($0.rawValue) || $0.isUnlocked(stats: stats, date: date, calendar: calendar) }
    }

    /// Hats unlocked now that haven't been collected yet.
    public static func newlyUnlocked(stats: MascotStats, date: Date, calendar: Calendar = .current) -> [Hat] {
        Hat.allCases.filter { $0 != .none && !stats.collected.contains($0.rawValue) && $0.isUnlocked(stats: stats, date: date, calendar: calendar) }
    }
}
