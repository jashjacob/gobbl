import Foundation

/// Compact markdown for MCP results. Every snippet names where it came from
/// ("WhatsApp · Samar · Sat 6:02 PM") and nothing runs past ~8k characters.
public enum MCPFormat {
    public static let maxChars = 8000

    public static let memoryOff = "Gobbl's Memory isn't on, so there's nothing to look up yet. Turn on Memory in Gobbl (Settings → Memory): it remembers what's on screen, on this Mac only."

    static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String { formatter("h:mm a", calendar).string(from: date) }

    /// "Today 6:02 PM", "Sat 6:02 PM" within the week, "Sat 5 Sep 6:02 PM" further back.
    public static func time(_ date: Date, now: Date, calendar: Calendar) -> String {
        let clock = clock(date, calendar)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(clock)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday \(clock)" }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: t) { return "Tomorrow \(clock)" }
        if abs(date.timeIntervalSince(now)) < 6 * 86400 { return formatter("EEE", calendar).string(from: date) + " " + clock }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return formatter("EEE d MMM", calendar).string(from: date) + " " + clock
        }
        return formatter("d MMM yyyy", calendar).string(from: date) + " " + clock
    }

    public static func dayKey(_ date: Date, calendar: Calendar) -> String { formatter("yyyy-MM-dd", calendar).string(from: date) }
    public static func dayTitle(_ date: Date, calendar: Calendar) -> String { formatter("EEEE d MMMM yyyy", calendar).string(from: date) }

    /// "WhatsApp · Samar · Sat 6:02 PM"
    public static func source(_ hit: MemoryStore.Hit, now: Date, calendar: Calendar) -> String {
        var parts = [hit.app.isEmpty ? "Unknown app" : hit.app]
        if let place = place(chat: hit.chat, domain: hit.domain, window: hit.window), place != hit.app { parts.append(oneLine(place, 60)) }
        parts.append(time(hit.ts, now: now, calendar: calendar))
        return parts.joined(separator: " · ")
    }

    static func place(chat: String?, domain: String?, window: String) -> String? {
        if let chat, !chat.isEmpty { return chat }
        if let domain, !domain.isEmpty { return domain }
        return window.isEmpty ? nil : window
    }

    static func speaker(_ hit: MemoryStore.Hit) -> String {
        if hit.fromMe { return "You: " }
        if let sender = hit.sender, !sender.isEmpty, sender != hit.chat { return sender + ": " }
        return ""
    }

    static func oneLine(_ s: String, _ max: Int) -> String {
        let collapsed = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > max ? String(collapsed.prefix(max - 1)) + "…" : collapsed
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 1 { return "<1 min" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h" + (m % 60 > 0 ? " \(m % 60) min" : "")
    }

    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) \(n == 1 ? one : many ?? one + "s")" }

    /// Cuts at a line break near the limit and says so.
    public static func cap(_ text: String, limit: Int = maxChars) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let end = cut.lastIndex(of: "\n") ?? cut.endIndex
        return String(cut[..<end]) + "\n\n… more was cut to keep this short. Narrow it down (a date, app or person) to see the rest."
    }

    /// "today", "yesterday", "now", 2026-09-14, or ISO 8601 with or without an offset (local time without).
    /// A bare date means its start, or with `endOfDay` the start of the next day.
    public static func parseDate(_ input: String, endOfDay: Bool, now: Date, calendar: Calendar) -> Date? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func day(_ d: Date) -> Date {
            let start = calendar.startOfDay(for: d)
            return endOfDay ? calendar.date(byAdding: .day, value: 1, to: start) ?? start : start
        }
        switch s.lowercased() {
        case "now": return now
        case "today": return day(now)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: now).map(day)
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: now).map(day)
        default: break
        }
        if s.count == 10, let d = formatter("yyyy-MM-dd", calendar).date(from: s) { return day(d) }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = options
            if let d = iso.date(from: s) { return d }
        }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            if let d = formatter(format, calendar).date(from: s) { return d }
        }
        return nil
    }

    // MARK: Results

    public static func hits(_ hits: [MemoryStore.Hit], title: String, now: Date, calendar: Calendar) -> String {
        var out = title + "\n"
        for (n, h) in hits.enumerated() {
            out += "\n\(n + 1). \(source(h, now: now, calendar: calendar))\n   \(speaker(h))\(oneLine(h.snippet, 400))\n"
        }
        return out
    }

    public static func digests(_ parts: [MemoryDigestPart], title: String) -> String {
        var out = "\(title), from Gobbl's summaries:\n"
        for p in parts {
            out += "\n## \(p.part.capitalized)\n"
            for b in p.bullets { out += "- \(oneLine(b, 300))\n" }
            if !p.apps.isEmpty { out += "Apps: \(p.apps.joined(separator: ", "))\n" }
        }
        return out
    }

    /// No summary for the day: apps by time spent, each with its busiest windows.
    public static func day(_ segments: [MemoryActivity], title: String, calendar: Calendar) -> String {
        struct Group { var total: TimeInterval = 0; var first: Date; var last: Date; var places: [String: TimeInterval] = [:] }
        var groups: [String: Group] = [:]
        for s in segments {
            let length = max(s.ended.timeIntervalSince(s.started), 30)
            var g = groups[s.app] ?? Group(first: s.started, last: s.ended)
            g.total += length
            g.first = min(g.first, s.started)
            g.last = max(g.last, s.ended)
            if let place = place(chat: s.chat, domain: s.domain, window: s.window) { g.places[place, default: 0] += length }
            groups[s.app] = g
        }
        let sorted = groups.sorted { $0.value.total > $1.value.total }
        let first = segments.map(\.started).min() ?? Date(), last = segments.map(\.ended).max() ?? Date()
        var out = "\(title): \(plural(sorted.count, "app")), \(clock(first, calendar)) to \(clock(last, calendar)). No summary for this day, so here are the windows used.\n"
        for (app, g) in sorted.prefix(20) {
            out += "\n## \(app.isEmpty ? "Unknown app" : app): \(duration(g.total)) (\(clock(g.first, calendar))–\(clock(g.last, calendar)))\n"
            for (place, length) in g.places.sorted(by: { $0.value > $1.value }).prefix(6) {
                out += "- \(oneLine(place, 80)) (\(duration(length)))\n"
            }
        }
        return out
    }

    public static func timeline(_ segments: [MemoryActivity], hours: Int, now: Date, calendar: Calendar) -> String {
        var out = "Last \(hours) h, newest first (\(plural(segments.count, "window"))):\n"
        for s in segments.reversed().prefix(60) {
            var line = "\n\(time(s.started, now: now, calendar: calendar))–\(clock(s.ended, calendar)) · \(s.app)"
            if let place = place(chat: s.chat, domain: s.domain, window: s.window), place != s.app { line += " · \(oneLine(place, 60))" }
            out += line + " (\(duration(s.ended.timeIntervalSince(s.started))))\n"
            if !s.excerpt.isEmpty { out += "   \(oneLine(s.excerpt, 200))\n" }
        }
        return out
    }

    public static func todos(_ todos: [MemoryTodo], label: String, now: Date, calendar: Calendar) -> String {
        var out = "\(plural(todos.count, "to-do")) (\(label)):\n"
        for t in todos {
            out += "\n- #\(t.id) \(oneLine(t.title, 160))"
            if let due = t.due { out += " (due \(time(due, now: now, calendar: calendar)))" }
            var meta = [t.status.rawValue.replacingOccurrences(of: "_", with: " ")]
            if !t.sourceApp.isEmpty { meta.append("from " + t.sourceApp + (t.chat.map { " · \($0)" } ?? "")) }
            if !t.people.isEmpty { meta.append("with " + t.people.joined(separator: ", ")) }
            meta.append("last seen " + time(t.lastEvidence, now: now, calendar: calendar))
            out += "\n  " + meta.joined(separator: " · ")
            if !t.reason.isEmpty { out += "\n  Why: \(oneLine(t.reason, 200))" }
            out += "\n"
        }
        return out
    }

    public static func entity(_ d: EntityDetail, now: Date, calendar: Calendar) -> String {
        let s = d.summary
        var out = "# \(s.name) (\(s.type.rawValue), id \(s.id))\n"
        if s.role != nil || s.org != nil {
            out += [s.role, s.org].compactMap { $0 }.joined(separator: " at ") + "\n"
        }
        if !d.description.isEmpty { out += oneLine(d.description, 400) + "\n" }
        let others = d.aliases.filter { EntityRules.normalize($0) != EntityRules.normalize(s.name) }
        if !others.isEmpty { out += "Also called: \(others.prefix(8).joined(separator: ", "))\n" }
        if !d.identifiers.isEmpty { out += "Contact: " + d.identifiers.map { "\($0.type) \($0.value)" }.joined(separator: ", ") + "\n" }
        var seen: [String] = []
        if !s.apps.isEmpty { seen.append("in " + s.apps.joined(separator: ", ")) }
        seen.append(plural(s.mentions30d, "mention") + " in 30 days")
        if let last = s.lastSeen { seen.append("last seen " + time(last, now: now, calendar: calendar)) }
        out += "Seen " + seen.joined(separator: " · ") + "\n"
        if !d.notes.isEmpty { out += "Notes: \(oneLine(d.notes, 600))\n" }
        if !d.facts.isEmpty {
            out += "\nFacts:\n" + d.facts.map { "- \($0.key): \(oneLine($0.value, 200))" }.joined(separator: "\n") + "\n"
        }
        if !d.related.isEmpty {
            out += "\nRelated:\n" + d.related.prefix(12).map { "- \($0.entity.name) (\($0.entity.type.rawValue), \($0.kind.replacingOccurrences(of: "_", with: " ")), id \($0.entity.id))" }
                .joined(separator: "\n") + "\n"
        }
        if !d.recent.isEmpty {
            out += "\nRecent:\n"
            for h in d.recent.prefix(8) { out += "- \(source(h, now: now, calendar: calendar))\n  \(speaker(h))\(oneLine(h.snippet, 240))\n" }
        }
        return out
    }

    /// Items from the app: kind, text, date (seconds since 1970), app.
    public static func clipboard(_ items: [[String: Any]], now: Date, calendar: Calendar) -> String {
        var out = "\(plural(items.count, "clipboard item")), newest first:\n"
        for (n, item) in items.enumerated() {
            let kind = item["kind"] as? String ?? "text"
            var meta = [kind]
            if let app = item["app"] as? String, !app.isEmpty { meta.append(app) }
            if let ts = item["date"] as? Double { meta.append(time(Date(timeIntervalSince1970: ts), now: now, calendar: calendar)) }
            if item["pinned"] as? Bool == true { meta.append("pinned") }
            let text = item["text"] as? String ?? ""
            let body: String
            switch kind {
            case "image": body = "(an image)"
            case "file": body = text.split(separator: "\n").joined(separator: ", ")
            default: body = oneLine(text, 600)
            }
            out += "\n\(n + 1). \(meta.joined(separator: " · "))\n   \(body)\n"
        }
        return out
    }
}
