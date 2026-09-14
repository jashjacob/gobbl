import Foundation
import Testing
@testable import GobblCore

@Suite struct NowPlayingTests {
    /// Applies one adapter line; returns whether the state changed.
    /// (#expect can't wrap a mutating call directly.)
    private func feed(_ s: inout NowPlayingStream, _ json: String) -> Bool {
        s.apply(line: Data(json.utf8))
    }

    @Test func fullPayloadThenDiffs() {
        var s = NowPlayingStream()
        var changed = feed(&s, #"{"type":"data","diff":false,"payload":{"title":"Song","artist":"Band","playing":true,"duration":200,"elapsedTime":10,"bundleIdentifier":"com.spotify.client"}}"#)
        #expect(changed)
        #expect(s.current.title == "Song")
        #expect(s.current.artist == "Band")
        #expect(s.current.playing)
        #expect(s.current.duration == 200)

        changed = feed(&s, #"{"type":"data","diff":true,"payload":{"playing":false}}"#)
        #expect(changed)
        #expect(s.current.title == "Song")
        #expect(!s.current.playing)

        changed = feed(&s, #"{"type":"data","diff":true,"payload":{"artist":null}}"#)
        #expect(changed)
        #expect(s.current.artist == nil)
    }

    @Test func fullPayloadReplacesEverything() {
        var s = NowPlayingStream()
        _ = feed(&s, #"{"diff":false,"payload":{"title":"A","artist":"X"}}"#)
        _ = feed(&s, #"{"diff":false,"payload":{"title":"B"}}"#)
        #expect(s.current.title == "B")
        #expect(s.current.artist == nil)
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        var s = NowPlayingStream()
        _ = feed(&s, #"{"diff":false,"payload":{"title":"A"}}"#)
        _ = feed(&s, #"{"diff":false,"payload":{}}"#)
        #expect(!s.current.hasMedia)
    }

    @Test func ignoresGarbageAndUnchangedLines() {
        var s = NowPlayingStream()
        let garbage = feed(&s, "not json")
        let first = feed(&s, #"{"diff":false,"payload":{"title":"A"}}"#)
        let same = feed(&s, #"{"diff":true,"payload":{"title":"A"}}"#)
        #expect(!garbage)
        #expect(first)
        #expect(!same)
    }

    @Test func decodesTimestampAndArtwork() {
        var s = NowPlayingStream()
        _ = feed(&s, #"{"diff":false,"payload":{"title":"A","timestamp":"2026-09-14T07:10:28Z","artworkData":"AAEC"}}"#)
        #expect(s.current.timestamp == ISO8601DateFormatter().date(from: "2026-09-14T07:10:28Z"))
        #expect(s.current.artworkData == Data([0, 1, 2]))
    }

    @Test func elapsedExtrapolatesOnlyWhilePlaying() {
        var n = NowPlaying()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        n.elapsedTime = 10
        n.duration = 100
        n.timestamp = t0
        #expect(n.elapsed(at: t0.addingTimeInterval(5)) == 10)
        n.playing = true
        #expect(n.elapsed(at: t0.addingTimeInterval(5)) == 15)
        n.playbackRate = 2
        #expect(n.elapsed(at: t0.addingTimeInterval(5)) == 20)
        #expect(n.elapsed(at: t0.addingTimeInterval(500)) == 100)
    }
}
