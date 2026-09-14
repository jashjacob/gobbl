import Foundation
import Testing
@testable import GobblCore

@Suite struct DayPartsTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    @Test func partsAndLateNights() {
        #expect(DayParts.part(of: date(14, 9), calendar: cal) == "morning")
        #expect(DayParts.part(of: date(14, 14), calendar: cal) == "afternoon")
        #expect(DayParts.part(of: date(14, 22), calendar: cal) == "evening")
        #expect(DayParts.dayKey(date(14, 9), calendar: cal) == "2026-09-14")
        // 2 am on the 15th still belongs to the 14th.
        #expect(DayParts.dayKey(date(15, 2), calendar: cal) == "2026-09-14")
        let range = DayParts.range(of: "2026-09-14", calendar: cal)
        #expect(range?.start == date(14, 5))
        #expect(range?.end == date(15, 5))
    }
}

@Suite struct DigestStoreTests {
    @Test func segmentsDigestsAndForgettingABlock() throws {
        let db = try MemoryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("gobbl-digest-\(UUID().uuidString).sqlite"))
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let seg = try db.beginSegment(appBundle: "com.google.Chrome", appName: "Google Chrome", window: "Wanderlog - UK trip",
                                      url: "https://wanderlog.com/trip", chat: nil, at: t)
        try db.addChunks(segment: seg, [.init(ts: t.addingTimeInterval(60), kind: "text", text: "Day 3: Edinburgh castle"),
                                        .init(ts: t.addingTimeInterval(1200), kind: "text", text: "Train to York, 10:04")])
        let summaries = try db.segments(from: t.addingTimeInterval(-10), to: t.addingTimeInterval(3600))
        #expect(summaries.count == 1)
        #expect(summaries[0].domain == "wanderlog.com")
        #expect(summaries[0].minutes == 20)
        #expect(summaries[0].excerpt.contains("Edinburgh"))

        try db.upsertDigest(DayDigest(day: "2026-09-12", part: "evening", bullets: ["Planned the UK trip on Wanderlog"], apps: ["Google Chrome"], created: t))
        try db.upsertDigest(DayDigest(day: "2026-09-12", part: "morning", bullets: ["Sorted email"], apps: ["Spark"], created: t))
        try db.upsertDigest(DayDigest(day: "2026-09-12", part: "morning", bullets: ["Sorted email in Spark"], apps: ["Spark"], created: t))
        let digests = try db.digests(sinceDay: "2026-09-01")
        #expect(digests.map(\.part) == ["morning", "evening"])
        #expect(digests[0].bullets == ["Sorted email in Spark"])
        #expect(db.hasDigest(day: "2026-09-12"))
        #expect(!db.hasDigest(day: "2026-09-13"))

        try db.forget(segment: seg)
        #expect(try db.segments(from: t.addingTimeInterval(-10), to: t.addingTimeInterval(3600)).isEmpty)
        #expect(try db.search("Edinburgh").isEmpty)
    }
}
