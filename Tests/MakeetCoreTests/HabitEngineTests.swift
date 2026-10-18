import XCTest
@testable import MakeetCore

final class HabitEngineTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func habit(created: String = "2026-10-01T00:00:00Z", zone: String = "UTC", target: Double = 3) -> HabitSnapshot {
        HabitSnapshot(name: "Read", target: target, createdAt: date(created), timeZoneID: zone)
    }
    private func entry(_ habit: HabitSnapshot, _ time: String, _ amount: Double) -> ActivitySnapshot {
        ActivitySnapshot(habitID: habit.id, amount: amount, timestamp: date(time))
    }

    func testHourlyRegistrationCountsRespectSelectedDaysAndRepeatedHours() {
        let h = habit(created: "2026-10-23T22:00:00Z", zone: "Europe/Rome")
        let other = habit(zone: "Europe/Rome")
        let entries = [entry(h, "2026-10-24T10:00:00Z", 9),
                       entry(h, "2026-10-25T00:30:00Z", 2), entry(h, "2026-10-25T01:30:00Z", 3),
                       entry(h, "2026-10-25T22:59:59Z", 1), entry(h, "2026-10-25T23:00:00Z", 20),
                       entry(h, "2026-10-25T12:00:00Z", .nan), entry(h, "2026-10-25T12:00:00Z", -1),
                       entry(h, "2026-10-25T12:00:00Z", 0), entry(other, "2026-10-25T12:00:00Z", 40)]
        let today = HabitEngine.statistics(for: h, activities: entries, now: date("2026-10-25T12:00:00Z"), window: 1)
        XCTAssertEqual(today.total, 6)
        XCTAssertEqual(today.days.first?.registrations, 3)
        XCTAssertEqual(today.hourlyRegistrations.count, 24)
        XCTAssertEqual(today.hourlyRegistrations[2], 2)
        XCTAssertEqual(today.hourlyRegistrations[23], 1)
        XCTAssertEqual(today.hourlyRegistrations.reduce(0, +), 3)
        let all = HabitEngine.statistics(for: h, activities: entries, now: date("2026-10-25T12:00:00Z"), window: 7)
        XCTAssertEqual(all.total, 15)
        XCTAssertEqual(all.hourlyRegistrations.reduce(0, +), 4)
        for day in all.days {
            let progress = HabitEngine.progress(for: h, on: day.date, activities: entries)
            XCTAssertEqual(day.quantity, progress.quantity)
            XCTAssertEqual(day.registrations, progress.registrations)
        }
    }

    func testLongHistoryKeepsLifetimeStreaksAndSelectedWindowQuantities() {
        let h = habit(created: "2020-01-01T00:00:00Z")
        let entries = (0..<2500).flatMap { day in
            (7..<11).map { hour in
                ActivitySnapshot(habitID: h.id, amount: 1, timestamp: h.createdAt.addingTimeInterval(Double(day * 86400 + hour * 3600)))
            }
        }
        let now = h.createdAt.addingTimeInterval(Double(2499 * 86400 + 12 * 3600))
        for window in [7, 28, 84] {
            let result = HabitEngine.statistics(for: h, activities: entries, now: now, window: window)
            XCTAssertEqual(result.days.count, window)
            XCTAssertEqual(result.total, Double(window * 4))
            XCTAssertEqual(result.currentStreak, 2500)
            XCTAssertEqual(result.longestStreak, 2500)
            XCTAssertEqual(result.hourlyRegistrations.reduce(0, +), window * 4)
            XCTAssertEqual(result.hourlyRegistrations[7], window)
        }
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
