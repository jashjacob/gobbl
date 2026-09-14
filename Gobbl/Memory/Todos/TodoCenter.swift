import AppKit
import GobblCore
import Observation
import os

private let log = Logger(subsystem: "com.xeve.gobbl", category: "todos")

/// To-dos Gobbl notices on screen. Every half hour of activity it sends the
/// few captured snippets that look like tasks (chats, mail, checkouts,
/// "can you…") to the AI, turns the answer into suggestions, and merges
/// repeats. Each suggestion carries a "done signal" that is checked locally
/// against new captures, so finished things tick themselves off (with Undo).
@MainActor @Observable
final class TodoCenter {
    static let shared = TodoCenter()

    /// Suggested and confirmed, due or best first.
    private(set) var open: [MemoryTodo] = []
    /// Lower-confidence finds, only mentioned in the brief.
    private(set) var maybe: [MemoryTodo] = []
    /// Recently ticked off automatically, for Undo.
    private(set) var autoDone: [MemoryTodo] = []
    private(set) var extracting = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var resolveWatermark = Date()

    static let maxExtractionsPerDay = 12

    private var store: MemoryStore? { MemoryModel.shared.store }
    private var sensitivity: TodoSensitivity {
        TodoSensitivity(rawValue: UserDefaults.standard.string(forKey: "todoSensitivity") ?? "") ?? .balanced
    }

