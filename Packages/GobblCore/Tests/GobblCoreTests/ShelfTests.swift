import Foundation
import Testing
@testable import GobblCore

@Suite struct ShelfTests {
    let a = URL(fileURLWithPath: "/tmp/a.png")
    let b = URL(fileURLWithPath: "/tmp/b.pdf")

    @Test func addsNewestFirstWithoutDuplicates() {
        var shelf = Shelf()
        #expect(shelf.add([a, b]) == 2)
        #expect(shelf.items.map(\.name) == ["b.pdf", "a.png"])
        #expect(shelf.add([URL(fileURLWithPath: "/tmp/./a.png")]) == 0)
        #expect(shelf.items.map(\.name) == ["a.png", "b.pdf"])
    }

    @Test func ignoresNonFileURLs() {
        var shelf = Shelf()
        #expect(shelf.add([URL(string: "https://xeve.io")!]) == 0)
        #expect(shelf.items.isEmpty)
    }

    @Test func capsCapacity() {
        var shelf = Shelf()
        shelf.add((0..<(Shelf.capacity + 10)).map { URL(fileURLWithPath: "/tmp/\($0)") })
        #expect(shelf.items.count == Shelf.capacity)
        #expect(shelf.items.first?.name == "\(Shelf.capacity + 9)")
    }

    @Test func removeAndPrune() {
        var shelf = Shelf()
        shelf.add([a, b])
        shelf.remove(shelf.items[0].id)
        #expect(shelf.items.map(\.name) == ["a.png"])
        shelf.add([b])
        shelf.prune { $0.lastPathComponent != "a.png" }
        #expect(shelf.items.map(\.name) == ["b.pdf"])
    }

    @Test func roundTripsThroughJSON() throws {
        var shelf = Shelf()
        shelf.add([a, b])
        let data = try JSONEncoder().encode(shelf)
        #expect(try JSONDecoder().decode(Shelf.self, from: data) == shelf)
    }
}
