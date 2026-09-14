import Foundation

/// A to-do Gobbl noticed (or the user added). Extracted ones start as
/// suggestions; nothing becomes confirmed without the user.
public struct MemoryTodo: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case suggested, maybe, confirmed, snoozed, done, autoDone = "auto_done", dismissed, stale
        public var isOpen: Bool { [.suggested, .maybe, .confirmed, .snoozed].contains(self) }
    }

    public struct DoneSignal: Codable, Equatable, Sendable {
        /// reply_to | page_contains | message_sent | file_sent | none
        public var type: String
        /// "|"-separated phrases, matched case-insensitively.
        public var pattern: String

        public init(type: String, pattern: String) {
            self.type = type
            self.pattern = pattern
        }
    }

    public var id: Int64 = 0
    public var title: String
    public var reason: String
    public var status: Status
    public var confidence: Double
    public var sourceApp: String
    public var window: String
    public var chat: String?
    public var domain: String?
    public var people: [String]
    public var firstSeen: Date
    public var lastEvidence: Date
    public var due: Date?
    public var doneSignal: DoneSignal?
    public var resolvedAt: Date?
    /// "user" or "auto".
    public var resolvedBy: String?
    public var snoozedUntil: Date?
    public var dismissReason: String?
    /// Status before an automatic change, so Undo can put it back.
    public var previousStatus: Status?
    public var dedupeKey: String

    public init(title: String, reason: String, status: Status, confidence: Double, sourceApp: String, window: String,
                chat: String? = nil, domain: String? = nil, people: [String] = [], firstSeen: Date, due: Date? = nil,
                doneSignal: DoneSignal? = nil) {
        self.title = title
        self.reason = reason
        self.status = status
        self.confidence = confidence
        self.sourceApp = sourceApp
        self.window = window
        self.chat = chat
        self.domain = domain
        self.people = people
        self.firstSeen = firstSeen
        self.lastEvidence = firstSeen
        self.due = due
        self.doneSignal = doneSignal
        self.dedupeKey = TodoRules.dedupeKey(title: title, people: people)
    }
}

/// Something newly seen on screen, checked against open to-dos' done signals.
public struct TodoObservation: Sendable {
    public var text: String
    public var domain: String?
    public var chat: String?
    public var fromMe: Bool
    public var kind: String

    public init(text: String, domain: String?, chat: String?, fromMe: Bool, kind: String) {
        self.text = text
        self.domain = domain
        self.chat = chat
        self.fromMe = fromMe
        self.kind = kind
    }
}

public enum TodoSensitivity: String, CaseIterable, Codable, Sendable {
    case conservative, balanced, eager
    var shift: Double {
        switch self {
        case .conservative: 0.08
        case .balanced: 0
        case .eager: -0.1
        }
    }
}

public enum TodoRules {
    /// ≥0.8 is a suggestion, 0.5–0.8 a "maybe" for the brief, below that nothing.
    public static func initialStatus(confidence: Double, sensitivity: TodoSensitivity = .balanced) -> MemoryTodo.Status? {
        if confidence >= 0.8 + sensitivity.shift { return .suggested }
        if confidence >= 0.5 + sensitivity.shift { return .maybe }
        return nil
    }

    static let stopWords: Set<String> = [
        "the", "a", "an", "to", "for", "of", "on", "in", "and", "with", "my", "your", "about", "by", "at", "from", "up",
        "out", "this", "that", "it", "is", "be", "get", "make",
    ]

