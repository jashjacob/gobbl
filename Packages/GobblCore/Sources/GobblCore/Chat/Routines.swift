import Foundation

public enum BriefKind: String, Codable, CaseIterable, Sendable {
    case morning, evening

    public var title: String { self == .morning ? "Morning brief" : "Evening wrap" }
}

public enum BriefSchedule {
    /// Due once a day, from its time until four hours after, so a Mac opened
    /// late at night doesn't get a stale morning brief.
    public static func isDue(minuteOfDay: Int, lastRun: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let at = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: now),
              now >= at, now < at.addingTimeInterval(4 * 3600) else { return false }
        if let lastRun, lastRun >= at { return false }
        return true
    }
}

/// Keeps nudges rare: at most a few a day, each thing once, never in quiet
/// mode, during focus, or outside waking hours.
public struct NudgePolicy: Codable, Equatable, Sendable {
    public var maxPerDay = 3
    public var activeHours = 8..<21
    public private(set) var day = ""
    public private(set) var count = 0
    public private(set) var sent: Set<String> = []

    public init() {}

    public func canNudge(_ key: String, now: Date, quiet: Bool, focusing: Bool, calendar: Calendar) -> Bool {
        guard !quiet, !focusing, activeHours.contains(calendar.component(.hour, from: now)) else { return false }
        guard Self.dayKey(now, calendar) == day else { return true }
        return count < maxPerDay && !sent.contains(key)
    }

    public mutating func record(_ key: String, now: Date, calendar: Calendar) {
        let today = Self.dayKey(now, calendar)
        if today != day {
            day = today
            count = 0
            sent = []
        }
        count += 1
        sent.insert(key)
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
