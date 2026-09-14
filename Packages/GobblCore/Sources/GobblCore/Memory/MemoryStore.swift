import Foundation
import SQLite3

/// Gobbl's local memory: what was on screen, in SQLite (system library, no
/// dependency) with FTS5 search. Used by the app (read/write) and by
/// gobbl-mcp (read-only). All access is serialised on one lock.
public final class MemoryStore: @unchecked Sendable {
    public struct NewChunk: Sendable {
        public var ts: Date
        public var kind: String
        public var sender: String?
        public var fromMe: Bool
        public var text: String

        public init(ts: Date, kind: String, sender: String? = nil, fromMe: Bool = false, text: String) {
            self.ts = ts
            self.kind = kind
            self.sender = sender
            self.fromMe = fromMe
            self.text = text
        }
    }

    public struct Hit: Equatable, Sendable {
        public var chunkID: Int64
        public var segmentID: Int64
        public var app: String
        public var appBundle: String = ""
        public var window: String
        public var chat: String?
        public var domain: String?
        public var sender: String?
        public var fromMe: Bool
        public var ts: Date
        public var snippet: String
    }

    public enum StoreError: Error { case open(String), sql(String) }

    var db: OpaquePointer?
    private let lock = NSLock()
    public let readOnly: Bool
    /// Search-by-meaning vectors, kept in memory between searches.
    let vectorCache = VectorCache()

