import XCTest
@testable import MakeetCore

final class WeeklyScheduleTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func habit(zone: String = "UTC", mask: Int = 11) -> HabitSnapshot {
        HabitSnapshot(name: "Read", target: 1, createdAt: date("2026-10-19T00:00:00Z"),
                      timeZoneID: zone, preferredHour: 18, durationMinutes: 20, weekdayMask: mask)
    }
    func testRestDaysDoNotBreakStreaksOrCountAsMissedTargets() {
        let h = habit()
        let entries = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22"].map {
            ActivitySnapshot(habitID: h.id, amount: 1, timestamp: date($0 + "T12:00:00Z"))
        }
        let result = HabitEngine.statistics(for: h, activities: entries, now: date("2026-10-25T12:00:00Z"), window: 7)
        XCTAssertEqual(result.scheduledDays, 3)
        XCTAssertEqual(result.completedDays, 3)
        XCTAssertEqual(result.completionRate, 1)
        XCTAssertEqual(result.currentStreak, 3)
        XCTAssertEqual(result.longestStreak, 3)
        XCTAssertEqual(result.total, 4)
        XCTAssertFalse(result.days[2].scheduled)
        let monday = HabitEngine.statistics(for: h, activities: entries, now: date("2026-10-26T08:00:00Z"), window: 7)
        XCTAssertEqual(monday.currentStreak, 3)
        let missed = HabitEngine.statistics(for: h, activities: entries.filter { $0.timestamp != date("2026-10-20T12:00:00Z") }, now: date("2026-10-25T12:00:00Z"))
        XCTAssertEqual(missed.currentStreak, 1)
    }
    func testFuturePlanUsesWeekdaysAvoidsExistingOccurrencesAndDST() {
        let h = habit(zone: "Europe/Rome")
        let now = date("2026-10-24T10:00:00Z")
        let first = ScheduleEngine.propose(habits: [h], activities: [], busy: [], now: now, days: 10)
        XCTAssertEqual(first.count, 4)
        XCTAssertTrue(first.allSatisfy { h.isScheduled(on: $0.start) && h.calendar.component(.hour, from: $0.start) == 18 })
        let planned = first.map { PlannedOccurrence(habitID: $0.habitID, start: $0.start) }
        XCTAssertTrue(ScheduleEngine.propose(habits: [h], activities: [], busy: [], now: now, days: 10, planned: planned).isEmpty)
        let blocked = ScheduleEngine.propose(habits: [h], activities: [], busy: [BusyInterval(start: first[0].start, end: first[0].end)], now: now, days: 10)
        XCTAssertEqual(blocked.count, 4)
        XCTAssertNotEqual(blocked[0].start, first[0].start)
        XCTAssertEqual(blocked[1].start, first[1].start)
    }
    func testCalendarDayMappingPreservesVisibleDateAcrossTimeZones() {
        var display = Calendar(identifier: .gregorian); display.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let h = habit(zone: "Pacific/Auckland", mask: 127)
        let shown = date("2026-10-25T10:00:00Z")
        let mapped = h.date(forCalendarDay: shown, displayedIn: display)
        XCTAssertEqual(h.calendar.component(.day, from: mapped), 25)
        XCTAssertEqual(h.calendar.component(.hour, from: mapped), 12)
    }
    func testLegacyHabitRecordsDefaultToDailyAndNewRecordsCarryWeekdays() throws {
        let record = HabitRecord(name: "Read", symbol: "book", colorIndex: 0, target: 1, step: 1, unit: "times",
            createdAt: date("2026-10-19T00:00:00Z"), timeZoneID: "UTC", preferredHour: 18, durationMinutes: 20, archived: false)
        let raw = try AccountCoding.encoder().encode(record)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        json.removeValue(forKey: "weekday_mask")
        let legacy = try AccountCoding.decoder().decode(HabitRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.weekdayMask, 127)
        var weekly = legacy; weekly.weekdayMask = 11
        XCTAssertEqual(try AccountCoding.decoder().decode(HabitRecord.self, from: AccountCoding.encoder().encode(weekly)).weekdayMask, 11)
    }
}

extension WeeklyScheduleTests {
    func testCalendarHeatmapKeepsArchivedActivityWithoutFutureGoals() {
        let h = habit(mask:127)
        var display = Calendar(identifier:.gregorian); display.timeZone = TimeZone(secondsFromGMT:0)!
        let day = date("2026-10-20T12:00:00Z")
        let values = HabitEngine.calendarDays(habits:[h],activities:[ActivitySnapshot(habitID:h.id,amount:1,timestamp:day)],dates:[day,day.addingTimeInterval(86400)],displayCalendar:display,excludedGoals:[h.id])
        XCTAssertTrue(values[0].hasActivity); XCTAssertEqual(values[0].scheduledGoals,0)
        XCTAssertFalse(values[1].hasActivity); XCTAssertEqual(values[1].scheduledGoals,0)
    }
}
