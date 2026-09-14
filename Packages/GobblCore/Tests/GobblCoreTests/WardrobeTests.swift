import Foundation
import Testing
@testable import GobblCore

@Suite struct WardrobeTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test func streakCountsConsecutiveDays() {
        var s = MascotStats()
        let first = s.recordActiveDay(date(2026, 9, 14), calendar: calendar)
        let again = s.recordActiveDay(date(2026, 9, 14, hour: 20), calendar: calendar)
        #expect(first)
        #expect(!again)
        #expect(s.streak == 1)
        s.recordActiveDay(date(2026, 9, 15), calendar: calendar)
        s.recordActiveDay(date(2026, 9, 16), calendar: calendar)
        #expect(s.streak == 3)
        s.recordActiveDay(date(2026, 9, 20), calendar: calendar) // gap resets
        #expect(s.streak == 1)
        #expect(s.longestStreak == 3)
    }

    @Test func streakCrossesMonthAndYear() {
        var s = MascotStats()
        s.recordActiveDay(date(2026, 12, 31), calendar: calendar)
        s.recordActiveDay(date(2027, 1, 1), calendar: calendar)
        #expect(s.streak == 2)
    }

    @Test func hatsUnlockFromStats() {
        var s = MascotStats()
        let summer = date(2026, 7, 1)
        #expect(Wardrobe.owned(stats: s, date: summer, calendar: calendar) == [.none])
        s.xp = 10
        s.pets = 25
        s.longestStreak = 7
        s.songs = 10
        s.agentTasks = 10
        let owned = Set(Wardrobe.owned(stats: s, date: summer, calendar: calendar))
        #expect(owned == [.none, .party, .bow, .beanie, .headphones, .sunglasses, .halo])
    }

    @Test func seasonalHatsFollowTheCalendar() {
        let s = MascotStats()
        func has(_ hat: Hat, _ d: Date) -> Bool { hat.isUnlocked(stats: s, date: d, calendar: calendar) }
        #expect(has(.pumpkin, date(2026, 10, 31)))
        #expect(!has(.pumpkin, date(2026, 11, 10)))
        #expect(has(.diya, date(2026, 11, 8)))
        #expect(has(.santa, date(2026, 12, 25)))
        #expect(has(.santa, date(2027, 1, 3)))
        #expect(!has(.santa, date(2027, 1, 10)))
        #expect(has(.flower, date(2027, 4, 1)))
    }

    @Test func collectedSeasonalHatsStayOwned() {
        var s = MascotStats()
        let halloween = date(2026, 10, 31)
        let new = Wardrobe.newlyUnlocked(stats: s, date: halloween, calendar: calendar)
        #expect(new == [.pumpkin, .diya])
        s.collected = new.map(\.rawValue)
        #expect(Wardrobe.newlyUnlocked(stats: s, date: halloween, calendar: calendar).isEmpty)
        #expect(Wardrobe.owned(stats: s, date: date(2027, 7, 1), calendar: calendar).contains(.pumpkin))
    }

    @Test func oldStatsJSONStillDecodes() throws {
        let json = #"{"filesGobbled":3,"burps":1,"pets":42,"xp":45}"#
        let s = try JSONDecoder().decode(MascotStats.self, from: Data(json.utf8))
        #expect(s.pets == 42)
        #expect(s.songs == 0)
        #expect(s.collected.isEmpty)
    }
}
