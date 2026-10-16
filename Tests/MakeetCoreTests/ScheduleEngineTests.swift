import XCTest
@testable import MakeetCore

final class ScheduleEngineTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func habit(hour: Int = 18) -> HabitSnapshot {
        HabitSnapshot(name: "Walk", target: 30, step: 10, createdAt: date("2026-10-01T00:00:00Z"),
                      timeZoneID: "UTC", preferredHour: hour, durationMinutes: 30)
    }
    func testAvoidsOverlappingMeetingsAndKeepsProposalDuration() {
        let h = habit()
        let busy = [BusyInterval(start: date("2026-10-16T17:30:00Z"), end: date("2026-10-16T18:45:00Z")),
                    BusyInterval(start: date("2026-10-16T18:15:00Z"), end: date("2026-10-16T19:00:00Z"))]
        let result = ScheduleEngine.propose(habits: [h], activities: [], busy: busy, now: date("2026-10-16T16:00:00Z"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].end.timeIntervalSince(result[0].start), 1800)
        XCTAssertFalse(busy.contains { result[0].start < $0.end && result[0].end > $0.start })
    }
    func testPlansDoNotOverlapEachOtherOrAppearInPast() {
        let result = ScheduleEngine.propose(habits: [habit(), habit(), habit()], activities: [], busy: [],
                                            now: date("2026-10-16T18:05:00Z"))
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.start >= date("2026-10-16T18:05:00Z") })
        for pair in zip(result, result.dropFirst()) { XCTAssertLessThanOrEqual(pair.0.end, pair.1.start) }
    }
    func testNoProposalForCompletedHabitOrFullDay() {
        let h = habit()
        let complete = ActivitySnapshot(habitID: h.id, amount: 30, timestamp: date("2026-10-16T08:00:00Z"))
        XCTAssertTrue(ScheduleEngine.propose(habits: [h], activities: [complete], busy: [], now: date("2026-10-16T09:00:00Z")).isEmpty)
        let full = BusyInterval(start: date("2026-10-16T00:00:00Z"), end: date("2026-10-17T00:00:00Z"))
        XCTAssertTrue(ScheduleEngine.propose(habits: [h], activities: [], busy: [full], now: date("2026-10-16T09:00:00Z")).isEmpty)
    }
    func testLearnsHistoricalHourOnlyFromPrevious28Days() {
        let h = habit(hour: 18)
        let history = (1...6).map { index in
            ActivitySnapshot(habitID: h.id, amount: 10, timestamp: date(String(format: "2026-10-%02dT11:00:00Z", index)))
        }
        let proposals = ScheduleEngine.propose(habits: [h], activities: history, busy: [], now: date("2026-10-16T07:00:00Z"))
        XCTAssertEqual(proposals.first?.start, date("2026-10-16T11:00:00Z"))
        guard case .historicalHour(let samples) = proposals[0].reason else { return XCTFail("Missing explanation") }
        XCTAssertEqual(samples, 6)
    }
    func testFallsBackToPreferredHourWithTooLittleEvidence() {
        let h = habit()
        let entries = [ActivitySnapshot(habitID: h.id, amount: 10, timestamp: date("2026-10-15T11:00:00Z"))]
        let proposals = ScheduleEngine.propose(habits: [h], activities: entries, busy: [], now: date("2026-10-16T07:00:00Z"))
        XCTAssertEqual(proposals.first?.start, date("2026-10-16T18:00:00Z"))
    }
    func testLateNightDoesNotInventAnUnavailableSlot() {
        XCTAssertTrue(ScheduleEngine.propose(habits: [habit()], activities: [], busy: [], now: date("2026-10-16T21:45:00Z")).isEmpty)
    }
}
