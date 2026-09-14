import Foundation
import SQLite3

/// "Search by meaning": sentence vectors (from Apple's on-device
/// NLEmbedding, computed by the app) for snippets, people, to-dos and
/// digests, searched by cosine similarity. Brute force over an in-memory
/// copy: a few tens of thousands of 512-number vectors is milliseconds.
public enum VectorKind: String, Sendable {
    case chunk, entity, todo, digest
}

public struct VectorHit: Equatable, Sendable {
    public var kind: VectorKind
    public var ref: Int64
    public var score: Float
}

public enum VectorMath {
    public static func normalized(_ v: [Float]) -> [Float] {
        let length = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return length > 0 ? v.map { $0 / length } : v
    }

    /// Both already normalised: the dot product is the cosine.
    public static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var sum: Float = 0
        for i in 0..<a.count { sum += a[i] * b[i] }
        return sum
    }

    static func encode(_ v: [Float]) -> Data {
        v.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

extension MemoryStore {
    func migrateVectors() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS vectors(kind TEXT NOT NULL, ref INTEGER NOT NULL, vec BLOB NOT NULL, PRIMARY KEY(kind, ref));
        PRAGMA user_version=5;
        """)
    }

    /// Stores (or replaces) a vector; it's normalised first.
    public func setVector(_ kind: VectorKind, ref: Int64, _ vector: [Float]) throws {
        let data = VectorMath.encode(VectorMath.normalized(vector))
        try locked {
            let stmt = try prepare("INSERT OR REPLACE INTO vectors(kind, ref, vec) VALUES (?,?,?)", [kind.rawValue, ref])
            defer { sqlite3_finalize(stmt) }
            _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
        }
        vectorCache.invalidate()
    }

    /// Chunks with enough text that don't have a vector yet, oldest first.
    public func chunksNeedingVectors(limit: Int = 300) throws -> [(id: Int64, text: String)] {
        try locked {
            try rows("""
            SELECT c.id, c.text FROM chunks c LEFT JOIN vectors v ON v.kind = 'chunk' AND v.ref = c.id
            WHERE v.ref IS NULL AND length(c.text) >= 20 ORDER BY c.id LIMIT ?
            """, [limit]) { (sqlite3_column_int64($0, 0), Self.text($0, 1) ?? "") }
        }
    }

    /// The closest items to `query` (a raw vector; normalised here).
    /// 0.48: Apple's sentence vectors score related text around 0.6 and
    /// unrelated text around 0.35–0.4, so this keeps the noise out.
    public func nearest(_ query: [Float], kinds: Set<VectorKind>, limit: Int = 20, minScore: Float = 0.48) throws -> [VectorHit] {
        let q = VectorMath.normalized(query)
        let all = try vectorCache.load { try self.allVectors() }
        var hits: [VectorHit] = []
        for entry in all where kinds.contains(entry.kind) {
            let score = VectorMath.dot(q, entry.vec)
            if score >= minScore { hits.append(VectorHit(kind: entry.kind, ref: entry.ref, score: score)) }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Snippets for chunk ids, in the given order (for showing semantic hits).
    public func hits(forChunks ids: [Int64]) throws -> [Hit] {
        guard !ids.isEmpty else { return [] }
        let found = try locked {
            try rows("""
            SELECT c.id, c.segment_id, s.app_name, s.app_bundle, s.window, s.chat, s.url_domain, c.sender, c.from_me, c.ts, c.text
            FROM chunks c JOIN segments s ON s.id = c.segment_id WHERE c.id IN (\(ids.map(String.init).joined(separator: ",")))
            """, [], Self.hit)
        }
        let byID = Dictionary(found.map { ($0.chunkID, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }

    fileprivate func allVectors() throws -> [VectorCache.Entry] {
        try locked {
            // Vectors whose chunk was forgotten go too.
            try exec("DELETE FROM vectors WHERE kind = 'chunk' AND ref NOT IN (SELECT id FROM chunks)")
            return try rows("SELECT kind, ref, vec FROM vectors", []) { s in
                let bytes = sqlite3_column_blob(s, 2)
                let count = Int(sqlite3_column_bytes(s, 2))
                let data = bytes.map { Data(bytes: $0, count: count) } ?? Data()
                return VectorCache.Entry(kind: VectorKind(rawValue: Self.text(s, 0) ?? "") ?? .chunk, ref: sqlite3_column_int64(s, 1),
                                         vec: VectorMath.decode(data))
            }
        }
    }
}

/// The vectors, kept in memory between searches and dropped on any write.
final class VectorCache: @unchecked Sendable {
    struct Entry {
        let kind: VectorKind
        let ref: Int64
        let vec: [Float]
    }

    private var entries: [Entry]?
    private let lock = NSLock()

    func load(_ fetch: () throws -> [Entry]) throws -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        if let entries { return entries }
        let fresh = try fetch()
        entries = fresh
        return fresh
    }

    func invalidate() {
        lock.lock()
        entries = nil
        lock.unlock()
    }
}
