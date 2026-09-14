import Foundation
import Testing
@testable import GobblCore

@Suite struct MemoryVectorTests {
    @Test func nearestRanksByCosineAndForgetsWithChunks() throws {
        let db = try MemoryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-vec-\(UUID().uuidString).sqlite"))
        let t = Date()
        let seg = try db.beginSegment(appBundle: "com.apple.Notes", appName: "Notes", window: "n", url: nil, chat: nil, at: t)
        try db.addChunks(segment: seg, [
            .init(ts: t, kind: "text", text: "Booked flights to Edinburgh for the trip"),
            .init(ts: t, kind: "text", text: "Quarterly revenue numbers for the board deck"),
            .init(ts: t, kind: "text", text: "short"),
        ])
        let needing = try db.chunksNeedingVectors()
        #expect(needing.count == 2) // "short" is under 20 characters

        // Toy 3-d "embeddings": travel, finance, other.
        try db.setVector(.chunk, ref: needing[0].id, [0.9, 0.1, 0])
        try db.setVector(.chunk, ref: needing[1].id, [0.1, 0.95, 0.1])
        try db.setVector(.todo, ref: 42, [0.8, 0.2, 0])
        #expect(try db.chunksNeedingVectors().isEmpty)

        let travel = try db.nearest([1, 0, 0], kinds: [.chunk])
        #expect(travel.first?.ref == needing[0].id)
        #expect(try db.hits(forChunks: travel.map(\.ref)).first?.snippet.contains("Edinburgh") == true)
        #expect(try db.nearest([1, 0, 0], kinds: [.todo]).map(\.ref) == [42])
        #expect(try db.nearest([0, 0, 1], kinds: [.chunk], minScore: 0.9).isEmpty)

        try db.forgetAll()
        #expect(try db.nearest([1, 0, 0], kinds: [.chunk]).isEmpty)
    }

    @Test func vectorMath() {
        #expect(VectorMath.normalized([3, 4]) == [0.6, 0.8])
        #expect(abs(VectorMath.dot([0.6, 0.8], [0.6, 0.8]) - 1) < 0.0001)
        #expect(VectorMath.dot([1, 0], [1, 0, 0]) == 0)
        #expect(VectorMath.decode(VectorMath.encode([1.5, -2])) == [1.5, -2])
    }
}
