import Foundation
import SQLite3

/// One stretch of time in one window, with a short excerpt of what was on screen.
public struct MemoryActivity: Equatable, Sendable {
    public var app: String
    public var window: String
    public var chat: String?
    public var domain: String?
    public var started: Date
    public var ended: Date
    public var excerpt: String
}

public struct MemoryDigestPart: Equatable, Sendable {
    public var part: String
    public var bullets: [String]
    public var apps: [String]
}

/// Read-only queries for gobbl-mcp.
extension MemoryStore {
    /// Full-text search narrowed by app, person and time.
    public func filteredSearch(_ query: String, app: String? = nil, person: String? = nil, since: Date? = nil, until: Date? = nil,
                               limit: Int = 10) throws -> [Hit] {
        let fts = Self.ftsQuery(query)
        guard !fts.isEmpty else { return [] }
        return try locked {
            var sql = """
            SELECT c.id, c.segment_id, s.app_name, s.window, s.chat, s.url_domain, c.sender, c.from_me, c.ts,
                   snippet(chunks_fts, 0, '[', ']', '…', 24)
            FROM chunks_fts JOIN chunks c ON c.id = chunks_fts.rowid JOIN segments s ON s.id = c.segment_id
            WHERE chunks_fts MATCH ?
            """
            var args: [Any?] = [fts]
            if let app {
                sql += " AND (s.app_name LIKE ? OR s.app_bundle LIKE ?)"
                args += ["%\(app)%", "%\(app)%"]
            }
            if let person {
                sql += " AND (c.sender LIKE ? OR s.chat LIKE ?)"
                args += ["%\(person)%", "%\(person)%"]
            }
            if let since {
                sql += " AND c.ts >= ?"
                args.append(since.timeIntervalSince1970)
            }
            if let until {
                sql += " AND c.ts < ?"
                args.append(until.timeIntervalSince1970)
            }
            sql += " ORDER BY bm25(chunks_fts) + (? - c.ts) / 2592000.0 LIMIT ?"
            args += [Date().timeIntervalSince1970, limit]
            return try rows(sql, args) { s in
                Hit(chunkID: sqlite3_column_int64(s, 0), segmentID: sqlite3_column_int64(s, 1), app: Self.text(s, 2) ?? "",
                    window: Self.text(s, 3) ?? "", chat: Self.text(s, 4), domain: Self.text(s, 5), sender: Self.text(s, 6),
                    fromMe: sqlite3_column_int(s, 7) != 0, ts: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)),
                    snippet: Self.text(s, 9) ?? "")
            }
        }
    }

    public func hasTable(_ name: String) -> Bool {
        let found = try? locked { try rows("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [name]) { _ in true } }
        return found?.isEmpty == false
    }

    /// The day's summaries, morning → evening; empty when there are none (or no digests table yet).
    public func digestParts(day: String) throws -> [MemoryDigestPart] {
        guard hasTable("digests") else { return [] }
        return try locked {
            try rows("""
            SELECT part, bullets, apps FROM digests WHERE day = ?
            ORDER BY CASE part WHEN 'morning' THEN 0 WHEN 'afternoon' THEN 1 ELSE 2 END
            """, [day]) { s in
                MemoryDigestPart(part: Self.text(s, 0) ?? "",
                                 bullets: (try? JSONDecoder().decode([String].self, from: Data((Self.text(s, 1) ?? "[]").utf8))) ?? [],
                                 apps: (try? JSONDecoder().decode([String].self, from: Data((Self.text(s, 2) ?? "[]").utf8))) ?? [])
            }
        }
    }

    /// Windows used between `from` and `to`, oldest first.
    public func activity(from: Date, to: Date, excerptChars: Int = 240, limit: Int = 400) throws -> [MemoryActivity] {
        try locked {
            try rows("""
            SELECT s.app_name, s.window, s.chat, s.url_domain, s.started, s.ended, substr(group_concat(c.text, ' / '), 1, ?)
            FROM segments s JOIN chunks c ON c.segment_id = s.id
            WHERE s.started < ? AND s.ended >= ?
            GROUP BY s.id ORDER BY s.started LIMIT ?
            """, [excerptChars, to.timeIntervalSince1970, from.timeIntervalSince1970, limit]) { s in
                MemoryActivity(app: Self.text(s, 0) ?? "", window: Self.text(s, 1) ?? "", chat: Self.text(s, 2), domain: Self.text(s, 3),
                               started: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
                               ended: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)), excerpt: Self.text(s, 6) ?? "")
            }
        }
    }
}
