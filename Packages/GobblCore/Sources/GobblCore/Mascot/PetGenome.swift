import Foundation

public enum Rarity: String, Codable, Sendable, Comparable {
    case common, uncommon, rare, legendary

    private var rank: Int {
        switch self {
        case .common: 0
        case .uncommon: 1
        case .rare: 2
        case .legendary: 3
        }
    }

    public static func < (a: Rarity, b: Rarity) -> Bool { a.rank < b.rank }
}

/// What hatches from the egg. Every user gets a random one, which is the
/// point: people post screenshots of what they got.
public enum Species: String, Codable, CaseIterable, Sendable {
    case mochi, sprout, ember, frost, bubble, sunny, plum, cosmo

    /// Hatch weight out of 100.
    public var weight: Int {
        switch self {
        case .mochi: 20
        case .sprout: 18
        case .ember: 16
        case .frost: 16
        case .bubble: 14
        case .sunny: 10
        case .plum: 5
        case .cosmo: 1
        }
    }

    public var rarity: Rarity {
        switch weight {
        case 14...: .common
        case 10...: .uncommon
        case 5...: .rare
        default: .legendary
        }
    }

    /// Body hue, 0–1.
    public var hue: Double {
        switch self {
        case .mochi: 0.93
        case .sprout: 0.30
        case .ember: 0.04
        case .frost: 0.55
        case .bubble: 0.48
        case .sunny: 0.13
        case .plum: 0.78
        case .cosmo: 0.68
        }
    }

    public var displayName: String { rawValue.capitalized }
}

/// Gob's genes: fixed at hatch, derived deterministically from a seed.
public struct PetGenome: Codable, Equatable, Sendable {
    public static let shinyOdds: UInt64 = 100

    public var seed: UInt64
    public var species: Species
    /// 1 in 100: sparkles.
    public var shiny: Bool

    public init(seed: UInt64, species: Species, shiny: Bool) {
        self.seed = seed
        self.species = species
        self.shiny = shiny
    }

    public static func hatch(seed: UInt64) -> PetGenome {
        var rng = SplitMix64(seed: seed)
        var roll = Int(rng.next() % 100)
        var species = Species.mochi
        for s in Species.allCases {
            if roll < s.weight { species = s; break }
            roll -= s.weight
        }
        return PetGenome(seed: seed, species: species, shiny: rng.next() % shinyOdds == 0)
    }

    public var rarity: Rarity { shiny ? max(species.rarity, .rare) : species.rarity }
}

public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
