import Foundation
import GobblCore

/// What chat gets from memory for a question: cards for the people and
/// projects it names, open to-dos when it asks about them, and the best
/// matching snippets. Capped at 12 items and 3,000 characters, each with a
/// source the answer cites ("WhatsApp · Samar · Sat 6:02 PM").
@MainActor
enum MemoryRecall {
    static func items(for question: String) -> [[String: String]] {
        guard MemoryModel.shared.enabled, let store = MemoryModel.shared.store else { return [] }
        var items: [[String: String]] = []
        var used = 0
        func add(_ source: String, _ text: String) {
            let text = String(text.prefix(600))
            let source = String(source.prefix(80))
            guard items.count < 12, !text.isEmpty, used + text.count + source.count <= 3000,
                  !items.contains(where: { $0["text"] == text }) else { return }
            used += text.count + source.count
            items.append(["source": source, "text": text])
        }

        for name in candidateNames(question) {
            guard let entity = (try? store.findEntity(named: name)) ?? nil, let detail = (try? store.entityDetail(entity.id)) ?? nil else { continue }
            add("\(entity.type == .person ? "Person" : entity.type.title) · \(entity.name)", describe(detail))
        }
        if question.range(of: #"(?i)\b(owe|to-?dos?|pending|promis|follow|remind|open items|left to do|what.*(do|finish))"#, options: .regularExpression) != nil {
            let list = TodoCenter.shared.open.prefix(8).map { t in
                "- \(t.title) (\(t.sourceApp)\(t.chat.map { " · \($0)" } ?? ""))\(t.due.map { ", due \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")"
            }
            if !list.isEmpty { add("Gobbl to-dos", list.joined(separator: "\n")) }
        }
        // "What did I do today?", "recap yesterday": the day's digest and where the time went.
        if let span = activitySpan(question), let range = DayParts.range(of: span.day, calendar: .current) {
            if let digest = DigestCenter.shared.text(forDay: span.day) { add("Gobbl digest · \(span.label)", digest) }
            let segments = (try? store.segments(from: range.start, to: min(range.end, Date()), excerptChars: 160)) ?? []
            var byPlace: [String: (minutes: Double, excerpt: String)] = [:]
            for s in segments {
                let place = "\(s.app) · \(s.chat ?? s.domain ?? String(s.window.prefix(40)))"
                let current = byPlace[place] ?? (0, "")
                byPlace[place] = (current.minutes + s.minutes, current.excerpt.isEmpty ? s.excerpt : current.excerpt)
            }
            let lines = byPlace.sorted { $0.value.minutes > $1.value.minutes }.prefix(10).map { place, v in
                "- \(place): \(Int(v.minutes.rounded())) min. \(v.excerpt.prefix(120))"
            }
            if !lines.isEmpty { add("Activity · \(span.label)", lines.joined(separator: "\n")) }
        }

        let words = keywords(question)
        var hits = (try? store.search(words.joined(separator: " "), limit: 8)) ?? []
        if hits.isEmpty, let first = words.first { hits = (try? store.search(first, limit: 6)) ?? [] }
        // Few word matches: add what's closest in meaning.
        if hits.count < 3 {
            hits += SemanticIndex.shared.search(question, limit: 4).filter { h in !hits.contains { $0.chunkID == h.chunkID } }
        }
        for hit in hits { add(source(hit), hit.snippet.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")) }
        return items
    }

    /// Questions about what the user did: which day, if any.
    static func activitySpan(_ question: String) -> (day: String, label: String)? {
        let q = question.lowercased()
        let asksActivity = q.range(of: #"\b(what (did|have|was) i|what i did|worked on|working on|been doing|been up to|my day|recap|summar|how did i spend|where did (my )?time go|what happened)"#,
                                   options: .regularExpression) != nil
        guard asksActivity else { return nil }
        let yesterday = q.contains("yesterday")
        let date = yesterday ? Date().addingTimeInterval(-86400) : Date()
        return (DayParts.dayKey(date, calendar: .current), yesterday ? "yesterday" : "today")
    }

    static func source(_ h: MemoryStore.Hit) -> String {
        let place = h.chat ?? h.sender ?? h.domain ?? String(h.window.prefix(30))
        return "\(h.app) · \(place) · \(h.ts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))"
    }

    private static func describe(_ d: EntityDetail) -> String {
        var lines: [String] = [d.summary.name]
        if let role = d.summary.role { lines.append("Role: \(role)") }
        if let org = d.summary.org { lines.append("Organisation: \(org)") }
        if let last = d.recent.first {
            lines.append("Last seen: \(last.app)\(last.chat.map { " · \($0)" } ?? "") on \(last.ts.formatted(date: .abbreviated, time: .shortened))")
        }
        for fact in d.facts.prefix(3) { lines.append("\(fact.key): \(fact.value)") }
        let related = d.related.prefix(4).map { "\($0.entity.name) (\($0.kind.replacingOccurrences(of: "_", with: " ")))" }
        if !related.isEmpty { lines.append("Connected: " + related.joined(separator: ", ")) }
        for hit in d.recent.prefix(2) { lines.append("Recent: \(hit.snippet.prefix(140))") }
        if !d.notes.isEmpty { lines.append("User's notes: \(d.notes.prefix(160))") }
        return lines.joined(separator: "\n")
    }

    private static let stop: Set<String> = [
        "what", "who", "whom", "whose", "when", "where", "why", "how", "which", "does", "did", "do", "is", "are", "was", "were",
        "the", "and", "for", "with", "about", "from", "that", "this", "have", "has", "had", "you", "your", "can", "could",
        "tell", "me", "my", "any", "anything", "remind", "said", "say", "says", "week", "today", "yesterday", "there", "been",
        "gobbl", "please", "know", "last", "owe", "still", "left",
    ]

    static func keywords(_ question: String) -> [String] {
        Array(question.lowercased().components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { $0.count >= 3 && !stop.contains($0) }.prefix(4))
    }

    /// Names the question points at: after "who is / about / with …", and capitalised runs.
    static func candidateNames(_ question: String) -> [String] {
        var out: [String] = []
        let patterns = [
            #"(?i)\b(?:who is|who's|about|with|from|to|for|tell me about|owe)\s+([\p{L}][\p{L}.'-]*(?:\s+[\p{Lu}][\p{L}.'-]*){0,2})"#,
            #"\b(\p{Lu}[\p{Ll}]+(?:\s+\p{Lu}[\p{Ll}]+){0,2})"#,
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = question as NSString
            for m in re.matches(in: question, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                if name.count >= 2, !stop.contains(name.lowercased()), !out.contains(name) { out.append(name) }
            }
        }
        return Array(out.prefix(4))
    }
}