    public init(url: URL, readOnly: Bool = false) throws {
        self.readOnly = readOnly
        if !readOnly {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(url.path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_busy_timeout(db, 2000)
        if !readOnly {
            try migrate()
            // Owner-only, like the rest of Gobbl's data.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: Schema

    private func migrate() throws {
        try exec("""
        PRAGMA journal_mode=WAL;
        PRAGMA secure_delete=ON;
        PRAGMA foreign_keys=ON;
        """)
        let version = try scalarInt("PRAGMA user_version")
        if version < 1 {
            try exec("""
            PRAGMA auto_vacuum=INCREMENTAL;
            CREATE TABLE IF NOT EXISTS segments(
              id INTEGER PRIMARY KEY, app_bundle TEXT NOT NULL, app_name TEXT NOT NULL, window TEXT NOT NULL DEFAULT '',
              url_domain TEXT, url TEXT, chat TEXT, started REAL NOT NULL, ended REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS segments_started ON segments(started);
            CREATE TABLE IF NOT EXISTS chunks(
              id INTEGER PRIMARY KEY, segment_id INTEGER NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
              ts REAL NOT NULL, kind TEXT NOT NULL, sender TEXT, from_me INTEGER NOT NULL DEFAULT 0, text TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS chunks_ts ON chunks(ts);
            CREATE INDEX IF NOT EXISTS chunks_segment ON chunks(segment_id);
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
              text, sender, content='chunks', content_rowid='id', tokenize='unicode61 remove_diacritics 2');
            CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
              INSERT INTO chunks_fts(rowid, text, sender) VALUES (new.id, new.text, coalesce(new.sender, ''));
            END;
            CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
              INSERT INTO chunks_fts(chunks_fts, rowid, text, sender) VALUES ('delete', old.id, old.text, coalesce(old.sender, ''));
            END;
            PRAGMA user_version=1;
            """)
        }
        if version < 2 {
            try exec("""
            CREATE TABLE IF NOT EXISTS todos(
              id INTEGER PRIMARY KEY, status TEXT NOT NULL, last_evidence REAL NOT NULL, data TEXT NOT NULL,
              evidence TEXT NOT NULL DEFAULT '[]');
            CREATE INDEX IF NOT EXISTS todos_status ON todos(status);
            CREATE TABLE IF NOT EXISTS entity_inbox(id INTEGER PRIMARY KEY, at REAL NOT NULL, data TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            PRAGMA user_version=2;
            """)
        }
        if version < 3 {
            try migrateKnowledge()
        }
        if version < 4 {
            try migrateDigests()
        }
        if version < 5 {
            try migrateVectors()
        }
    }

    // MARK: To-dos

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    @discardableResult
    public func insertTodo(_ todo: MemoryTodo, evidence: [Int64]) throws -> Int64 {
        try locked {
            let data = String(decoding: try Self.encoder.encode(todo), as: UTF8.self)
            let ev = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
            try run("INSERT INTO todos(status, last_evidence, data, evidence) VALUES (?,?,?,?)",
                    [todo.status.rawValue, todo.lastEvidence.timeIntervalSince1970, data, ev])
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func updateTodo(_ todo: MemoryTodo) throws {
        try locked {
            let data = String(decoding: try Self.encoder.encode(todo), as: UTF8.self)
            try run("UPDATE todos SET status = ?, last_evidence = ?, data = ? WHERE id = ?",
                    [todo.status.rawValue, todo.lastEvidence.timeIntervalSince1970, data, todo.id])
        }
    }

    /// Adds proof to an existing to-do (seen again) and bumps its last evidence.
    public func addEvidence(todo id: Int64, chunks: [Int64], at: Date) throws {
        try locked {
            let current = try rows("SELECT evidence FROM todos WHERE id = ?", [id]) { Self.text($0, 0) ?? "[]" }.first ?? "[]"
            var list = (try? JSONDecoder().decode([Int64].self, from: Data(current.utf8))) ?? []
            list = Array((list + chunks).suffix(30))
            let ev = String(decoding: try JSONEncoder().encode(list), as: UTF8.self)
            try run("UPDATE todos SET evidence = ?, last_evidence = max(last_evidence, ?) WHERE id = ?", [ev, at.timeIntervalSince1970, id])
        }
    }

    public func todos(_ statuses: [MemoryTodo.Status], limit: Int = 300) throws -> [MemoryTodo] {
        guard !statuses.isEmpty else { return [] }
        return try locked {
            let marks = statuses.map { _ in "?" }.joined(separator: ",")
            return try rows("SELECT id, data, last_evidence FROM todos WHERE status IN (\(marks)) ORDER BY last_evidence DESC LIMIT ?",
                            statuses.map(\.rawValue) + [limit]) { s -> MemoryTodo? in
                guard let json = Self.text(s, 1), var todo = try? Self.decoder.decode(MemoryTodo.self, from: Data(json.utf8)) else { return nil }
                todo.id = sqlite3_column_int64(s, 0)
                todo.lastEvidence = Date(timeIntervalSince1970: sqlite3_column_double(s, 2))
                return todo
            }.compactMap { $0 }
        }
    }

    /// The captured text behind a to-do, newest first.
    public func evidence(todo id: Int64) throws -> [Hit] {
        let ids: [Int64] = try locked {
            let json = try rows("SELECT evidence FROM todos WHERE id = ?", [id]) { Self.text($0, 0) ?? "[]" }.first ?? "[]"
            return (try? JSONDecoder().decode([Int64].self, from: Data(json.utf8))) ?? []
        }
        guard !ids.isEmpty else { return [] }
        return try locked {
            try rows("""
            SELECT c.id, c.segment_id, s.app_name, s.app_bundle, s.window, s.chat, s.url_domain, c.sender, c.from_me, c.ts, c.text
            FROM chunks c JOIN segments s ON s.id = c.segment_id WHERE c.id IN (\(ids.map(String.init).joined(separator: ","))) ORDER BY c.ts DESC
            """, [], Self.hit)
        }
    }

    // MARK: Entity inbox and state

    /// Raw people/project extractions, kept until the knowledge base processes them.
    public func addToEntityInbox(_ json: String, at: Date) throws {
        try locked { try run("INSERT INTO entity_inbox(at, data) VALUES (?,?)", [at.timeIntervalSince1970, json]) }
    }

    public func state(_ key: String) -> String? {
        (try? locked { try rows("SELECT value FROM state WHERE key = ?", [key]) { Self.text($0, 0) } })?.first ?? nil
    }

    public func setState(_ key: String, _ value: String) throws {
        try locked { try run("INSERT INTO state(key, value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value]) }
    }

    // MARK: Writing

    /// Starts a stretch of time in one window; returns its id.
    public func beginSegment(appBundle: String, appName: String, window: String, url: String?, chat: String?, at: Date) throws -> Int64 {
        try locked {
            try run("INSERT INTO segments(app_bundle, app_name, window, url_domain, url, chat, started, ended) VALUES (?,?,?,?,?,?,?,?)",
                    [appBundle, appName, window, CaptureRules.domain(of: url), url, chat, at.timeIntervalSince1970, at.timeIntervalSince1970])
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func addChunks(segment: Int64, _ chunks: [NewChunk]) throws {
        guard !chunks.isEmpty else { return }
        try locked {
            try exec("BEGIN")
            do {
                for c in chunks {
                    try run("INSERT INTO chunks(segment_id, ts, kind, sender, from_me, text) VALUES (?,?,?,?,?,?)",
                            [segment, c.ts.timeIntervalSince1970, c.kind, c.sender, c.fromMe ? 1 : 0, c.text])
                }
                let last = chunks.map(\.ts).max() ?? Date()
                try run("UPDATE segments SET ended = max(ended, ?) WHERE id = ?", [last.timeIntervalSince1970, segment])
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    // MARK: Reading

    /// Full-text search, newest first among the best matches.
    public func search(_ query: String, limit: Int = 20, since: Date? = nil) throws -> [Hit] {
        let fts = Self.ftsQuery(query)
        guard !fts.isEmpty else { return [] }
        return try locked {
            var sql = """
            SELECT c.id, c.segment_id, s.app_name, s.window, s.chat, s.url_domain, c.sender, c.from_me, c.ts,
                   snippet(chunks_fts, 0, '[', ']', '…', 14)
            FROM chunks_fts JOIN chunks c ON c.id = chunks_fts.rowid JOIN segments s ON s.id = c.segment_id
            WHERE chunks_fts MATCH ?
            """
            var args: [Any?] = [fts]
            if let since {
                sql += " AND c.ts >= ?"
                args.append(since.timeIntervalSince1970)
            }
            sql += " ORDER BY bm25(chunks_fts) + (? - c.ts) / 2592000.0 LIMIT ?"
            args.append(Date().timeIntervalSince1970)
            args.append(limit)
            return try rows(sql, args) { s in
                Hit(chunkID: sqlite3_column_int64(s, 0), segmentID: sqlite3_column_int64(s, 1), app: Self.text(s, 2) ?? "",
                    window: Self.text(s, 3) ?? "", chat: Self.text(s, 4), domain: Self.text(s, 5), sender: Self.text(s, 6),
                    fromMe: sqlite3_column_int(s, 7) != 0, ts: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)),
                    snippet: Self.text(s, 9) ?? "")
            }
        }
    }

    /// Chunks captured after `since`, oldest first, for extraction and digests.
    /// `snippet` holds the full text here.
    public func chunks(since: Date, limit: Int = 500) throws -> [Hit] {
        try locked {
            try rows("""
            SELECT c.id, c.segment_id, s.app_name, s.app_bundle, s.window, s.chat, s.url_domain, c.sender, c.from_me, c.ts, c.text
            FROM chunks c JOIN segments s ON s.id = c.segment_id WHERE c.ts > ? ORDER BY c.ts LIMIT ?
            """, [since.timeIntervalSince1970, limit], Self.hit)
        }
    }

    /// Rows of: id, segment, app name, bundle, window, chat, domain, sender, from_me, ts, text.
    static func hit(_ s: OpaquePointer?) -> Hit {
        var h = Hit(chunkID: sqlite3_column_int64(s, 0), segmentID: sqlite3_column_int64(s, 1), app: text(s, 2) ?? "",
                    window: text(s, 4) ?? "", chat: text(s, 5), domain: text(s, 6), sender: text(s, 7),
                    fromMe: sqlite3_column_int(s, 8) != 0, ts: Date(timeIntervalSince1970: sqlite3_column_double(s, 9)),
                    snippet: text(s, 10) ?? "")
        h.appBundle = text(s, 3) ?? ""
        return h
    }

    public struct Stats: Equatable, Sendable {
        public var chunks: Int
        public var segments: Int
        public var bytes: Int64

        public init(chunks: Int, segments: Int, bytes: Int64) {
            self.chunks = chunks
            self.segments = segments
            self.bytes = bytes
        }
    }

    public func stats() throws -> Stats {
        try locked {
            let pages = try scalarInt("PRAGMA page_count")
            let size = try scalarInt("PRAGMA page_size")
            return Stats(chunks: try scalarInt("SELECT count(*) FROM chunks"), segments: try scalarInt("SELECT count(*) FROM segments"),
                         bytes: Int64(pages) * Int64(size))
        }
    }

    // MARK: Forgetting

    /// Deletes everything captured in [from, to]. Secure-delete overwrites it on disk.
    public func forget(from: Date, to: Date = .distantFuture) throws {
        try locked {
            try run("DELETE FROM chunks WHERE ts BETWEEN ? AND ?", [from.timeIntervalSince1970, to.timeIntervalSince1970])
            try exec("DELETE FROM segments WHERE id NOT IN (SELECT DISTINCT segment_id FROM chunks)")
            try exec("DELETE FROM vectors WHERE kind = 'chunk' AND ref NOT IN (SELECT id FROM chunks)")
            vectorCache.invalidate()
            try exec("PRAGMA incremental_vacuum")
        }
    }

    public func forgetAll() throws {
        try locked {
            try exec("DELETE FROM vectors; DELETE FROM chunks; DELETE FROM segments; INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild'); VACUUM;")
            vectorCache.invalidate()
        }
    }

    /// Everything from one app (the user excluded it after the fact).
    public func forget(appBundle: String) throws {
        try locked {
            try run("DELETE FROM segments WHERE app_bundle = ?", [appBundle])
            try exec("DELETE FROM vectors WHERE kind = 'chunk' AND ref NOT IN (SELECT id FROM chunks)")
            vectorCache.invalidate()
            try exec("PRAGMA incremental_vacuum")
        }
    }

    // MARK: FTS query building

    /// User text → a safe FTS5 query: every word must appear, prefix-matched.
    static func ftsQuery(_ query: String) -> String {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .prefix(8)
            .map { "\"\($0)\"*" }
            .joined(separator: " ")
    }

    // MARK: SQLite plumbing

    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw StoreError.sql(message)
        }
    }

    func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg {
            case nil: sqlite3_bind_null(stmt, index)
            case let v as Int: sqlite3_bind_int64(stmt, index, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, index, v)
            case let v as Double: sqlite3_bind_double(stmt, index, v)
            case let v as String: sqlite3_bind_text(stmt, index, v, -1, transient)
            default: sqlite3_bind_text(stmt, index, "\(arg!)", -1, transient)
            }
        }
        return stmt
    }

    func run(_ sql: String, _ args: [Any?]) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
    }

    func rows<T>(_ sql: String, _ args: [Any?], _ map: (OpaquePointer?) -> T) throws -> [T] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(map(stmt)) } else if rc == SQLITE_DONE { break } else {
                throw StoreError.sql(String(cString: sqlite3_errmsg(db)))
            }
        }
        return out
    }

    func scalarInt(_ sql: String) throws -> Int {
        try rows(sql, []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: c)
    }
}
