import XCTest
@testable import AvviCore

final class HabitEngineTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func habit(created: String = "2026-10-01T00:00:00Z", zone: String = "UTC", target: Double = 3) -> HabitSnapshot {
        HabitSnapshot(name: "Read", target: target, createdAt: date(created), timeZoneID: zone)
    }
    private func entry(_ habit: HabitSnapshot, _ time: String, _ amount: Double) -> ActivitySnapshot {
        ActivitySnapshot(habitID: habit.id, amount: amount, timestamp: date(time))
    }

    func testMultipleDailyRegistrationsPreserveQuantityBeyondTarget() {
        let h = habit()
        let entries = [entry(h, "2026-10-16T08:00:00Z", 2), entry(h, "2026-10-16T12:00:00Z", 4),
                       entry(h, "2026-10-17T00:00:00Z", 9)]
        let result = HabitEngine.progress(for: h, on: date("2026-10-16T22:00:00Z"), activities: entries)
        XCTAssertEqual(result.quantity, 6)
        XCTAssertEqual(result.registrations, 2)
        XCTAssertEqual(result.fraction, 1)
        XCTAssertTrue(result.completed)
    }

    func testRomeSpringDayIncludes23HoursAndExcludesNextMidnight() {
        let h = habit(created: "2026-03-01T00:00:00Z", zone: "Europe/Rome")
        let entries = [entry(h, "2026-03-28T23:00:00Z", 1), entry(h, "2026-03-29T21:59:59Z", 1),
                       entry(h, "2026-03-29T22:00:00Z", 10)]
        let result = HabitEngine.progress(for: h, on: date("2026-03-29T12:00:00Z"), activities: entries)
        XCTAssertEqual(result.quantity, 2)
    }

    func testRomeAutumnDayIncludesBothRepeatedHours() {
        let h = habit(zone: "Europe/Rome")
        let entries = [entry(h, "2026-10-25T00:30:00Z", 1), entry(h, "2026-10-25T01:30:00Z", 1),
                       entry(h, "2026-10-25T22:59:59Z", 1), entry(h, "2026-10-25T23:00:00Z", 20)]
        XCTAssertEqual(HabitEngine.progress(for: h, on: date("2026-10-25T12:00:00Z"), activities: entries).quantity, 3)
    }

    func testStatisticsExcludeDaysBeforeCreationAndFutureDays() {
        let h = habit(created: "2026-10-15T15:00:00Z")
        let result = HabitEngine.statistics(for: h, activities: [entry(h, "2026-10-15T18:00:00Z", 3)],
                                           now: date("2026-10-16T12:00:00Z"), window: 28)
        XCTAssertEqual(result.days.count, 2)
        XCTAssertEqual(result.completionRate, 0.5)
        XCTAssertEqual(result.average, 1.5)
    }

    func testIncompleteTodayDoesNotBreakYesterdayStreak() {
        let h = habit(created: "2026-10-13T00:00:00Z")
        let entries = [entry(h, "2026-10-14T18:00:00Z", 3), entry(h, "2026-10-15T18:00:00Z", 3)]
        let result = HabitEngine.statistics(for: h, activities: entries, now: date("2026-10-16T12:00:00Z"))
        XCTAssertEqual(result.currentStreak, 2)
        XCTAssertEqual(result.longestStreak, 2)
    }

    func testMissedYesterdayBreaksCurrentStreakAndWindowDoesNotTruncateBestStreak() {
        let h = habit(created: "2026-10-01T00:00:00Z")
        let entries = (1...10).map { entry(h, String(format: "2026-10-%02dT18:00:00Z", $0), 3) }
        let result = HabitEngine.statistics(for: h, activities: entries, now: date("2026-10-16T12:00:00Z"), window: 7)
        XCTAssertEqual(result.currentStreak, 0)
        XCTAssertEqual(result.longestStreak, 10)
        XCTAssertEqual(result.days.count, 7)
    }

    func testCorruptAndOtherHabitEntriesDoNotPoisonStatistics() {
        let h = habit()
        let other = habit()
        let entries = [entry(h, "2026-10-16T08:00:00Z", .nan), entry(h, "2026-10-16T08:00:00Z", -2),
                       entry(other, "2026-10-16T08:00:00Z", 100), entry(h, "2026-10-16T08:00:00Z", 1)]
        XCTAssertEqual(HabitEngine.progress(for: h, on: date("2026-10-16T12:00:00Z"), activities: entries).quantity, 1)
    }
}
