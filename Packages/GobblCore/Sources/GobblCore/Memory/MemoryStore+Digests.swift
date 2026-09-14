import Foundation
import SQLite3

/// A stretch of time in one window, summarised for the day digest.
public struct SegmentSummary: Equatable, Identifiable, Sendable {
    public var id: Int64
    public var app: String
    public var appBundle: String
    public var window: String
    public var chat: String?
    public var domain: String?
    public var started: Date
    public var ended: Date
    public var chunks: Int
    /// The start of what was captured there (already redacted), for the AI.
    public var excerpt: String

    public var minutes: Double { max(1, ended.timeIntervalSince(started) / 60) }
}

/// One part of one day, as the AI summarised it: at most three outcome bullets.
public struct DayDigest: Equatable, Sendable {
    public var day: String
    public var part: String
    public var bullets: [String]
    public var apps: [String]
    public var created: Date

    public init(day: String, part: String, bullets: [String], apps: [String], created: Date) {
        self.day = day
        self.part = part
        self.bullets = bullets
        self.apps = apps
        self.created = created
    }
}

/// A day runs 5 am to 5 am, so a late night belongs to the day it started.
public enum DayParts {
    public static let order = ["morning", "afternoon", "evening"]

    public static func part(of date: Date, calendar: Calendar) -> String {
        let h = calendar.component(.hour, from: date)
        if (5..<12).contains(h) { return "morning" }
        if (12..<17).contains(h) { return "afternoon" }
        return "evening"
    }

    /// "2026-09-14" for anything from 05:00 that day until 05:00 the next.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let shifted = calendar.component(.hour, from: date) < 5 ? date.addingTimeInterval(-86400) : date
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func range(of day: String, calendar: Calendar) -> (start: Date, end: Date)? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 5)),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }
}

extension MemoryStore {
    func migrateDigests() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS digests(
          day TEXT NOT NULL, part TEXT NOT NULL, bullets TEXT NOT NULL, apps TEXT NOT NULL, created REAL NOT NULL,
          PRIMARY KEY(day, part));
        PRAGMA user_version=4;
        """)
    }

    /// Windows used between `from` and `to`, oldest first, with a short excerpt each.
    public func segments(from: Date, to: Date, excerptChars: Int = 300, limit: Int = 400) throws -> [SegmentSummary] {
        try locked {
            try rows("""
            SELECT s.id, s.app_name, s.app_bundle, s.window, s.chat, s.url_domain, s.started, s.ended, count(c.id),
                   substr(group_concat(c.text, ' / '), 1, ?)
            FROM segments s JOIN chunks c ON c.segment_id = s.id
            WHERE s.started < ? AND s.ended >= ?
            GROUP BY s.id ORDER BY s.started LIMIT ?
            """, [excerptChars, to.timeIntervalSince1970, from.timeIntervalSince1970, limit]) { s in
                SegmentSummary(id: sqlite3_column_int64(s, 0), app: Self.text(s, 1) ?? "", appBundle: Self.text(s, 2) ?? "",
                               window: Self.text(s, 3) ?? "", chat: Self.text(s, 4), domain: Self.text(s, 5),
                               started: Date(timeIntervalSince1970: sqlite3_column_double(s, 6)),
                               ended: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)),
                               chunks: Int(sqlite3_column_int(s, 8)), excerpt: Self.text(s, 9) ?? "")
            }
        }
    }

    public func upsertDigest(_ d: DayDigest) throws {
        let bullets = String(decoding: try JSONEncoder().encode(d.bullets), as: UTF8.self)
        let apps = String(decoding: try JSONEncoder().encode(d.apps), as: UTF8.self)
        try locked {
            try run("INSERT OR REPLACE INTO digests(day, part, bullets, apps, created) VALUES (?,?,?,?,?)",
                    [d.day, d.part, bullets, apps, d.created.timeIntervalSince1970])
        }
    }

    /// Newest day first; within a day, morning → evening.
    public func digests(sinceDay: String) throws -> [DayDigest] {
        try locked {
            try rows("""
            SELECT day, part, bullets, apps, created FROM digests WHERE day >= ?
            ORDER BY day DESC, CASE part WHEN 'morning' THEN 0 WHEN 'afternoon' THEN 1 ELSE 2 END
            """, [sinceDay]) { s in
                DayDigest(day: Self.text(s, 0) ?? "", part: Self.text(s, 1) ?? "",
                          bullets: (try? JSONDecoder().decode([String].self, from: Data((Self.text(s, 2) ?? "[]").utf8))) ?? [],
                          apps: (try? JSONDecoder().decode([String].self, from: Data((Self.text(s, 3) ?? "[]").utf8))) ?? [],
                          created: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)))
            }
        }
    }

    public func hasDigest(day: String) -> Bool {
        ((try? locked { try rows("SELECT 1 FROM digests WHERE day = ? LIMIT 1", [day]) { _ in true } }) ?? []).isEmpty == false
    }

    /// One block from the timeline, gone ("forget this").
    public func forget(segment id: Int64) throws {
        try locked {
            try run("DELETE FROM chunks WHERE segment_id = ?", [id])
            try run("DELETE FROM segments WHERE id = ?", [id])
            try exec("DELETE FROM vectors WHERE kind = 'chunk' AND ref NOT IN (SELECT id FROM chunks)")
            vectorCache.invalidate()
            try exec("PRAGMA incremental_vacuum")
        }
    }
}
