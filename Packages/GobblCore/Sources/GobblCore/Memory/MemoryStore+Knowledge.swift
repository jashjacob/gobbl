import Foundation
import SQLite3

/// People, projects, organisations, topics and tools, built from captured
/// chats and the AI's extractions. Every fact keeps the snippet it came from.
extension MemoryStore {
    func migrateKnowledge() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS entities(
          id INTEGER PRIMARY KEY, type TEXT NOT NULL, name TEXT NOT NULL, role TEXT, org TEXT, description TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '', pinned INTEGER NOT NULL DEFAULT 0, hidden INTEGER NOT NULL DEFAULT 0,
          forgotten INTEGER NOT NULL DEFAULT 0, first_seen REAL NOT NULL, last_seen REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS entities_type ON entities(type, last_seen);
        CREATE TABLE IF NOT EXISTS aliases(
          entity_id INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE, alias TEXT NOT NULL, norm TEXT NOT NULL, scope TEXT,
          PRIMARY KEY(entity_id, norm));
        CREATE INDEX IF NOT EXISTS aliases_norm ON aliases(norm);
        CREATE TABLE IF NOT EXISTS identifiers(
          entity_id INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE, type TEXT NOT NULL, value TEXT NOT NULL,
          PRIMARY KEY(type, value));
        CREATE TABLE IF NOT EXISTS mentions(
          entity_id INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE, chunk_id INTEGER NOT NULL, role TEXT NOT NULL,
          ts REAL NOT NULL, app TEXT NOT NULL DEFAULT '', PRIMARY KEY(entity_id, chunk_id, role));
        CREATE INDEX IF NOT EXISTS mentions_ts ON mentions(entity_id, ts);
        CREATE TABLE IF NOT EXISTS relations(
          a INTEGER NOT NULL, b INTEGER NOT NULL, kind TEXT NOT NULL, weight REAL NOT NULL DEFAULT 1, evidence INTEGER,
          PRIMARY KEY(a, b, kind));
        CREATE TABLE IF NOT EXISTS facts(
          entity_id INTEGER NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, evidence INTEGER, confidence REAL NOT NULL DEFAULT 0.7,
          PRIMARY KEY(entity_id, key, value));
        CREATE TABLE IF NOT EXISTS merge_suggestions(
          a INTEGER NOT NULL, b INTEGER NOT NULL, reason TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open', PRIMARY KEY(a, b));
        CREATE TABLE IF NOT EXISTS merge_log(id INTEGER PRIMARY KEY, at REAL NOT NULL, kept INTEGER NOT NULL, snapshot TEXT NOT NULL);
        PRAGMA user_version=3;
        """)
    }

    // MARK: Building

    /// Finds or creates an entity. Merges automatically only on a shared
    /// identifier or the exact same name; near-misses become suggestions.
    /// Returns nil for noise names and for people the user asked to forget.
    @discardableResult
    public func upsertEntity(type: EntityType, name: String, aliases: [String] = [], identifiers: [(type: String, value: String)] = [],
                             role: String? = nil, org: String? = nil, scope: String? = nil, at: Date) throws -> Int64? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !EntityRules.isNoise(clean) else { return nil }
        let norm = EntityRules.normalize(clean)
        return try locked {
            var id: Int64?
            for ident in identifiers where !ident.value.isEmpty {
                id = try rows("SELECT entity_id FROM identifiers WHERE type = ? AND value = ?",
                              [ident.type, ident.value.lowercased()]) { sqlite3_column_int64($0, 0) }.first
                if id != nil { break }
            }
            if id == nil {
                id = try rows("""
                SELECT e.id FROM entities e JOIN aliases a ON a.entity_id = e.id WHERE e.type = ? AND a.norm = ?
                ORDER BY e.last_seen DESC LIMIT 1
                """, [type.rawValue, norm]) { sqlite3_column_int64($0, 0) }.first
            }
            let isNew = id == nil
            if id == nil {
                try run("INSERT INTO entities(type, name, role, org, first_seen, last_seen) VALUES (?,?,?,?,?,?)",
                        [type.rawValue, clean, role, org, at.timeIntervalSince1970, at.timeIntervalSince1970])
                id = sqlite3_last_insert_rowid(db)
            }
            guard let entity = id else { return nil }
            let forgotten = try rows("SELECT forgotten FROM entities WHERE id = ?", [entity]) { sqlite3_column_int($0, 0) }.first ?? 0
            if forgotten != 0 { return nil }

            for alias in [clean] + aliases where !EntityRules.isNoise(alias) {
                try run("INSERT OR IGNORE INTO aliases(entity_id, alias, norm, scope) VALUES (?,?,?,?)",
                        [entity, alias, EntityRules.normalize(alias), scope])
            }
            for ident in identifiers where !ident.value.isEmpty {
                try run("INSERT OR IGNORE INTO identifiers(entity_id, type, value) VALUES (?,?,?)", [entity, ident.type, ident.value.lowercased()])
            }
            // Role and org only fill gaps; a user edit ("locked") is never overwritten.
            try run("UPDATE entities SET role = coalesce(role, ?), org = coalesce(org, ?), last_seen = max(last_seen, ?) WHERE id = ?",
                    [role, org, at.timeIntervalSince1970, entity])
            // Longer, fuller names win as the display name ("Samar" → "Samar Mustafa").
            try run("UPDATE entities SET name = ? WHERE id = ? AND length(name) < length(?)", [clean, entity, clean])

            if isNew {
                let others = try rows("SELECT id, name FROM entities WHERE type = ? AND id != ? AND forgotten = 0 ORDER BY last_seen DESC LIMIT 2000",
                                      [type.rawValue, entity]) { (sqlite3_column_int64($0, 0), Self.text($0, 1) ?? "") }
                for (other, otherName) in others {
                    guard let reason = EntityRules.mightBeSame(clean, otherName) else { continue }
                    let (a, b) = entity < other ? (entity, other) : (other, entity)
                    try run("INSERT OR IGNORE INTO merge_suggestions(a, b, reason) VALUES (?,?,?)", [a, b, reason])
                }
            }
            return entity
        }
    }

    public func addMention(entity: Int64, chunk: Int64, role: String, at: Date, app: String) throws {
        try locked {
            try run("INSERT OR IGNORE INTO mentions(entity_id, chunk_id, role, ts, app) VALUES (?,?,?,?,?)",
                    [entity, chunk, role, at.timeIntervalSince1970, app])
            try run("UPDATE entities SET last_seen = max(last_seen, ?) WHERE id = ?", [at.timeIntervalSince1970, entity])
        }
    }

    public func addRelation(_ a: Int64, _ b: Int64, kind: String, evidence: Int64?) throws {
        guard a != b else { return }
        try locked {
            try run("""
            INSERT INTO relations(a, b, kind, weight, evidence) VALUES (?,?,?,1,?)
            ON CONFLICT(a, b, kind) DO UPDATE SET weight = weight + 1, evidence = coalesce(excluded.evidence, evidence)
            """, [a, b, kind, evidence])
        }
    }

    public func addFact(entity: Int64, key: String, value: String, evidence: Int64?, confidence: Double) throws {
        try locked {
            try run("INSERT OR IGNORE INTO facts(entity_id, key, value, evidence, confidence) VALUES (?,?,?,?,?)",
                    [entity, key, value, evidence, confidence])
        }
    }

    // MARK: Reading

    private static let summarySelect = """
    SELECT e.id, e.type, e.name, e.role, e.org, e.last_seen, e.pinned,
      (SELECT count(*) FROM mentions m WHERE m.entity_id = e.id AND m.ts > ?) AS recent,
      (SELECT group_concat(app, '|') FROM (SELECT DISTINCT app FROM mentions m WHERE m.entity_id = e.id AND app != '' LIMIT 6)) AS apps
    FROM entities e
    """

    private static func summary(_ s: OpaquePointer?) -> EntitySummary {
        EntitySummary(id: sqlite3_column_int64(s, 0), type: EntityType(rawValue: text(s, 1) ?? "") ?? .topic, name: text(s, 2) ?? "",
                      role: text(s, 3), org: text(s, 4),
                      lastSeen: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 5)),
                      mentions30d: Int(sqlite3_column_int(s, 7)), apps: (text(s, 8) ?? "").split(separator: "|").map(String.init),
                      pinned: sqlite3_column_int(s, 6) != 0)
    }

    /// People (or projects…), pinned first, then most active recently. People seen only once in 30 days are hidden unless `everyone`.
    public func entities(_ type: EntityType, matching query: String = "", everyone: Bool = false, limit: Int = 200) throws -> [EntitySummary] {
        let since = Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
        return try locked {
            var sql = Self.summarySelect + " WHERE e.type = ? AND e.forgotten = 0 AND e.hidden = 0"
            var args: [Any?] = [since, type.rawValue]
            let norm = EntityRules.normalize(query)
            if !norm.isEmpty {
                sql += " AND e.id IN (SELECT entity_id FROM aliases WHERE norm LIKE ?)"
                args.append("%\(norm)%")
            }
            sql += " ORDER BY e.pinned DESC, recent DESC, e.last_seen DESC LIMIT ?"
            args.append(limit)
            let all = try rows(sql, args, Self.summary)
            return everyone || !norm.isEmpty ? all : all.filter { $0.pinned || $0.mentions30d >= 2 || $0.role != nil }
        }
    }

    /// Best match for a name the user typed or said ("who is Samar").
    public func findEntity(named name: String, type: EntityType? = nil) throws -> EntitySummary? {
        let norm = EntityRules.normalize(name)
        guard !norm.isEmpty else { return nil }
        let since = Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
        return try locked {
            var sql = Self.summarySelect + " JOIN aliases a ON a.entity_id = e.id WHERE e.forgotten = 0 AND (a.norm = ? OR a.norm LIKE ?)"
            var args: [Any?] = [since, norm, "\(norm) %"]
            if let type {
                sql += " AND e.type = ?"
                args.append(type.rawValue)
            }
            sql += " GROUP BY e.id ORDER BY (a.norm = ?) DESC, e.last_seen DESC LIMIT 1"
            args.append(norm)
            return try rows(sql, args, Self.summary).first
        }
    }

    public func entityDetail(_ id: Int64) throws -> EntityDetail? {
        let since = Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
        return try locked {
            guard let summary = try rows(Self.summarySelect + " WHERE e.id = ?", [since, id], Self.summary).first else { return nil }
            let aliases = try rows("SELECT alias FROM aliases WHERE entity_id = ? ORDER BY length(alias) DESC", [id]) { Self.text($0, 0) ?? "" }
            let identifiers = try rows("SELECT type, value FROM identifiers WHERE entity_id = ?", [id]) { (Self.text($0, 0) ?? "", Self.text($0, 1) ?? "") }
            let facts = try rows("SELECT key, value FROM facts WHERE entity_id = ? ORDER BY confidence DESC LIMIT 20", [id]) { (Self.text($0, 0) ?? "", Self.text($0, 1) ?? "") }
            let relatedIDs = try rows("""
            SELECT CASE WHEN a = ? THEN b ELSE a END AS other, kind FROM relations WHERE a = ? OR b = ? ORDER BY weight DESC LIMIT 30
            """, [id, id, id]) { (sqlite3_column_int64($0, 0), Self.text($0, 1) ?? "") }
            var related: [(entity: EntitySummary, kind: String)] = []
            for (other, kind) in relatedIDs {
                if let s = try rows(Self.summarySelect + " WHERE e.id = ? AND e.forgotten = 0", [since, other], Self.summary).first {
                    related.append((s, kind))
                }
            }
            let recent = try rows("""
            SELECT c.id, c.segment_id, s.app_name, s.app_bundle, s.window, s.chat, s.url_domain, c.sender, c.from_me, c.ts, c.text
            FROM mentions m JOIN chunks c ON c.id = m.chunk_id JOIN segments s ON s.id = c.segment_id
            WHERE m.entity_id = ? GROUP BY c.id ORDER BY c.ts DESC LIMIT 12
            """, [id], Self.hit)
            let extra = try rows("SELECT notes, description FROM entities WHERE id = ?", [id]) { (Self.text($0, 0) ?? "", Self.text($0, 1) ?? "") }.first ?? ("", "")
            return EntityDetail(summary: summary, aliases: aliases, identifiers: identifiers, facts: facts, related: related,
                                recent: recent, notes: extra.0, description: extra.1)
        }
    }

    public func mergeSuggestions(limit: Int = 20) throws -> [MergeSuggestion] {
        let since = Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970
        return try locked {
            let pairs = try rows("SELECT a, b, reason FROM merge_suggestions WHERE status = 'open' LIMIT ?", [limit]) {
                (sqlite3_column_int64($0, 0), sqlite3_column_int64($0, 1), Self.text($0, 2) ?? "")
            }
            return try pairs.compactMap { a, b, reason in
                guard let x = try rows(Self.summarySelect + " WHERE e.id = ? AND e.forgotten = 0", [since, a], Self.summary).first,
                      let y = try rows(Self.summarySelect + " WHERE e.id = ? AND e.forgotten = 0", [since, b], Self.summary).first else { return nil }
                return MergeSuggestion(a: x, b: y, reason: reason)
            }
        }
    }

    // MARK: Editing

    public func updateEntity(_ id: Int64, name: String? = nil, role: String? = nil, org: String? = nil, notes: String? = nil,
                             pinned: Bool? = nil, hidden: Bool? = nil) throws {
        try locked {
            if let name { try run("UPDATE entities SET name = ? WHERE id = ?", [name, id]) }
            if let role { try run("UPDATE entities SET role = ? WHERE id = ?", [role.isEmpty ? nil : role, id]) }
            if let org { try run("UPDATE entities SET org = ? WHERE id = ?", [org.isEmpty ? nil : org, id]) }
            if let notes { try run("UPDATE entities SET notes = ? WHERE id = ?", [notes, id]) }
            if let pinned { try run("UPDATE entities SET pinned = ? WHERE id = ?", [pinned ? 1 : 0, id]) }
            if let hidden { try run("UPDATE entities SET hidden = ? WHERE id = ?", [hidden ? 1 : 0, id]) }
        }
    }

    /// "Not the same person": never suggested again.
    public func rejectMerge(_ a: Int64, _ b: Int64) throws {
        try locked { try run("UPDATE merge_suggestions SET status = 'rejected' WHERE a = ? AND b = ?", [min(a, b), max(a, b)]) }
    }

    /// Folds `remove` into `keep`. Returns a log id for Undo.
    @discardableResult
    public func merge(keep: Int64, remove: Int64) throws -> Int64 {
        try locked {
            let snapshot: [String: Any] = [
                "entity": try rows("SELECT id, type, name, role, org, description, notes, pinned, hidden, first_seen, last_seen FROM entities WHERE id = ?", [remove]) { s in
                    (0..<11).map { i -> Any in sqlite3_column_type(s, Int32(i)) == SQLITE_NULL ? NSNull() : (Self.text(s, Int32(i)) ?? "") }
                }.first ?? [],
                "aliases": try rows("SELECT alias, norm, coalesce(scope, '') FROM aliases WHERE entity_id = ?", [remove]) { [Self.text($0, 0) ?? "", Self.text($0, 1) ?? "", Self.text($0, 2) ?? ""] },
                "identifiers": try rows("SELECT type, value FROM identifiers WHERE entity_id = ?", [remove]) { [Self.text($0, 0) ?? "", Self.text($0, 1) ?? ""] },
                "mentions": try rows("SELECT chunk_id, role FROM mentions WHERE entity_id = ?", [remove]) { [String(sqlite3_column_int64($0, 0)), Self.text($0, 1) ?? ""] },
            ]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: snapshot), as: UTF8.self)
            try exec("BEGIN")
            do {
                try run("INSERT INTO merge_log(at, kept, snapshot) VALUES (?,?,?)", [Date().timeIntervalSince1970, keep, json])
                let logID = sqlite3_last_insert_rowid(db)
                try run("UPDATE OR IGNORE aliases SET entity_id = ? WHERE entity_id = ?", [keep, remove])
                try run("UPDATE OR IGNORE identifiers SET entity_id = ? WHERE entity_id = ?", [keep, remove])
                try run("UPDATE OR IGNORE mentions SET entity_id = ? WHERE entity_id = ?", [keep, remove])
                try run("UPDATE OR IGNORE facts SET entity_id = ? WHERE entity_id = ?", [keep, remove])
                try run("UPDATE OR IGNORE relations SET a = ? WHERE a = ?", [keep, remove])
                try run("UPDATE OR IGNORE relations SET b = ? WHERE b = ?", [keep, remove])
                try run("DELETE FROM relations WHERE a = b", [])
                try run("UPDATE entities SET name = CASE WHEN length((SELECT name FROM entities WHERE id = ?)) > length(name) THEN (SELECT name FROM entities WHERE id = ?) ELSE name END, role = coalesce(role, (SELECT role FROM entities WHERE id = ?)), org = coalesce(org, (SELECT org FROM entities WHERE id = ?)), first_seen = min(first_seen, (SELECT first_seen FROM entities WHERE id = ?)), last_seen = max(last_seen, (SELECT last_seen FROM entities WHERE id = ?)) WHERE id = ?",
                        [remove, remove, remove, remove, remove, remove, keep])
                try run("DELETE FROM entities WHERE id = ?", [remove])
                try run("UPDATE merge_suggestions SET status = 'merged' WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)", [min(keep, remove), max(keep, remove), min(keep, remove), max(keep, remove)])
                try exec("COMMIT")
                return logID
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    /// Splits a merged entity back out, with its aliases, identifiers and mentions.
    public func undoMerge(_ logID: Int64) throws {
        try locked {
            guard let row = try rows("SELECT kept, snapshot FROM merge_log WHERE id = ?", [logID], { (sqlite3_column_int64($0, 0), Self.text($0, 1) ?? "{}") }).first,
                  let snapshot = try JSONSerialization.jsonObject(with: Data(row.1.utf8)) as? [String: Any],
                  let e = snapshot["entity"] as? [Any], e.count == 11 else { return }
            let kept = row.0
            func s(_ i: Int) -> Any? { e[i] is NSNull ? nil : e[i] }
            try exec("BEGIN")
            do {
                try run("INSERT INTO entities(id, type, name, role, org, description, notes, pinned, hidden, first_seen, last_seen) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                        [Int64((s(0) as? String) ?? "") ?? 0, s(1), s(2), s(3), s(4), s(5) ?? "", s(6) ?? "", Int((s(7) as? String) ?? "0") ?? 0,
                         Int((s(8) as? String) ?? "0") ?? 0, Double((s(9) as? String) ?? "0") ?? 0, Double((s(10) as? String) ?? "0") ?? 0])
                let removed = sqlite3_last_insert_rowid(db)
                for a in snapshot["aliases"] as? [[String]] ?? [] where a.count == 3 {
                    try run("DELETE FROM aliases WHERE entity_id = ? AND norm = ?", [kept, a[1]])
                    try run("INSERT OR IGNORE INTO aliases(entity_id, alias, norm, scope) VALUES (?,?,?,?)", [removed, a[0], a[1], a[2].isEmpty ? nil : a[2]])
                }
                for i in snapshot["identifiers"] as? [[String]] ?? [] where i.count == 2 {
                    try run("UPDATE identifiers SET entity_id = ? WHERE type = ? AND value = ?", [removed, i[0], i[1]])
                }
                for m in snapshot["mentions"] as? [[String]] ?? [] where m.count == 2 {
                    try run("UPDATE OR IGNORE mentions SET entity_id = ? WHERE entity_id = ? AND chunk_id = ? AND role = ?", [removed, kept, Int64(m[0]) ?? 0, m[1]])
                }
                try run("UPDATE merge_suggestions SET status = 'rejected' WHERE a = ? AND b = ?", [min(kept, removed), max(kept, removed)])
                try run("DELETE FROM merge_log WHERE id = ?", [logID])
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    /// "Forget and never remember this person": everything about them goes;
    /// only their names stay, marked, so they aren't picked up again.
    public func forgetEntity(_ id: Int64) throws {
        try locked {
            try run("DELETE FROM mentions WHERE entity_id = ?", [id])
            try run("DELETE FROM facts WHERE entity_id = ?", [id])
            try run("DELETE FROM relations WHERE a = ? OR b = ?", [id, id])
            try run("DELETE FROM identifiers WHERE entity_id = ?", [id])
            try run("UPDATE entities SET forgotten = 1, role = NULL, org = NULL, notes = '', description = '' WHERE id = ?", [id])
        }
    }

    /// Entries the knowledge base hasn't processed yet (the AI's extractions).
    public func takeEntityInbox(limit: Int = 50) throws -> [(id: Int64, json: String)] {
        try locked { try rows("SELECT id, data FROM entity_inbox ORDER BY id LIMIT ?", [limit]) { (sqlite3_column_int64($0, 0), Self.text($0, 1) ?? "{}") } }
    }

    public func removeFromEntityInbox(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try locked { try exec("DELETE FROM entity_inbox WHERE id IN (\(ids.map(String.init).joined(separator: ",")))") }
    }
}