    func start() {
        reload()
        let timer = Timer(timeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { TodoCenter.shared.tick() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let store else { return }
        let now = Date()
        // Snoozes that are up come back; quiet week-old ones go stale.
        for var t in (try? store.todos([.snoozed, .suggested, .maybe, .confirmed])) ?? [] {
            if t.status == .snoozed, let until = t.snoozedUntil, until <= now {
                t.status = t.previousStatus ?? .suggested
                t.snoozedUntil = nil
                try? store.updateTodo(t)
            } else if TodoRules.isStale(t, now: now) {
                t.previousStatus = t.status
                t.status = .stale
                try? store.updateTodo(t)
            }
        }
        reload()
        guard MemoryModel.shared.isCapturing, AIClient.shared.isRegistered else { return }
        let last = UserDefaults.standard.object(forKey: "extractLastRun") as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= 30 * 60, extractionsToday < Self.maxExtractionsPerDay else { return }
        Task { await extract() }
    }

    // MARK: Extraction

    func extract() async {
        guard !extracting, let store, AIClient.shared.isRegistered else { return }
        extracting = true
        defer { extracting = false }
        let now = Date()
        let watermark = store.state("extractWatermark").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
            ?? now.addingTimeInterval(-6 * 3600)
        guard let chunks = try? store.chunks(since: watermark, limit: 400), let newest = chunks.last else { return }

        // Newest first until the batch is full, then back in time order.
        var picked: [MemoryStore.Hit] = []
        var total = 0
        for c in chunks.reversed() where ExtractionFilter.isCandidate(appKind: CaptureRules.kind(of: c.appBundle), domain: c.domain, text: c.snippet) {
            let length = min(c.snippet.count, 1200)
            if total + length > 5800 || picked.count >= 110 { break }
            picked.append(c)
            total += length
        }
        picked.reverse()
        guard !picked.isEmpty else {
            try? store.setState("extractWatermark", String(newest.ts.timeIntervalSince1970))
            return
        }

        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var refs: [String: MemoryStore.Hit] = [:]
        let batch: [[String: Any]] = picked.map { c in
            let ref = "c\(c.chunkID)"
            refs[ref] = c
            var item: [String: Any] = [
                "ref": ref, "app": c.app, "window": String(c.window.prefix(160)), "fromMe": c.fromMe,
                "time": iso.string(from: c.ts), "text": String(c.snippet.prefix(1200)),
                "kind": c.chat != nil ? "message" : (CaptureRules.kind(of: c.appBundle) == .mail ? "mail" : "text"),
            ]
            if let chat = c.chat { item["chat"] = chat }
            if let domain = c.domain { item["url_domain"] = domain }
            if let sender = c.sender { item["sender"] = sender }
            return item
        }
        let body: [String: Any] = ["batch": batch, "known": KnowledgeCenter.shared.knownNames(),
                                   "now": iso.string(from: now), "timezone": TimeZone.current.identifier, "locale": AIClient.locale]
        do {
            let result = try await AIClient.shared.json("/v1/extract", body: body)
            UserDefaults.standard.set(now, forKey: "extractLastRun")
            countExtraction()
            try? store.setState("extractWatermark", String(newest.ts.timeIntervalSince1970))
            ingest(result, refs: refs, store: store)
            KnowledgeCenter.shared.process()
            log.info("extracted from \(picked.count) snippets")
        } catch {
            // Over quota or paused: try again next window without losing anything.
            UserDefaults.standard.set(now, forKey: "extractLastRun")
            log.error("extract failed: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    private func ingest(_ result: [String: Any], refs: [String: MemoryStore.Hit], store: MemoryStore) {
        let known = (try? store.todos([.suggested, .maybe, .confirmed, .snoozed, .dismissed, .done, .autoDone], limit: 500)) ?? []
        let neverApps = Set(UserDefaults.standard.stringArray(forKey: "todoNeverApps") ?? [])
        let iso = ISO8601DateFormatter()
        let isoDay = ISO8601DateFormatter()
        isoDay.formatOptions = [.withFullDate]
        var added = 0

        for raw in result["todos"] as? [[String: Any]] ?? [] {
            guard let title = raw["title"] as? String, let ref = raw["source_ref"] as? String, let hit = refs[ref],
                  let status = TodoRules.initialStatus(confidence: raw["confidence"] as? Double ?? 0, sensitivity: sensitivity),
                  !neverApps.contains(hit.app) else { continue }
            let due = (raw["due"] as? String).flatMap { iso.date(from: $0) ?? isoDay.date(from: $0) }
            let signal = (raw["done_signal"] as? [String: Any]).map {
                MemoryTodo.DoneSignal(type: $0["type"] as? String ?? "none", pattern: $0["pattern"] as? String ?? "")
            }
            let todo = MemoryTodo(title: title, reason: raw["reason"] as? String ?? "", status: status,
                                  confidence: raw["confidence"] as? Double ?? 0, sourceApp: hit.app, window: hit.window,
                                  chat: hit.chat, domain: hit.domain, people: raw["people"] as? [String] ?? [],
                                  firstSeen: hit.ts, due: due, doneSignal: signal)
            if var existing = known.first(where: { TodoRules.isDuplicate(todo, of: $0) }) {
                // Seen again: more evidence, and a "maybe" that keeps coming back becomes a suggestion.
                try? store.addEvidence(todo: existing.id, chunks: [hit.chunkID], at: hit.ts)
                if existing.status == .maybe && status == .suggested {
                    existing.status = .suggested
                    try? store.updateTodo(existing)
                }
                continue
            }
            if (try? store.insertTodo(todo, evidence: [hit.chunkID])) != nil, status == .suggested { added += 1 }
        }

        // People and projects wait in the inbox for the knowledge base.
        let entities = result["entities"] as? [[String: Any]] ?? []
        let relations = result["relations"] as? [[String: Any]] ?? []
        let facts = result["facts"] as? [[String: Any]] ?? []
        if !entities.isEmpty || !relations.isEmpty || !facts.isEmpty {
            let evidence = refs.mapValues { $0.chunkID }
            let payload: [String: Any] = ["entities": entities, "relations": relations, "facts": facts, "refs": evidence]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? store.addToEntityInbox(String(decoding: data, as: UTF8.self), at: Date())
            }
        }
        if added > 0 {
            HUDModel.shared.show(.init(symbol: "checklist", label: added == 1 ? "1 new to-do" : "\(added) new to-dos", tint: Palette.accent), for: 3)
        }
    }

    private var extractionsToday: Int {
        let key = Self.dayKey()
        return (UserDefaults.standard.dictionary(forKey: "extractCounts") as? [String: Int])?[key] ?? 0
    }

    private func countExtraction() {
        let key = Self.dayKey()
        var counts = (UserDefaults.standard.dictionary(forKey: "extractCounts") as? [String: Int]) ?? [:]
        counts = counts.filter { $0.key == key }
        counts[key, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: "extractCounts")
    }

    private static func dayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: Ticking off automatically

    /// New captures arrived: does any of them prove an open to-do is done?
    func checkResolution() {
        guard let store else { return }
        let candidates = open.filter { ($0.doneSignal?.type ?? "none") != "none" }
        guard !candidates.isEmpty, let fresh = try? store.chunks(since: resolveWatermark, limit: 200), let newest = fresh.last else { return }
        resolveWatermark = newest.ts
        for var todo in candidates {
            guard let proof = fresh.first(where: {
                TodoRules.resolves(todo, TodoObservation(text: $0.snippet, domain: $0.domain, chat: $0.chat, fromMe: $0.fromMe,
                                                         kind: $0.chat != nil ? "message" : "text"))
            }) else { continue }
            todo.previousStatus = todo.status
            todo.status = .autoDone
            todo.resolvedAt = proof.ts
            todo.resolvedBy = "auto"
            try? store.updateTodo(todo)
            try? store.addEvidence(todo: todo.id, chunks: [proof.chunkID], at: proof.ts)
            HUDModel.shared.show(.init(symbol: "checkmark.circle.fill", label: "Done: \(String(todo.title.prefix(14)))", tint: Palette.accent), for: 4)
            PetModel.shared.send(.celebrate)
        }
        reload()
    }

    // MARK: Actions

    func complete(_ todo: MemoryTodo) { change(todo) { $0.status = .done; $0.resolvedAt = Date(); $0.resolvedBy = "user" } }
    func confirm(_ todo: MemoryTodo) { change(todo) { $0.status = .confirmed } }

    func dismiss(_ todo: MemoryTodo, reason: String = "not_a_todo") {
        change(todo) { $0.status = .dismissed; $0.dismissReason = reason }
    }

    func snooze(_ todo: MemoryTodo, until: Date) {
        change(todo) { $0.previousStatus = $0.status; $0.status = .snoozed; $0.snoozedUntil = until }
    }

    /// Puts an automatic tick-off (or a stale one) back where it was.
    func undo(_ todo: MemoryTodo) {
        change(todo) { $0.status = $0.previousStatus ?? .suggested; $0.resolvedAt = nil; $0.resolvedBy = nil }
    }

    /// "Never suggest from this app": remembered, and its open suggestions go.
    func neverSuggest(from app: String) {
        var apps = Set(UserDefaults.standard.stringArray(forKey: "todoNeverApps") ?? [])
        apps.insert(app)
        UserDefaults.standard.set(Array(apps), forKey: "todoNeverApps")
        for todo in open + maybe where todo.sourceApp == app && todo.status != .confirmed { dismiss(todo, reason: "app") }
    }

    private func change(_ todo: MemoryTodo, _ edit: (inout MemoryTodo) -> Void) {
        var t = todo
        edit(&t)
        try? store?.updateTodo(t)
        reload()
    }

    func reload() {
        guard let store else {
            open = []
            maybe = []
            autoDone = []
            return
        }
        open = TodoRules.sorted((try? store.todos([.suggested, .confirmed])) ?? [])
        maybe = (try? store.todos([.maybe], limit: 20)) ?? []
        autoDone = Array(((try? store.todos([.autoDone], limit: 5)) ?? []))
    }
}