    static func words(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    public static func dedupeKey(title: String, people: [String]) -> String {
        (words(title).prefix(6) + people.map { $0.lowercased() }.sorted()).joined(separator: " ")
    }

    /// Same task seen again: identical key, or mostly the same words (fewer
    /// needed when it's the same person or place), within a week.
    public static func isDuplicate(_ new: MemoryTodo, of old: MemoryTodo) -> Bool {
        if new.dedupeKey == old.dedupeKey { return true }
        guard abs(new.firstSeen.timeIntervalSince(old.lastEvidence)) < 7 * 86400 else { return false }
        let a = Set(words(new.title)), b = Set(words(old.title))
        guard !a.isEmpty, !b.isEmpty else { return false }
        let overlap = Double(a.intersection(b).count) / Double(a.union(b).count)
        let sharedPerson = !Set(new.people.map { $0.lowercased() }).isDisjoint(with: old.people.map { $0.lowercased() })
        let sameSource = (new.domain != nil && new.domain == old.domain) || (new.chat != nil && new.chat == old.chat)
        return overlap >= 0.6 || (overlap >= 0.34 && (sharedPerson || sameSource))
    }

    /// Whether `observation` is the proof that `todo` got done.
    public static func resolves(_ todo: MemoryTodo, _ o: TodoObservation) -> Bool {
        guard todo.status.isOpen, let signal = todo.doneSignal, signal.type != "none" else { return false }
        let phrases = signal.pattern.lowercased().split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 }
        let text = o.text.lowercased()
        let phraseHit = phrases.contains { text.contains($0) }
        switch signal.type {
        case "page_contains":
            return phraseHit && (todo.domain == nil || o.domain == todo.domain)
        case "reply_to":
            guard o.fromMe, o.kind == "message", let chat = o.chat else { return false }
            return chat == todo.chat || todo.people.contains { chat.localizedCaseInsensitiveContains($0) }
        case "message_sent":
            return o.fromMe && (phrases.isEmpty || phraseHit) && (todo.chat == nil || o.chat == todo.chat)
        case "file_sent":
            let file = text.range(of: #"\.(pdf|docx?|pptx?|xlsx?|key|pages|numbers|zip|png|jpe?g)\b"#, options: .regularExpression) != nil
            return o.fromMe && file && (phrases.isEmpty || phraseHit || (todo.chat != nil && o.chat == todo.chat))
        default:
            return false
        }
    }

    /// Open with no new evidence for a week and nothing due ahead.
    public static func isStale(_ todo: MemoryTodo, now: Date) -> Bool {
        guard [.suggested, .maybe, .confirmed].contains(todo.status), now.timeIntervalSince(todo.lastEvidence) > 7 * 86400 else { return false }
        if let due = todo.due, due > now { return false }
        return true
    }

    /// Order for showing: due soonest, then confirmed before suggested, then confidence.
    public static func sorted(_ todos: [MemoryTodo]) -> [MemoryTodo] {
        todos.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if (a.status == .confirmed) != (b.status == .confirmed) { return a.status == .confirmed }
            return a.confidence > b.confidence
        }
    }
}

/// Which captured text is worth sending to the AI for to-dos and people.
/// Keeps costs down and keeps most of the screen on the Mac.
public enum ExtractionFilter {
    static let flowWords = [
        "checkout", "payment", "pay now", "booking", "book now", "reserve", "your cart", "order summary", "application",
        "submit", "invoice", "proceed to pay", "amount to be paid", "confirm your", "complete your",
    ]
    static let newsDomains = ["news", "reddit.com", "x.com", "twitter.com", "youtube.com", "instagram.com", "facebook.com", "linkedin.com/feed"]
    static let intent = try! NSRegularExpression(pattern: #"(?i)\b(todo|to-do|to do|remind|deadline|due|by (?:mon|tues|wednes|thurs|fri|satur|sun)day|by tomorrow|by eod|asap|follow[ -]up|can you|could you|please|i'll|i will|will send|let me know|action item|don't forget)\b"#)

    public static func isCandidate(appKind: CaptureAppKind, domain: String?, text: String) -> Bool {
        switch appKind {
        case .code, .terminal:
            return text.contains("TODO:")
        case .messaging, .mail:
            return true
        case .browser:
            if let domain, newsDomains.contains(where: { domain.contains($0) }) { return false }
            return hasFlow(text) || hasIntent(text)
        case .generic:
            return hasIntent(text) || hasFlow(text)
        }
    }

    static func hasFlow(_ text: String) -> Bool {
        let lower = text.lowercased()
        return flowWords.contains { lower.contains($0) }
    }

    static func hasIntent(_ text: String) -> Bool {
        intent.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
