import Foundation
import Testing
@testable import GobblCore

@Suite struct ReminderParserTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    /// Monday 14 Sep 2026, 10:00 IST.
    private var now: Date { date(14, 10, 0) }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func reminder(_ text: String) -> Reminder? {
        if case .reminder(let r)? = ReminderParser.parse(text, now: now, calendar: cal) { return r }
        return nil
    }

    @Test func timeAfterTheTask() {
        let r = reminder("Remind me to call Sara at 3pm")
        #expect(r?.text == "Call Sara")
        #expect(r?.due == date(14, 15, 0))
    }

    @Test func ambiguousHourPicksTheNextOne() {
        #expect(reminder("remind me at 3 to call Sara")?.due == date(14, 15, 0))
        #expect(reminder("remind me at 8 to walk")?.due == date(14, 20, 0))
        #expect(reminder("remind me at 11 to stretch")?.due == date(14, 11, 0))
    }

    @Test func relative() {
        #expect(reminder("remind me in 20 minutes to stretch")?.due == now.addingTimeInterval(1200))
        #expect(reminder("remind me in half an hour to check the oven")?.text == "Check the oven")
        #expect(reminder("remind me in half an hour to check the oven")?.due == now.addingTimeInterval(1800))
        #expect(reminder("remind me in an hour to leave")?.due == now.addingTimeInterval(3600))
    }

    @Test func tomorrowAndWeekdays() {
        let r = reminder("remind me tomorrow at 9 to send the invoice")
        #expect(r?.due == date(15, 9, 0))
        #expect(r?.text == "Send the invoice")
        #expect(reminder("remind me on friday at 4:30pm to review PRs")?.due == date(18, 16, 30))
        #expect(reminder("remind me tomorrow at 3 to call the bank")?.due == date(15, 15, 0))
    }

    @Test func tonight() {
        let r = reminder("remind me tonight at 9 to call mom")
        #expect(r?.due == date(14, 21, 0))
        #expect(r?.text == "Call mom")
    }

    @Test func repeating() {
        let r = reminder("remind me every weekday at 10 to stand up")
        #expect(r?.repeats == .weekdays)
        #expect(r?.due == date(15, 10, 0))
        #expect(r?.text == "Stand up")
        let weekly = Reminder(text: "Plan", due: date(14, 9, 0), repeats: .weekly(weekday: 2))
        #expect(weekly.nextOccurrence(after: now, calendar: cal) == date(21, 9, 0))
        let weekdays = Reminder(text: "Standup", due: date(18, 10, 0), repeats: .weekdays)
        #expect(weekdays.nextOccurrence(after: date(18, 10, 0), calendar: cal) == date(21, 10, 0))
    }

    @Test func needsATime() {
        #expect(ReminderParser.parse("remind me to buy milk", now: now, calendar: cal) == .needsTime("Buy milk"))
    }

    @Test func notAReminder() {
        #expect(ReminderParser.parse("what's on today?", now: now, calendar: cal) == nil)
    }
}

@Suite struct RoutineTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test func briefIsDueOncePerDayInsideItsWindow() {
        let eight = 8 * 60
        #expect(!BriefSchedule.isDue(minuteOfDay: eight, lastRun: nil, now: date(14, 7, 59), calendar: cal))
        #expect(BriefSchedule.isDue(minuteOfDay: eight, lastRun: nil, now: date(14, 8, 5), calendar: cal))
        #expect(BriefSchedule.isDue(minuteOfDay: eight, lastRun: date(13, 8, 1), now: date(14, 9), calendar: cal))
        #expect(!BriefSchedule.isDue(minuteOfDay: eight, lastRun: date(14, 8, 1), now: date(14, 9), calendar: cal))
        #expect(!BriefSchedule.isDue(minuteOfDay: eight, lastRun: nil, now: date(14, 13), calendar: cal))
    }

    @Test func nudgesAreRareAndRespectQuiet() {
        var policy = NudgePolicy()
        let noon = date(14, 12)
        #expect(!policy.canNudge("a", now: noon, quiet: true, focusing: false, calendar: cal))
        #expect(!policy.canNudge("a", now: noon, quiet: false, focusing: true, calendar: cal))
        #expect(!policy.canNudge("a", now: date(14, 23), quiet: false, focusing: false, calendar: cal))
        for key in ["a", "b", "c"] {
            #expect(policy.canNudge(key, now: noon, quiet: false, focusing: false, calendar: cal))
            policy.record(key, now: noon, calendar: cal)
        }
        #expect(!policy.canNudge("d", now: noon, quiet: false, focusing: false, calendar: cal))
        #expect(policy.canNudge("a", now: date(15, 12), quiet: false, focusing: false, calendar: cal))
    }

    @Test func sameThingIsNudgedOnce() {
        var policy = NudgePolicy()
        policy.record("agent-1", now: date(14, 12), calendar: cal)
        #expect(!policy.canNudge("agent-1", now: date(14, 13), quiet: false, focusing: false, calendar: cal))
    }
}
