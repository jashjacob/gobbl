import Foundation
import Testing
@testable import GobblCore

@Suite struct PetSkinTests {
    @Test func hexRoundTrip() {
        let c = PetSkin.rgb("#FF8000")
        #expect(c?.r == 1)
        #expect(c?.b == 0)
        #expect(PetSkin.hex(r: 1, g: 0.5, b: 0) == "#FF8000")
        #expect(PetSkin.rgb("12345") == nil)
        #expect(PetSkin.rgb("#GGGGGG") == nil)
    }

    @Test func decodesASharedFile() throws {
        let json = ##"{"format":1,"id":"","name":"  Mint Chip! ","bodyTop":"#D2FAE3","bodyBottom":"6FD39B","face":"#2B1B12"}"##
        let skin = try PetSkin.decode(Data(json.utf8))
        #expect(skin.name == "Mint Chip!")
        #expect(skin.id == "mint-chip")
        #expect(skin.glow == nil)
    }

    @Test func rejectsBadFiles() {
        #expect(throws: PetSkin.SkinError.self) {
            try PetSkin.decode(Data(##"{"id":"x","name":"x","bodyTop":"red","bodyBottom":"#000000"}"##.utf8))
        }
        #expect(throws: PetSkin.SkinError.self) {
            try PetSkin.decode(Data(##"{"id":"x","name":"","bodyTop":"#000000","bodyBottom":"#000000"}"##.utf8))
        }
        #expect(throws: PetSkin.SkinError.self) {
            try PetSkin.decode(Data(##"{"format":99,"id":"x","name":"x","bodyTop":"#000000","bodyBottom":"#000000"}"##.utf8))
        }
    }

    @Test func slugIsAFileSafeName() {
        #expect(PetSkin.slug("../../etc/passwd") == "etc-passwd")
        #expect(PetSkin.slug("Été 🌞") == "t")
        #expect(PetSkin.slug("!!!") == "skin")
    }

    @Test func builtInsAreValidAndUnique() throws {
        for skin in PetSkin.builtIn { _ = try skin.validated() }
        #expect(Set(PetSkin.builtIn.map(\.id)).count == PetSkin.builtIn.count)
    }

    @Test func encodeDecodeRoundTrip() throws {
        let skin = PetSkin.builtIn[0]
        #expect(try PetSkin.decode(skin.encoded()) == skin)
    }
}
