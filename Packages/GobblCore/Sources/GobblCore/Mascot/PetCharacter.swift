/// Which computer the pet is. All share every mood, hat and colour; only the
/// case differs. Era archetypes, deliberately generic: no maker's logo or
/// exact product silhouette.
public enum PetCharacter: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Late-70s home computer: a keyboard base with a boxy monitor on top.
    case classic
    /// Mid-80s compact all-in-one: CRT above a floppy slot.
    case retro
    /// Late-90s bubble computer in candy colours.
    case candy

    public static let defaultCharacter = PetCharacter.retro

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: "Classic"
        case .retro: "Compact"
        case .candy: "Candy"
        }
    }

    public var era: String {
        switch self {
        case .classic: "Late-70s home computer"
        case .retro: "Mid-80s all-in-one"
        case .candy: "Late-90s bubble computer"
        }
    }
}

/// What connected AI agents are doing, as far as Gob's face is concerned.
public enum AgentActivity: String, Sendable {
    case idle
    /// Between a prompt and the next tool call: the model is reasoning.
    case thinking
    /// Running tools: editing files, running commands.
    case coding
}
