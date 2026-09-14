import Foundation
import GobblCore

/// What chat gets from memory for a question. The AI first turns the question
/// into a plan (/v1/plan: which days, apps, sites, chats and people, what kind
/// of answer), the Mac runs it against the local store, and only the results
/// go to /v1/chat. Every item carries a source the answer cites
/// ("WhatsApp · Samar · Sat 6:02 PM"). If the plan call fails, a local
/// keyword heuristic stands in.
@MainActor
enum MemoryRecall {
    static let maxItems = 16
    static let maxItemChars = 1500
    static let maxTotalChars = 6000

    /// The last plan, for `--recall`.
    private(set) static var lastPlan: Plan?

    struct Plan {
        var needsMemory = true
        var from: String?
        var to: String?
        var part: String?
        var lastHours: Int?
        var apps: [String] = []
        var sites: [String] = []
        var chats: [String] = []
        var people: [String] = []
        var fromMe: Bool?
        var queries: [String] = []
        var want: Set<String> = []
        var order = "relevance"

        init() {}

        init(_ json: [String: Any]) {
            needsMemory = json["needs_memory"] as? Bool ?? false
            from = json["from"] as? String
            to = json["to"] as? String
            part = json["part"] as? String
            lastHours = json["last_hours"] as? Int
            apps = json["apps"] as? [String] ?? []
            sites = json["sites"] as? [String] ?? []
            chats = json["chats"] as? [String] ?? []
            people = json["people"] as? [String] ?? []
            fromMe = json["from_me"] as? Bool
            queries = json["queries"] as? [String] ?? []
            want = Set(json["want"] as? [String] ?? [])
            order = json["order"] as? String ?? "relevance"
        }

        var summary: String {
            var parts = ["want: \(want.sorted().joined(separator: ","))"]
            if let lastHours { parts.append("last \(lastHours)h") }
            if let from { parts.append("days: \(from)…\(to ?? from)") }
            if let part { parts.append("part: \(part)") }
            for (k, v) in [("apps", apps), ("sites", sites), ("chats", chats), ("people", people), ("queries", queries)] where !v.isEmpty {
                parts.append("\(k): \(v.joined(separator: ", "))")
            }
            if let fromMe { parts.append(fromMe ? "from me" : "from others") }
            if order != "relevance" { parts.append("order: \(order)") }
            return needsMemory ? parts.joined(separator: " · ") : "no memory needed"
        }
    }

    // MARK: Entry point

    /// `conversation`: earlier turns (not the question), for follow-ups like "and on WhatsApp?".
    static func items(for question: String, conversation: [[String: String]] = []) async -> [[String: String]] {
        let store = MemoryModel.shared.enabled ? MemoryModel.shared.store : nil
        let places = store.flatMap { try? $0.recentPlaces(since: Date().addingTimeInterval(-14 * 86400)) } ?? []
        var body: [String: Any] = [
            "question": question,
            "conversation": Array(conversation.suffix(4)),
            "today": DayParts.dayKey(Date(), calendar: .current),
            "weekday": Date().formatted(.dateTime.weekday(.wide)),
            "time": Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()),
        ]
        body["apps"] = top(places.map { ($0.app, $0.segments) }, 40)
        body["sites"] = top(places.compactMap { p in p.domain.map { ($0, p.segments) } }, 40)
        body["chats"] = top(places.compactMap { p in p.chat.map { ($0, p.segments) } }, 60)
        if let store {
            let people = ((try? store.entities(.person, limit: 50)) ?? []) + ((try? store.entities(.project, limit: 10)) ?? [])
            body["people"] = people.map(\.name)
        }

