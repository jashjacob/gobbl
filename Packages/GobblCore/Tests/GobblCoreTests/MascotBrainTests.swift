import Foundation
import Testing
@testable import GobblCore

@Suite struct MascotBrainTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func startsIdle() {
        #expect(MascotBrain().mood(at: t0) == .idle)
    }

    @Test func eatsDroppedFilesThenSettles() {
        var b = MascotBrain()
        b.handle(.filesDropped(3), now: t0)
        #expect(b.mood(at: t0) == .eating)
        #expect(b.stats.filesGobbled == 3)
        #expect(b.nextChange(after: t0) == t0.addingTimeInterval(1.2))
        #expect(b.mood(at: t0.addingTimeInterval(2)) == .idle)
        #expect(b.nextChange(after: t0.addingTimeInterval(2)) == nil)
    }

    @Test func emptyDropDoesNothing() {
        var b = MascotBrain()
        b.handle(.filesDropped(0), now: t0)
        #expect(b.mood(at: t0) == .idle)
        #expect(b.stats.xp == 0)
    }

    @Test func restingMoodPriority() {
        var b = MascotBrain()
        b.handle(.cursorNear(true), now: t0)
        #expect(b.mood(at: t0) == .curious)
        b.handle(.battery(level: 0.1, charging: false), now: t0)
        #expect(b.mood(at: t0) == .sleepy)
        b.handle(.musicPlaying(true), now: t0)
        #expect(b.mood(at: t0) == .dancing)
        b.handle(.userIdle(MascotBrain.sleepAfter), now: t0)
        #expect(b.mood(at: t0) == .sleeping)
        b.handle(.petted, now: t0)
        #expect(b.mood(at: t0) == .love)
    }

    @Test func pluggingInCheersUpUnlessQuiet() {
        var b = MascotBrain()
        b.handle(.pluggedIn, now: t0)
        #expect(b.mood(at: t0) == .happy)
        var q = MascotBrain()
        q.quiet = true
        q.handle(.pluggedIn, now: t0)
        #expect(q.mood(at: t0) == .idle)
    }

    @Test func chargingIsNeverSleepy() {
        var b = MascotBrain()
        b.handle(.battery(level: 0.05, charging: true), now: t0)
        #expect(b.mood(at: t0) == .idle)
    }

    @Test func quietModeSkipsPlayfulReactionsButCountsActions() {
        var b = MascotBrain()
        b.quiet = true
        b.handle(.musicPlaying(true), now: t0)
        #expect(b.mood(at: t0) == .idle)
        b.handle(.shaken, now: t0)
        #expect(b.mood(at: t0) == .idle)
        b.handle(.filesDropped(1), now: t0)
        #expect(b.mood(at: t0) == .eating)
        #expect(b.stats.filesGobbled == 1)
    }

    @Test func levelsUpAndCelebrates() {
        var b = MascotBrain()
        #expect(b.stats.level == 1)
        let first = b.handle(.filesDropped(4), now: t0)  // 8 XP
        #expect(!first)
        let second = b.handle(.filesDropped(1), now: t0) // 10 XP → level 2
        #expect(second)
        #expect(b.stats.level == 2)
        #expect(b.mood(at: t0) == .celebrating)
    }

    @Test func levelCurveAndStages() {
        var s = MascotStats()
        for (xp, level) in [(0, 1), (9, 1), (10, 2), (39, 2), (40, 3), (90, 4), (160, 5)] {
            s.xp = xp
            #expect(s.level == level, "xp \(xp)")
        }
        s.xp = 0
        #expect(s.stage == 0)
        s.xp = 160
        #expect(s.stage == 1)
        s.xp = 10 * 11 * 11
        #expect(s.stage == 2)
        s.xp = 25
        #expect(s.levelProgress == 0.5)
    }

    @Test func bigDropsAreCappedForXP() {
        var b = MascotBrain()
        b.handle(.filesDropped(500), now: t0)
        #expect(b.stats.filesGobbled == 500)
        #expect(b.stats.xp == 10)
    }
}
