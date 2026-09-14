import Foundation
import Testing
@testable import GobblCore

@Suite struct ClipboardHistoryTests {
    @Test func newestFirstAndDedupe() {
        var h = ClipboardHistory()
        h.record(ClipItem(kind: .text, text: "one"))
        h.record(ClipItem(kind: .text, text: "two"))
        h.record(ClipItem(kind: .text, text: "one"))
        #expect(h.items.map(\.text) == ["one", "two"])
    }

    @Test func dedupeKeepsIdAndPin() {
        var h = ClipboardHistory()
        h.record(ClipItem(kind: .text, text: "keep"))
        let id = h.items[0].id
        h.togglePin(id)
        h.record(ClipItem(kind: .text, text: "other"))
        h.record(ClipItem(kind: .text, text: "keep"))
        #expect(h.items[0].id == id)
        #expect(h.items[0].pinned)
    }

    @Test func imagesDedupeByDigest() {
        var h = ClipboardHistory()
        h.record(ClipItem(kind: .image, text: "a.png", digest: "abc"))
        h.record(ClipItem(kind: .image, text: "b.png", digest: "abc"))
        #expect(h.items.count == 1)
        #expect(h.item(matching: "image:abc") != nil)
    }

    @Test func evictsOldestUnpinned() {
        var h = ClipboardHistory(limit: 3)
        h.record(ClipItem(kind: .text, text: "pinned"))
        h.togglePin(h.items[0].id)
        for t in ["a", "b"] { h.record(ClipItem(kind: .text, text: t)) }
        let first = h.record(ClipItem(kind: .text, text: "c")).map(\.text)
        let second = h.record(ClipItem(kind: .text, text: "d")).map(\.text)
        #expect(first == ["a"])
        #expect(second == ["b"])
        #expect(h.items.map(\.text) == ["d", "c", "pinned"])
    }

    @Test func clearKeepsPinned() {
        var h = ClipboardHistory()
        h.record(ClipItem(kind: .text, text: "a"))
        h.record(ClipItem(kind: .text, text: "b"))
        h.togglePin(h.items[1].id)
        let removed = h.clearUnpinned().map(\.text)
        #expect(removed == ["b"])
        #expect(h.items.map(\.text) == ["a"])
    }

    @Test func searchPutsPinnedFirst() {
        var h = ClipboardHistory()
        h.record(ClipItem(kind: .text, text: "hello world"))
        h.record(ClipItem(kind: .text, text: "Hello again"))
        h.record(ClipItem(kind: .text, text: "bye"))
        h.togglePin(h.items[2].id) // "hello world"
        #expect(h.filtered("hello").map(\.text) == ["hello world", "Hello again"])
        #expect(h.filtered("").count == 3)
    }

    @Test func previews() {
        #expect(ClipItem(kind: .text, text: "  a\n\n b  ").preview == "a b")
        #expect(ClipItem(kind: .file, text: "/x/one.pdf\n/x/two.pdf").preview == "one.pdf + 1 more")
        #expect(ClipItem(kind: .image, text: "x.png").preview == "Image")
    }
}
