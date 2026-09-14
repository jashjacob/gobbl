import AppKit
import GobblCore
import Observation

/// Builds the "who is who": people from chat senders and one-to-one chats
/// (free, local), then the AI's extractions (people, projects, orgs,
/// relations, facts) waiting in the inbox. Merges only on hard matches;
/// softer ones become "Same person?" questions.
@MainActor @Observable
final class KnowledgeCenter {
    static let shared = KnowledgeCenter()

    private(set) var suggestions: [MergeSuggestion] = []
    /// Bumped after every change, so lists reload.
    private(set) var version = 0
    private(set) var lastMerge: Int64?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var running = false

    private var store: MemoryStore? { MemoryModel.shared.store }

    func start() {
        let timer = Timer(timeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { KnowledgeCenter.shared.process() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        process()
    }

    /// Names the AI should link to rather than invent again.
    func knownNames() -> [String: [String]] {
        guard let store else { return ["people": [], "projects": []] }
        return ["people": ((try? store.entities(.person, limit: 200)) ?? []).map(\.name),
                "projects": ((try? store.entities(.project, limit: 100)) ?? []).map(\.name)]
    }

    func process() {
        guard !running, let store else { return }
        running = true
        let me = Set((MemoryModel.myNames + ["you"]).map(EntityRules.normalize))
        Task.detached(priority: .utility) {
            Self.harvestSenders(store, me: me)
            Self.drainInbox(store)
            let suggestions = (try? store.mergeSuggestions()) ?? []
            await MainActor.run {
                KnowledgeCenter.shared.suggestions = suggestions
                KnowledgeCenter.shared.version += 1
                KnowledgeCenter.shared.running = false
            }
        }
    }

    /// Chat senders, and the other person in one-to-one chats, become people.
    nonisolated private static func harvestSenders(_ store: MemoryStore, me: Set<String>) {
        let since = store.state("kbWatermark").flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        guard let chunks = try? store.chunks(since: since, limit: 1000), let newest = chunks.last else { return }
        for c in chunks where c.chat != nil || c.sender != nil {
            if let sender = c.sender, !me.contains(EntityRules.normalize(sender)) {
                if let id = (try? store.upsertEntity(type: .person, name: sender, scope: c.app, at: c.ts)) ?? nil {
                    try? store.addMention(entity: id, chunk: c.chunkID, role: "sender", at: c.ts, app: c.app)
                }
            } else if c.sender == nil, let chat = c.chat, MessagingParser.looksLikeName(chat), !me.contains(EntityRules.normalize(chat)) {
                if let id = (try? store.upsertEntity(type: .person, name: chat, scope: c.app, at: c.ts)) ?? nil {
                    try? store.addMention(entity: id, chunk: c.chunkID, role: c.fromMe ? "recipient" : "sender", at: c.ts, app: c.app)
                }
            }
        }
        try? store.setState("kbWatermark", String(newest.ts.timeIntervalSince1970))
    }

    /// The AI's people, projects, orgs, relations and facts, each tied to its snippet.
    nonisolated private static func drainInbox(_ store: MemoryStore) {
        guard let entries = try? store.takeEntityInbox(limit: 50), !entries.isEmpty else { return }
        let now = Date()
        for entry in entries {
            guard let payload = try? JSONSerialization.jsonObject(with: Data(entry.json.utf8)) as? [String: Any] else { continue }
            let refs = payload["refs"] as? [String: Any] ?? [:]
            func chunk(_ ref: Any?) -> Int64? {
                guard let r = ref as? String, let n = refs[r] as? NSNumber else { return nil }
                return n.int64Value
            }
            var ids: [String: Int64] = [:]
            for e in payload["entities"] as? [[String: Any]] ?? [] {
                guard let name = e["name"] as? String, let type = EntityType(rawValue: e["type"] as? String ?? "") else { continue }
                let identifiers = (e["identifiers"] as? [[String: Any]] ?? []).compactMap { d -> (type: String, value: String)? in
                    guard let t = d["type"] as? String, let v = d["value"] as? String else { return nil }
                    return (t, v)
                }
                guard let id = (try? store.upsertEntity(type: type, name: name, aliases: e["aliases"] as? [String] ?? [],
                                                        identifiers: identifiers, role: e["role"] as? String,
                                                        org: e["org"] as? String, at: now)) ?? nil else { continue }
                ids[EntityRules.normalize(name)] = id
                let evidence = chunk(e["evidence_ref"])
                if let evidence { try? store.addMention(entity: id, chunk: evidence, role: "mentioned", at: now, app: "") }
                if type == .person, let org = e["org"] as? String, let orgID = (try? store.upsertEntity(type: .org, name: org, at: now)) ?? nil {
                    try? store.addRelation(id, orgID, kind: "works_at", evidence: evidence)
                }
            }
            func resolve(_ name: Any?) -> Int64? {
                guard let name = name as? String else { return nil }
                return ids[EntityRules.normalize(name)] ?? ((try? store.findEntity(named: name)) ?? nil)?.id
            }
            for r in payload["relations"] as? [[String: Any]] ?? [] {
                guard let a = resolve(r["a"]), let b = resolve(r["b"]), let kind = r["kind"] as? String else { continue }
                try? store.addRelation(a, b, kind: kind, evidence: chunk(r["evidence_ref"]))
            }
            for f in payload["facts"] as? [[String: Any]] ?? [] {
                guard let id = resolve(f["entity"]), let key = f["key"] as? String, let value = f["value"] as? String else { continue }
                try? store.addFact(entity: id, key: key, value: value, evidence: chunk(f["evidence_ref"]), confidence: f["confidence"] as? Double ?? 0.7)
            }
        }
        try? store.removeFromEntityInbox(entries.map(\.id))
    }

    // MARK: Actions

    /// Keeps the fuller name.
    func merge(_ s: MergeSuggestion) {
        guard let store else { return }
        let keep = s.a.name.count >= s.b.name.count ? s.a : s.b
        let remove = keep.id == s.a.id ? s.b : s.a
        lastMerge = try? store.merge(keep: keep.id, remove: remove.id)
        refresh()
    }

    func reject(_ s: MergeSuggestion) {
        try? store?.rejectMerge(s.a.id, s.b.id)
        refresh()
    }

    func undoLastMerge() {
        if let lastMerge { try? store?.undoMerge(lastMerge) }
        lastMerge = nil
        refresh()
    }

    func forget(_ id: Int64) {
        try? store?.forgetEntity(id)
        refresh()
    }

    func refresh() {
        if let store { suggestions = (try? store.mergeSuggestions()) ?? [] }
        version += 1
    }
}
