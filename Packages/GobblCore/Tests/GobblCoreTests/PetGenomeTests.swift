import Testing
@testable import GobblCore

@Suite struct PetGenomeTests {
    @Test func weightsSumToOneHundred() {
        #expect(Species.allCases.map(\.weight).reduce(0, +) == 100)
    }

    @Test func hatchIsDeterministic() {
        for seed: UInt64 in [0, 1, 42, .max] {
            #expect(PetGenome.hatch(seed: seed) == PetGenome.hatch(seed: seed))
        }
    }

    @Test func distributionRoughlyMatchesWeights() {
        let n = 100_000
        var counts: [Species: Int] = [:]
        var shiny = 0
        for seed in 0..<UInt64(n) {
            let g = PetGenome.hatch(seed: seed &* 0x2545_F491_4F6C_DD1D)
            counts[g.species, default: 0] += 1
            if g.shiny { shiny += 1 }
        }
        for s in Species.allCases {
            let share = Double(counts[s, default: 0]) / Double(n) * 100
            #expect(abs(share - Double(s.weight)) < 1, "\(s): \(share)%")
        }
        #expect((700...1300).contains(shiny), "shiny: \(shiny)")
    }

    @Test func shinyIsAtLeastRare() {
        #expect(PetGenome(seed: 0, species: .mochi, shiny: true).rarity == .rare)
        #expect(PetGenome(seed: 0, species: .cosmo, shiny: true).rarity == .legendary)
        #expect(PetGenome(seed: 0, species: .mochi, shiny: false).rarity == .common)
    }
}