        guard let json = try? await AIClient.shared.json("/v1/plan", body: body) else {
            lastPlan = nil
            return store == nil ? [] : heuristicItems(for: question)
        }
        let plan = Plan(json)
        lastPlan = plan
        guard plan.needsMemory else { return [] }
        guard let store else {
            return [["source": "Memory note",
                     "text": "Memory is off, so Gobbl has no record of what was on screen. It can be turned on in Settings, Memory."]]
        }
        return run(plan, question: question, store: store)
    }

    private static func top(_ pairs: [(String, Int)], _ n: Int) -> [String] {
        var counts: [String: Int] = [:]
        for (name, c) in pairs where !name.isEmpty { counts[name, default: 0] += c }
        return counts.sorted { $0.value > $1.value }.prefix(n).map(\.key)
    }

    // MARK: Running a plan

    struct Window {
        var start: Date?
        var end: Date
        var part: String?
        var label: String

        func contains(_ date: Date) -> Bool {
            if let start, date < start { return false }
            if date >= end { return false }
            if let part, DayParts.part(of: date, calendar: .current) != part { return false }
            return true
        }

        /// Day keys the window covers, newest first, at most 7.
        var days: [String] {
            guard let start else { return [] }
            var out: [String] = []
            var d = end.addingTimeInterval(-1)
            while d >= start.addingTimeInterval(-1), out.count < 7 {
                let key = DayParts.dayKey(d, calendar: .current)
                if !out.contains(key) { out.append(key) }
                d = d.addingTimeInterval(-86400)
            }
            return out
        }
    }

    static func window(for plan: Plan, now: Date = Date()) -> Window? {
        let cal = Calendar.current
        let partLabel = plan.part.map { " \($0)" } ?? ""
        if let h = plan.lastHours {
            return Window(start: now.addingTimeInterval(-Double(h) * 3600), end: now, part: nil,
                          label: h == 1 ? "the last hour" : "the last \(h) hours")
        }
        let today = DayParts.dayKey(now, calendar: cal)
        if let from = plan.from, let a = DayParts.range(of: from, calendar: cal), let b = DayParts.range(of: plan.to ?? from, calendar: cal) {
            return Window(start: a.start, end: min(b.end, now), part: plan.part, label: dayLabel(from, plan.to ?? from, today: today) + partLabel)
        }
        // No time given: summaries default to today, searches look at all of memory.
        let summaries: Set<String> = ["activity", "time", "contacts", "sites", "messages"]
        if !plan.want.isDisjoint(with: summaries), plan.queries.isEmpty || !plan.want.contains("search"),
           let r = DayParts.range(of: today, calendar: cal) {
            return Window(start: r.start, end: now, part: plan.part, label: "today" + partLabel)
        }
        return nil
    }

    static func dayLabel(_ from: String, _ to: String, today: String) -> String {
        let yesterday = DayParts.dayKey(Date().addingTimeInterval(-86400), calendar: .current)
        func one(_ d: String) -> String {
            if d == today { return "today" }
            if d == yesterday { return "yesterday" }
            guard let r = DayParts.range(of: d, calendar: .current) else { return d }
            return r.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return from == to ? one(from) : "\(one(from)) to \(one(to))"
    }

    private final class Collector {
        var items: [[String: String]] = []
        var used = 0

        var full: Bool { items.count >= MemoryRecall.maxItems || used >= MemoryRecall.maxTotalChars - 100 }

        func add(_ source: String, _ text: String) {
            let source = String(source.prefix(80))
            var text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(MemoryRecall.maxItemChars))
            let room = MemoryRecall.maxTotalChars - used - source.count
            guard !full, !text.isEmpty, room > 60, !items.contains(where: { $0["text"] == text }) else { return }
            if text.count > room { text = String(text.prefix(room - 1)) + "…" }
            used += text.count + source.count
            items.append(["source": source, "text": text])
        }
    }

    static func run(_ plan: Plan, question: String, store: MemoryStore) -> [[String: String]] {
        let out = Collector()
        let now = Date()
        let window = window(for: plan, now: now)
        let label = window?.label ?? "all of memory"
        let filters = Filters(plan)

        // What memory can and can't know: paused, or asked about a time before it started.
        var notes: [String] = []
        if MemoryModel.shared.isPaused, let until = MemoryModel.shared.pausedUntil {
            notes.append("Memory is paused until \(until.formatted(date: .omitted, time: .shortened)); nothing is recorded meanwhile.")
        }
        let first = (try? store.firstCapture()) ?? nil
        if let first, let start = window?.start, start < first {
            notes.append("Memory only has records from \(first.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())); anything earlier was not recorded.")
        } else if first == nil {
            notes.append("Memory has not recorded anything yet.")
        }
        if !notes.isEmpty { out.add("Memory note", notes.joined(separator: " ")) }

        // People and projects the question is about.
        var names = plan.people
        if names.isEmpty, plan.want.contains("person") { names = candidateNames(question) }
        var plan = plan
        for name in names.prefix(4) {
            let entity = ((try? store.findEntity(named: name)) ?? nil) ?? (try? store.entities(.person, matching: name, limit: 1))?.first
            guard let entity, let detail = (try? store.entityDetail(entity.id)) ?? nil else {
                // No card yet: look for the name in what was captured instead.
                if !plan.queries.contains(where: { $0.localizedCaseInsensitiveContains(name) }) { plan.queries.append(name) }
                continue
            }
            out.add("\(entity.type == .person ? "Person" : entity.type.title) · \(entity.name)", describe(detail))
        }

        let chunks: [MemoryStore.Hit] = {
            guard let window, !plan.want.isDisjoint(with: ["contacts", "messages"]) else { return [] }
            let start = window.start ?? now.addingTimeInterval(-30 * 86400)
            return ((try? store.chunks(from: start, to: window.end, limit: 4000)) ?? [])
                .filter { window.contains($0.ts) && filters.matches(app: $0.app, domain: $0.domain, chat: $0.chat, sender: $0.sender) }
        }()
        let segments: [SegmentSummary] = {
            guard let window, let start = window.start, !plan.want.isDisjoint(with: ["activity", "time", "sites"]) else { return [] }
            return ((try? store.segments(from: start, to: window.end, excerptChars: 160, limit: 3000)) ?? [])
                .filter { window.contains($0.started) && filters.matches(app: $0.app, domain: $0.domain, chat: $0.chat, sender: nil) }
        }()

        if plan.want.contains("activity"), let window {
            if filters.isEmpty, window.part == nil {
                for day in window.days.prefix(3) {
                    if let digest = DigestCenter.shared.text(forDay: day) {
                        out.add("Gobbl digest · \(dayLabel(day, day, today: DayParts.dayKey(now, calendar: .current)))", digest)
                    }
                }
            }
            out.add("Activity · \(label)", activity(segments))
        }
        if plan.want.contains("time") { out.add("Screen time · \(label)", screenTime(segments)) }
        if plan.want.contains("contacts") { out.add("Contacts · \(label)\(filters.suffix)", contacts(chunks)) }
        if plan.want.contains("messages") {
            for (source, text) in messages(chunks, fromMe: plan.fromMe, order: plan.order).prefix(4) {
                out.add("Messages · \(source)", text)
            }
        }
        if plan.want.contains("sites") { out.add("Sites · \(label)", sites(segments)) }
        if plan.want.contains("todos") {
            let open = TodoCenter.shared.open.filter { t in
                let keys = plan.people + plan.chats
                return keys.isEmpty || keys.contains { k in
                    t.title.localizedCaseInsensitiveContains(k) || t.people.contains { $0.localizedCaseInsensitiveContains(k) }
                        || (t.chat?.localizedCaseInsensitiveContains(k) ?? false)
                }
            }
            let lines = open.prefix(12).map { t in
                "- \(t.title) (\(t.sourceApp)\(t.chat.map { " · \($0)" } ?? ""))\(t.due.map { ", due \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")"
            }
            out.add("Gobbl to-dos", lines.isEmpty ? "No open to-dos\(plan.people.isEmpty ? "" : " involving \(plan.people.joined(separator: ", "))")." : lines.joined(separator: "\n"))
        }

        // Specific information: the plan's searches, else the question's own words.
        let searching = plan.want.contains("search") || plan.want.contains("when") || !plan.queries.isEmpty
            || (plan.want.isEmpty && out.items.isEmpty)
        if searching {
            var hits: [MemoryStore.Hit] = []
            let queries = plan.queries.isEmpty ? [keywords(question).joined(separator: " ")] : plan.queries
            for q in queries where !q.isEmpty {
                var found = (try? store.search(q, limit: 10, since: window?.start)) ?? []
                if found.isEmpty, q.contains(" ") {
                    // Every word must match in FTS; retry with the most distinctive one.
                    if let word = q.split(separator: " ").max(by: { $0.count < $1.count }) {
                        found = (try? store.search(String(word), limit: 6, since: window?.start)) ?? []
                    }
                }
                hits += found.filter { h in !hits.contains { $0.chunkID == h.chunkID } }
            }
            if hits.count < 3 {
                let semantic = SemanticIndex.shared.search(plan.queries.first ?? question, limit: 6)
                hits += semantic.filter { h in !hits.contains { $0.chunkID == h.chunkID } }
            }
            hits = hits.filter { (window?.contains($0.ts) ?? true) && filters.matches(app: $0.app, domain: $0.domain, chat: $0.chat, sender: $0.sender) }
            if let fromMe = plan.fromMe { hits = hits.filter { $0.fromMe == fromMe } }
            switch plan.order {
            case "latest": hits.sort { $0.ts > $1.ts }
            case "earliest": hits.sort { $0.ts < $1.ts }
            default: break
            }
            for hit in hits.prefix(10) {
                out.add(source(hit), hit.snippet.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
            }
        }

        // Nothing relevant: say exactly what was looked at, so the answer can too.
        let found = out.items.filter { $0["source"] != "Memory note" }
        if found.isEmpty {
            var looked: [String] = []
            if !plan.apps.isEmpty { looked.append("in \(plan.apps.joined(separator: ", "))") }
            if !plan.sites.isEmpty { looked.append("on \(plan.sites.joined(separator: ", "))") }
            if !plan.chats.isEmpty { looked.append("in chats with \(plan.chats.joined(separator: ", "))") }
            if !plan.people.isEmpty { looked.append("about \(plan.people.joined(separator: ", "))") }
            if !plan.queries.isEmpty { looked.append("for \"\(plan.queries.joined(separator: "\", \""))\"") }
            out.add("Memory note", "Searched \(label)\(looked.isEmpty ? "" : " " + looked.joined(separator: " ")): nothing was recorded that matches.")
        }
        return out.items
    }

    // MARK: Filters

    struct Filters {
        var apps: [String]
        var sites: [String]
        var chats: [String]

        init(_ plan: Plan) {
            apps = plan.apps.map { $0.lowercased() }
            sites = plan.sites.map { $0.lowercased() }
            chats = plan.chats.map { $0.lowercased() }
        }

        var isEmpty: Bool { apps.isEmpty && sites.isEmpty && chats.isEmpty }

        var suffix: String {
            let names = apps + sites + chats
            return names.isEmpty ? "" : " · " + names.joined(separator: ", ")
        }

        func matches(app: String, domain: String?, chat: String?, sender: String?) -> Bool {
            if !apps.isEmpty, !apps.contains(app.lowercased()) { return false }
            if !sites.isEmpty {
                guard let d = domain?.lowercased(), sites.contains(where: { d == $0 || d.hasSuffix("." + $0) }) else { return false }
            }
            if !chats.isEmpty {
                let names = [chat, sender].compactMap { $0?.lowercased() }
                guard chats.contains(where: { c in names.contains { $0.contains(c) || c.contains($0) } }) else { return false }
            }
            return true
        }
    }

    // MARK: Summaries

    static func minutes(_ m: Double) -> String {
        let m = Int(m.rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(max(1, m)) min"
    }

    private static func place(_ s: SegmentSummary) -> String {
        "\(s.app) · \(s.chat ?? s.domain ?? String(s.window.prefix(50)))"
    }

    static func activity(_ segments: [SegmentSummary]) -> String {
        var byPlace: [String: (minutes: Double, excerpt: String, last: Date)] = [:]
        for s in segments {
            let key = place(s)
            let cur = byPlace[key] ?? (0, "", s.ended)
            byPlace[key] = (cur.minutes + s.minutes, cur.excerpt.isEmpty ? s.excerpt : cur.excerpt, max(cur.last, s.ended))
        }
        guard !byPlace.isEmpty else { return "" }
        let total = segments.reduce(0) { $0 + $1.minutes }
        let lines = byPlace.sorted { $0.value.minutes > $1.value.minutes }.prefix(14).map { key, v in
            "- \(key): \(minutes(v.minutes)), last \(v.last.formatted(date: .omitted, time: .shortened)). \(v.excerpt.prefix(110))"
        }
        return "Active for about \(minutes(total)) across \(Set(segments.map(\.app)).count) apps.\n" + lines.joined(separator: "\n")
    }

    static func screenTime(_ segments: [SegmentSummary]) -> String {
        guard !segments.isEmpty else { return "" }
        var apps: [String: Double] = [:]
        var sites: [String: Double] = [:]
        var chats: [String: Double] = [:]
        for s in segments {
            apps[s.app, default: 0] += s.minutes
            if let d = s.domain { sites[d, default: 0] += s.minutes }
            if let c = s.chat { chats["\(s.app) · \(c)", default: 0] += s.minutes }
        }
        func lines(_ d: [String: Double], _ n: Int) -> String {
            d.sorted { $0.value > $1.value }.prefix(n).map { "- \($0.key): \(minutes($0.value))" }.joined(separator: "\n")
        }
        var text = "Total about \(minutes(apps.values.reduce(0, +))).\nApps:\n" + lines(apps, 10)
        if !sites.isEmpty { text += "\nSites:\n" + lines(sites, 6) }
        if !chats.isEmpty { text += "\nChats:\n" + lines(chats, 6) }
        return text
    }

    static func contacts(_ chunks: [MemoryStore.Hit]) -> String {
        struct Tally { var count = 0, mine = 0, last = Date.distantPast, senders: Set<String> = [] }
        var byChat: [String: Tally] = [:]
        for c in chunks {
            // Messaging and mail: a chat or a sender. Plain pages are not contacts.
            guard let who = c.chat ?? c.sender, !who.isEmpty else { continue }
            let key = "\(c.app) · \(who)"
            var t = byChat[key] ?? Tally()
            t.count += 1
            if c.fromMe { t.mine += 1 }
            t.last = max(t.last, c.ts)
            if let s = c.sender, !c.fromMe, s != who { t.senders.insert(s) }
            byChat[key] = t
        }
        guard !byChat.isEmpty else { return "" }
        let lines = byChat.sorted { $0.value.count > $1.value.count }.prefix(20).map { key, t in
            var line = "- \(key): \(t.count) message\(t.count == 1 ? "" : "s")"
            if t.mine > 0 { line += " (\(t.mine) from you)" }
            line += ", last \(t.last.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
            if !t.senders.isEmpty { line += "; people: \(t.senders.sorted().prefix(6).joined(separator: ", "))" }
            return line
        }
        return "\(byChat.count) chats or senders.\n" + lines.joined(separator: "\n")
    }

    /// One block per chat, most active first: (source, lines).
    static func messages(_ chunks: [MemoryStore.Hit], fromMe: Bool?, order: String) -> [(String, String)] {
        var byChat: [String: [MemoryStore.Hit]] = [:]
        for c in chunks {
            guard let who = c.chat ?? c.sender else { continue }
            if let fromMe, c.fromMe != fromMe { continue }
            byChat["\(c.app) · \(who)", default: []].append(c)
        }
        return byChat.sorted { $0.value.count > $1.value.count }.map { key, hits in
            // `chunks` is newest first; show a conversation oldest first unless asked for the latest.
            let picked = order == "earliest" ? Array(hits.suffix(14).reversed()) : Array(hits.prefix(14))
            let ordered = order == "latest" ? picked : picked.sorted { $0.ts < $1.ts }
            let lines = ordered.map { h in
                "\(h.ts.formatted(.dateTime.weekday(.abbreviated).hour().minute())) \(h.fromMe ? "me" : (h.sender ?? "them")): \(h.snippet.replacingOccurrences(of: "\n", with: " ").prefix(220))"
            }
            return (key, lines.joined(separator: "\n"))
        }
    }

    static func sites(_ segments: [SegmentSummary]) -> String {
        var byDomain: [String: (minutes: Double, titles: [String])] = [:]
        for s in segments {
            guard let d = s.domain else { continue }
            var v = byDomain[d] ?? (0, [])
            v.minutes += s.minutes
            let title = s.window.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, !v.titles.contains(title), v.titles.count < 4 { v.titles.append(String(title.prefix(70))) }
            byDomain[d] = v
        }
        guard !byDomain.isEmpty else { return "" }
        return byDomain.sorted { $0.value.minutes > $1.value.minutes }.prefix(15).map { d, v in
            "- \(d): \(minutes(v.minutes))\(v.titles.isEmpty ? "" : ". " + v.titles.map { "\"\($0)\"" }.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    // MARK: Fallback without the AI plan

    /// Used when /v1/plan is unreachable: names, to-dos, today's activity, then keyword and meaning search.
    static func heuristicItems(for question: String) -> [[String: String]] {
        var plan = Plan()
        plan.people = candidateNames(question)
        let q = question.lowercased()
        if q.range(of: #"(owe|to-?dos?|pending|promis|follow|open items|left to do)"#, options: .regularExpression) != nil {
            plan.want.insert("todos")
        }
        if q.range(of: #"\b(did i|i did|have i been|was i|do today|done today|worked on|working on|been doing|been up to|my day|recap|summar|how did i spend|where did (my )?time go|what happened)\b"#,
                   options: .regularExpression) != nil {
            plan.want.insert("activity")
            let day = DayParts.dayKey(q.contains("yesterday") ? Date().addingTimeInterval(-86400) : Date(), calendar: .current)
            plan.from = day
            plan.to = day
        }
        if q.range(of: #"\b(talk|talked|chat|chatted|interact|messag|spoke|who (did|have) i)"#, options: .regularExpression) != nil {
            plan.want.insert("contacts")
        }
        plan.want.insert("search")
        guard let store = MemoryModel.shared.store else { return [] }
        return run(plan, question: question, store: store)
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
        if d.summary.mentions30d > 0 { lines.append("Mentioned \(d.summary.mentions30d) times in 30 days, in \(d.summary.apps.prefix(4).joined(separator: ", "))") }
        for fact in d.facts.prefix(5) { lines.append("\(fact.key): \(fact.value)") }
        let related = d.related.prefix(6).map { "\($0.entity.name) (\($0.kind.replacingOccurrences(of: "_", with: " ")))" }
        if !related.isEmpty { lines.append("Connected: " + related.joined(separator: ", ")) }
        let todos = TodoCenter.shared.open.filter { t in t.people.contains { $0.localizedCaseInsensitiveContains(d.summary.name) } }
        for t in todos.prefix(3) { lines.append("Open to-do: \(t.title)") }
        for hit in d.recent.prefix(4) { lines.append("Recent (\(hit.app), \(hit.ts.formatted(.dateTime.weekday(.abbreviated).hour().minute()))): \(hit.snippet.prefix(160))") }
        if !d.notes.isEmpty { lines.append("User's notes: \(d.notes.prefix(200))") }
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
