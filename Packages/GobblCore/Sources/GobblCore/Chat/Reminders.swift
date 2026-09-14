import Foundation

public struct Reminder: Identifiable, Codable, Equatable, Sendable {
    public enum Repeat: Codable, Equatable, Sendable {
        case daily
        case weekdays
        /// 1 = Sunday … 7 = Saturday, as `Calendar` numbers them.
        case weekly(weekday: Int)

        public func matches(_ weekday: Int) -> Bool {
            switch self {
            case .daily: true
            case .weekdays: (2...6).contains(weekday)
            case .weekly(let w): w == weekday
            }
        }

        public var label: String {
            switch self {
            case .daily: "Every day"
            case .weekdays: "Every weekday"
            case .weekly(let w): "Every " + DateFormatter().weekdaySymbols[(w - 1 + 7) % 7]
            }
        }
    }

    public var id: UUID
    public var text: String
    public var due: Date
    public var repeats: Repeat?
    public var done: Bool

    public init(id: UUID = UUID(), text: String, due: Date, repeats: Repeat? = nil, done: Bool = false) {
        self.id = id
        self.text = text
        self.due = due
        self.repeats = repeats
        self.done = done
    }

    /// When a repeating reminder next comes round after `date`, at the same time of day.
    public func nextOccurrence(after date: Date, calendar: Calendar) -> Date? {
        guard let repeats else { return nil }
        let time = calendar.dateComponents([.hour, .minute], from: due)
        var day = calendar.startOfDay(for: date)
        for _ in 0..<15 {
            if let candidate = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day),
               candidate > date, repeats.matches(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}

/// Turns "remind me at 3 to call Sara", "in 20 minutes", "tomorrow at 9",
/// "every weekday at 10", "on friday at 4:30pm" into a reminder, on the Mac,
/// with no AI call.
public enum ReminderParser {
    public enum Result: Equatable, Sendable {
        case reminder(Reminder)
        /// "remind me to buy milk": we know what, not when.
        case needsTime(String)
    }

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "ten": 10, "fifteen": 15,
        "twenty": 20, "thirty": 30, "forty-five": 45, "fortyfive": 45, "half a": 0.5, "half an": 0.5,
    ]

    public static func parse(_ input: String, now: Date, calendar: Calendar = .current) -> Result? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard take(#"^(?:please\s+)?(?:can you\s+)?(?:remind me|set a reminder|reminder)\b[:,]?"#, from: &s) != nil else { return nil }

        var relative: TimeInterval?
        var hour: Int?
        var minute = 0
        var meridiem: String?
        var dayOffset: Int?
        var tonight = false
        var weekday: Int?
        var repeats: Reminder.Repeat?
        var partHour: Int?

        if let g = take(#"\bin\s+(\d+|an?|one|two|three|four|five|ten|fifteen|twenty|thirty|forty-?five|half an?)\s*(minutes?|mins?|hours?|hrs?)\b"#, from: &s) {
            let amount = Double(g[1] ?? "") ?? numberWords[(g[1] ?? "").lowercased().replacingOccurrences(of: "-", with: "")] ?? numberWords[(g[1] ?? "").lowercased()] ?? 1
            let unit: Double = (g[2] ?? "").lowercased().hasPrefix("h") ? 3600 : 60
            relative = amount * unit
        }
        if let g = take(#"\bevery\s+(day|weekday|morning|evening|night|sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?\b"#, from: &s) {
            switch (g[1] ?? "").lowercased() {
            case "day": repeats = .daily
            case "weekday": repeats = .weekdays
            case "morning": repeats = .daily; partHour = 9
            case "evening": repeats = .daily; partHour = 18
            case "night": repeats = .daily; partHour = 21
            case let name: repeats = .weekly(weekday: (weekdays.firstIndex(of: name) ?? 1) + 1)
            }
        } else if take(#"\b(?:daily|every single day)\b"#, from: &s) != nil {
            repeats = .daily
        } else if take(#"\bon weekdays\b"#, from: &s) != nil {
            repeats = .weekdays
        }
        if let g = take(#"\bat\s+(noon|midnight|(\d{1,2})(?:[:.](\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?)(?=\W|$)"#, from: &s)
            ?? take(#"\b()(\d{1,2})(?:[:.](\d{2}))?\s*(a\.?m\.?|p\.?m\.?)(?=\W|$)"#, from: &s) {
            switch (g[1] ?? "").lowercased() {
            case "noon": hour = 12; meridiem = "pm"
            case "midnight": hour = 0; meridiem = "am"
            default:
                hour = Int(g[2] ?? "")
                minute = Int(g[3] ?? "") ?? 0
                meridiem = g[4]?.lowercased()
            }
        }
        if let g = take(#"\b(today|tonight|tomorrow)\b"#, from: &s) {
            switch (g[1] ?? "").lowercased() {
            case "tomorrow": dayOffset = 1
            case "tonight": dayOffset = 0; tonight = true; partHour = partHour ?? 20
            default: dayOffset = 0
            }
        }
        if let g = take(#"\b(?:on\s+|next\s+|this\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#, from: &s) {
            weekday = (weekdays.firstIndex(of: (g[1] ?? "").lowercased()) ?? 1) + 1
        }
        if let g = take(#"\b(?:in the\s+|this\s+)?(morning|afternoon|evening)\b"#, from: &s) {
            partHour = ["morning": 9, "afternoon": 14, "evening": 18][(g[1] ?? "").lowercased()]
        }

        let task = cleanTask(s)
        guard relative != nil || hour != nil || dayOffset != nil || weekday != nil || repeats != nil || partHour != nil else {
            return .needsTime(task)
        }

        if let relative {
            return .reminder(Reminder(text: task, due: now.addingTimeInterval(relative)))
        }

        // The hour, in 24h, and whether it's unambiguous.
        var h = hour ?? partHour ?? 9
        var exact = meridiem != nil || hour == nil || h >= 13 || h == 0
        if let meridiem {
            if meridiem.hasPrefix("p"), h < 12 { h += 12 }
            if meridiem.hasPrefix("a"), h == 12 { h = 0 }
        } else if tonight, h < 12 {
            h += 12
            exact = true
        }

        if let repeats {
            // "every weekday at 3" means the afternoon.
            if !exact, (1...6).contains(h) { h += 12 }
            let template = Reminder(text: task, due: calendar.date(bySettingHour: h, minute: minute, second: 0, of: now) ?? now, repeats: repeats)
            guard let first = template.nextOccurrence(after: now, calendar: calendar) else { return nil }
            return .reminder(Reminder(text: task, due: first, repeats: repeats))
        }

        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, on day: Date) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }

        if weekday != nil || (dayOffset ?? 0) > 0 {
            var day = calendar.date(byAdding: .day, value: dayOffset ?? 0, to: today) ?? today
            if let weekday {
                day = today
                for _ in 0..<8 {
                    if calendar.component(.weekday, from: day) == weekday, let d = at(h, on: day), d > now { break }
                    day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                }
            }
            if !exact, (1...6).contains(h) { h += 12 }
            guard let due = at(h, on: day) else { return nil }
            return .reminder(Reminder(text: task, due: due))
        }

        // Today (or unspecified): the next time that hour comes round.
        let candidates = exact || h >= 12 ? [h] : [h, h + 12]
        if let due = candidates.compactMap({ at($0, on: today) }).first(where: { $0 > now }) {
            return .reminder(Reminder(text: task, due: due))
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        guard let due = at(candidates[0], on: tomorrow) else { return nil }
        return .reminder(Reminder(text: task, due: due))
    }

    private static func cleanTask(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        t = t.replacingOccurrences(of: #"^(?:to|that|about|i need to|i have to|i should)\s+"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"[\s.!?,]+$"#, with: "", options: .regularExpression)
        guard let first = t.first else { return "Reminder" }
        return first.uppercased() + t.dropFirst()
    }

    /// Finds the first match, removes it from `s`, and returns its groups (0 = the whole match).
    private static func take(_ pattern: String, from s: inout String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let groups = (0..<m.numberOfRanges).map { i -> String? in
            let r = m.range(at: i)
            return r.location == NSNotFound || r.length == 0 ? nil : ns.substring(with: r)
        }
        s = ns.replacingCharacters(in: m.range, with: " ")
        return groups
    }
}
