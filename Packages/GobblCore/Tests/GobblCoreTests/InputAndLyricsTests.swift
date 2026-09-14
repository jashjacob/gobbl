import CoreGraphics
import Foundation
import Testing
@testable import GobblCore

@Suite struct ShakeDetectorTests {
    /// Zigzags between x = 100 and 100 + amplitude, `strokes` times, 10 samples per stroke.
    private func zigzag(_ d: inout ShakeDetector, strokes: Int, amplitude: CGFloat, strokeTime: TimeInterval, start: TimeInterval = 0) -> Bool {
        var fired = false
        var t = start
        for s in 0..<strokes {
            for i in 1...10 {
                let f = CGFloat(i) / 10
                let x = s.isMultiple(of: 2) ? 100 + amplitude * f : 100 + amplitude * (1 - f)
                t += strokeTime / 10
                if d.feed(x: x, time: t) { fired = true }
            }
        }
        return fired
    }

    @Test func quickShakeFires() {
        var d = ShakeDetector()
        #expect(zigzag(&d, strokes: 6, amplitude: 80, strokeTime: 0.08))
    }

    @Test func slowOrSmallMovementDoesNot() {
        var slow = ShakeDetector()
        #expect(!zigzag(&slow, strokes: 6, amplitude: 80, strokeTime: 0.5))
        var tiny = ShakeDetector()
        #expect(!zigzag(&tiny, strokes: 8, amplitude: 10, strokeTime: 0.05))
    }

    @Test func straightLineDoesNot() {
        var d = ShakeDetector()
        var fired = false
        for i in 0..<200 where d.feed(x: CGFloat(i * 5), time: Double(i) * 0.01) { fired = true }
        #expect(!fired)
    }

    @Test func cooldownPreventsRepeats() {
        var d = ShakeDetector()
        #expect(zigzag(&d, strokes: 6, amplitude: 80, strokeTime: 0.08))
        #expect(!zigzag(&d, strokes: 6, amplitude: 80, strokeTime: 0.08, start: 0.6))
    }
}

@Suite struct LyricsTests {
    let lrc = """
    [ar: Someone]
    [00:01.00] First line
    [00:05.50][00:20.00] Chorus
    [00:10.00]
    [00:12.25] After the break
    """

    @Test func parsesAndSorts() {
        let lines = LRC.parse(lrc)
        #expect(lines.map(\.time) == [1, 5.5, 10, 12.25, 20])
        #expect(lines[1].text == "Chorus")
    }

    @Test func currentLine() {
        let lines = LRC.parse(lrc)
        #expect(LRC.line(at: 0.5, in: lines) == nil)
        #expect(LRC.line(at: 3, in: lines)?.text == "First line")
        #expect(LRC.line(at: 11, in: lines) == nil) // instrumental gap
        #expect(LRC.line(at: 25, in: lines)?.text == "Chorus")
    }
}

@Suite struct ShelfReplaceTests {
    @Test func replaceKeepsIdentity() {
        var shelf = Shelf()
        shelf.add([URL(fileURLWithPath: "/tmp/a.png")])
        let id = shelf.items[0].id
        shelf.replace(id, with: URL(fileURLWithPath: "/tmp/b.png"))
        #expect(shelf.items[0].id == id)
        #expect(shelf.items[0].name == "b.png")
    }
}
