import Foundation

public enum EntityType: String, Codable, CaseIterable, Sendable {
    case person, project, org, topic, tool

    public var title: String {
        switch self {
        case .person: "People"
        case .project: "Projects"
        case .org: "Organisations"
        case .topic: "Topics"
        case .tool: "Tools"
        }
    }
}

public struct EntitySummary: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var type: EntityType
    public var name: String
    public var role: String?
    public var org: String?
    public var lastSeen: Date?
    public var mentions30d: Int
    public var apps: [String]
    public var pinned: Bool
}

public struct EntityDetail: Equatable, Sendable {
    public var summary: EntitySummary
    public var aliases: [String]
    public var identifiers: [(type: String, value: String)]
    public var facts: [(key: String, value: String)]
    public var related: [(entity: EntitySummary, kind: String)]
    public var recent: [MemoryStore.Hit]
    public var notes: String
    public var description: String

    public static func == (a: EntityDetail, b: EntityDetail) -> Bool {
        a.summary == b.summary && a.aliases == b.aliases && a.notes == b.notes && a.recent == b.recent
    }
}

public struct MergeSuggestion: Identifiable, Equatable, Sendable {
    public var id: String { "\(a.id)-\(b.id)" }
    public var a: EntitySummary
    public var b: EntitySummary
    public var reason: String
}

/// Name handling for the knowledge base. Automatic merges happen only on a
/// hard match (same email, phone or handle, or the exact same name); anything
/// softer becomes a "Same person?" question the user answers.
public enum EntityRules {
    /// Lowercased, accents and punctuation removed, single spaces.
    public static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static let genericNames: Set<String> = [
        "you", "me", "team", "everyone", "all", "admin", "support", "unknown", "whatsapp", "telegram", "slack", "teams",
        "group", "channel", "general", "bot", "system", "notification", "notifications", "someone", "user", "customer",
    ]

    /// Too generic to be a person or project worth a card.
    public static func isNoise(_ name: String) -> Bool {
        let n = normalize(name)
        return n.count < 2 || genericNames.contains(n) || n.allSatisfy(\.isNumber)
    }

    /// "Samar" and "Samar Mustafa", or "S Mustafa" and "Samar Mustafa": maybe
    /// the same person. Returns the reason to show, or nil.
    public static func mightBeSame(_ a: String, _ b: String) -> String? {
        let x = normalize(a).split(separator: " ").map(String.init)
        let y = normalize(b).split(separator: " ").map(String.init)
        guard !x.isEmpty, !y.isEmpty, x != y else { return nil }
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        if short.count < long.count, short.first == long.first, Set(short).isSubset(of: Set(long)), short[0].count >= 3 {
            return "\"\(short.joined(separator: " ").capitalized)\" could be short for \"\(long.joined(separator: " ").capitalized)\""
        }
        if short.count == long.count, short.count >= 2, short.last == long.last,
           let s = short.first, let l = long.first, s.count == 1 || l.count == 1, s.first == l.first {
            return "Same surname and initial"
        }
        return nil
    }
}
