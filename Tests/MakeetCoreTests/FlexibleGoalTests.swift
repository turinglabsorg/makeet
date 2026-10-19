import XCTest
import SwiftData
import MakeetCore
@testable import MakeetPersistence

final class FlexibleGoalTests: XCTestCase {
    private let day = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00Z")!
    private func habit(goal: HabitGoal = .atMost, target: Double = 0) -> HabitSnapshot {
        HabitSnapshot(name: "Limit", target: target, createdAt: day.addingTimeInterval(-86400),
                      timeZoneID: "UTC", goal: goal, allowsNegative: true)
    }
    func testZeroLimitRequiresARegistrationAndCountsOccurrencesAsMalus() {
        let h = habit()
        let unknown = HabitEngine.progress(for: h, on: day, activities: [])
        XCTAssertFalse(unknown.completed); XCTAssertEqual(unknown.fraction, 0)
        let zero = ActivitySnapshot(habitID: h.id, amount: 0, timestamp: day)
        let confirmed = HabitEngine.progress(for: h, on: day, activities: [zero])
        XCTAssertTrue(confirmed.completed); XCTAssertEqual(confirmed.fraction, 1)
        XCTAssertEqual(confirmed.registrations, 1)
        let occurrences = ActivitySnapshot(habitID: h.id, amount: 3, timestamp: day)
        let failed = HabitEngine.progress(for: h, on: day, activities: [zero, occurrences])
        XCTAssertFalse(failed.completed); XCTAssertEqual(failed.malus, 3)
        XCTAssertTrue(failed.fraction.isFinite)
        let stats = HabitEngine.statistics(for: h, activities: [zero, occurrences], now: day)
        XCTAssertEqual(stats.total, 3); XCTAssertEqual(stats.activeDays, 1)
        XCTAssertTrue(ScheduleEngine.propose(habits: [h], activities: [], busy: [], now: day, days: 28).isEmpty)
    }
    func testPositiveLimitAndSignedBalanceAgreeInCalendarStatisticsAndStreaks() {
        let h = habit(target: 2)
        let yesterday = day.addingTimeInterval(-86400)
        let entries = [ActivitySnapshot(habitID: h.id, amount: 0, timestamp: yesterday),
                       ActivitySnapshot(habitID: h.id, amount: 3, timestamp: day)]
        let stats = HabitEngine.statistics(for: h, activities: entries, now: day)
        XCTAssertEqual(stats.completedDays, 1); XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.days.last?.malus, 1)
        let calendar = HabitEngine.calendarDays(habits: [h], activities: entries, dates: [yesterday, day], displayCalendar: h.calendar)
        XCTAssertEqual(calendar.map(\.completedGoals), [1, 0]); XCTAssertTrue(calendar[1].hasMalus)
        XCTAssertTrue(calendar[0].hasActivity)
        let grow = habit(goal: .atLeast, target: 3)
        let signed = [ActivitySnapshot(habitID: grow.id, amount: -4, timestamp: day),
                      ActivitySnapshot(habitID: grow.id, amount: 1, timestamp: day)]
        let progress = HabitEngine.progress(for: grow, on: day, activities: signed)
        XCTAssertEqual(progress.quantity, -3); XCTAssertEqual(progress.malus, 3)
        XCTAssertEqual(progress.fraction, 0); XCTAssertFalse(progress.completed)
        XCTAssertEqual(HabitEngine.statistics(for: grow, activities: signed, now: day).total, -3)
    }
    @MainActor func testSignedLoggingZeroConfirmationCorrectionAndSyncSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([Habit.self, Activity.self])
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                url: directory.appendingPathComponent("goals.store"), cloudKitDatabase: .none)])
        }
        let context = ModelContext(try open())
        let h = Habit(name: "Beer", symbol: "leaf", colorIndex: 0, target: 0, step: 1, unit: "times",
                      createdAt: day.addingTimeInterval(-86400), goal: .atMost, allowsNegative: true)
        h.timeZoneID = "UTC"; context.insert(h); try context.save()
        try SharedStore.confirmZero(h, in: context, now: day)
        try SharedStore.confirmZero(h, in: context, now: day)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Activity>()), 1)
        try SharedStore.decrement(h, in: context, now: day)
        XCTAssertEqual(HabitEngine.progress(for: h.snapshot, on: day, activities: try context.fetch(FetchDescriptor<Activity>()).map(\.snapshot)).quantity, -1)
        try SharedStore.correct([HabitDayCorrection(habitID: h.id, date: day, quantity: -4, expectedQuantity: -1)], in: context, now: day)
        let reopened = ModelContext(try open())
        let saved = try XCTUnwrap(reopened.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(saved.goal, .atMost); XCTAssertTrue(saved.allowsNegative)
        XCTAssertEqual(saved.target, 0)
        let records = try AccountRecords.snapshot(in: reopened)
        let remote = ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
        try AccountRecords.apply(records, in: remote)
        let remoteHabit = try XCTUnwrap(remote.fetch(FetchDescriptor<Habit>()).first)
        let progress = HabitEngine.progress(for: remoteHabit.snapshot, on: day, activities: try remote.fetch(FetchDescriptor<Activity>()).map(\.snapshot))
        XCTAssertEqual(progress.quantity, -4); XCTAssertTrue(progress.completed)
        remoteHabit.allowsNegative = false
        try SharedStore.decrement(remoteHabit, in: remote, now: day)
        XCTAssertEqual(HabitEngine.progress(for: remoteHabit.snapshot, on: day, activities: try remote.fetch(FetchDescriptor<Activity>()).map(\.snapshot)).quantity, -4)
        XCTAssertThrowsError(try SharedStore.correct([HabitDayCorrection(habitID: remoteHabit.id, date: day, quantity: -5, expectedQuantity: -4)], in: remote, now: day))
    }
    @MainActor func testFractionalSignedCancellationRemainsZeroAcrossSurfacesAndCorrections() throws {
        let h = habit()
        let entries = [0.1, 0.2, -0.3].map { ActivitySnapshot(habitID: h.id, amount: $0, timestamp: day) }
        let progress = HabitEngine.progress(for: h, on: day, activities: entries)
        XCTAssertEqual(progress.quantity, 0); XCTAssertTrue(progress.completed); XCTAssertEqual(progress.malus, 0)
        XCTAssertEqual(HabitEngine.statistics(for: h, activities: entries, now: day).total, 0)
        XCTAssertFalse(HabitEngine.calendarDays(habits: [h], activities: entries, dates: [day], displayCalendar: h.calendar)[0].hasMalus)
        XCTAssertEqual(QuantityTotal.sum([0.0000000001]), 0.0000000001)
        let schema = Schema([Habit.self, Activity.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
        let saved = Habit(name: "Fraction", symbol: "leaf", colorIndex: 0, target: 0, step: 0.1, unit: "times", createdAt: day, goal: .atMost, allowsNegative: true)
        saved.id = h.id; saved.timeZoneID = "UTC"; context.insert(saved)
        for entry in entries { context.insert(Activity(habitID: h.id, amount: entry.amount, timestamp: day)) }
        try context.save()
        try SharedStore.correct([HabitDayCorrection(habitID: h.id, date: day, quantity: -1, expectedQuantity: 0)], in: context, now: day)
        XCTAssertEqual(HabitEngine.progress(for: saved.snapshot, on: day, activities: try context.fetch(FetchDescriptor<Activity>()).map(\.snapshot)).quantity, -1)
    }

    func testLegacyWireDefaultsAndGoalRoundTrip() throws {
        let record = HabitRecord(name: "Legacy", symbol: "leaf", colorIndex: 0, target: 1, step: 1,
            unit: "times", createdAt: day, timeZoneID: "UTC", preferredHour: 18, durationMinutes: 20, archived: false)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: AccountCoding.encoder().encode(record)) as? [String: Any])
        json.removeValue(forKey: "goal"); json.removeValue(forKey: "allows_negative")
        let legacy = try AccountCoding.decoder().decode(HabitRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.goal, .atLeast); XCTAssertFalse(legacy.allowsNegative)
        var signed = record; signed.goal = .atMost; signed.target = 0; signed.allowsNegative = true
        XCTAssertEqual(try AccountCoding.decoder().decode(HabitRecord.self, from: AccountCoding.encoder().encode(signed)), signed)
    }
}
