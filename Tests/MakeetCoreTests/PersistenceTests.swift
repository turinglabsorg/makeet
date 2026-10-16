import XCTest
import SwiftData
import MakeetCore
@testable import MakeetPersistence

final class PersistenceTests: XCTestCase {
    @MainActor func testDecrementSeesWidgetCorrectionEvenWhenAppAlreadyCachedTheActivity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([Habit.self, Activity.self]); let url = directory.appendingPathComponent("shared.store")
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        let app = ModelContext(try open())
        let habit = Habit(name: "Read", symbol: "book", colorIndex: 0, target: 20, step: 1, unit: "pages")
        app.insert(habit); app.insert(Activity(habitID: habit.id, amount: 5)); try app.save()
        _ = try app.fetch(FetchDescriptor<Activity>())
        let widget = ModelContext(try open())
        let activity = try XCTUnwrap(widget.fetch(FetchDescriptor<Activity>()).first)
        activity.amount = 3; try widget.save()
        try SharedStore.decrement(habit, in: app)
        let value = try ModelContext(open()).fetch(FetchDescriptor<Activity>()).first?.amount
        XCTAssertEqual(value, 2)
    }

    @MainActor func testAccountArchivesRemainSeparateAndScopedIntentCannotCrossAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = try AccountStoreLocation(root: directory)
        let first = UUID(), second = UUID()
        let firstContext = ModelContext(try location.container(for: first))
        firstContext.insert(Habit(name: "Private", symbol: "leaf", colorIndex: 0, target: 1, step: 1, unit: "times"))
        try firstContext.save()
        let secondContext = ModelContext(try location.container(for: second))
        XCTAssertEqual(try secondContext.fetchCount(FetchDescriptor<Habit>()), 0)
        XCTAssertEqual(try ModelContext(location.container(for: first)).fetchCount(FetchDescriptor<Habit>()), 1)
        let registry = try ScopeRegistry(root: directory)
        try registry.write(StoreScope.account(first).key)
        let stale = try XCTUnwrap(registry.read())
        try registry.write(StoreScope.account(second).key)
        var performed = false
        XCTAssertThrowsError(try registry.withScope(expected: stale) { _ in performed = true })
        XCTAssertFalse(performed)
        try registry.write("signed-out")
        XCTAssertThrowsError(try registry.withScope(expected: StoreScope.account(second).key) { _ in performed = true })
        XCTAssertFalse(performed)
    }

    @MainActor func testSyncSnapshotExcludesDemoAndRemoteApplyPersistsQuantities() throws {
        let container = try ModelContainer(for: Habit.self, Activity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let demo = Habit(name: "Demo", symbol: "leaf", colorIndex: 0, target: 1, step: 1, unit: "times")
        demo.isDemo = true; context.insert(demo)
        context.insert(Activity(habitID: demo.id, amount: 9, source: "demo"))
        let habit = Habit(name: "Water", symbol: "drop", colorIndex: 1, target: 8, step: 1, unit: "glasses")
        context.insert(habit); context.insert(Activity(habitID: habit.id, amount: 3)); try context.save()
        let original = try AccountRecords.snapshot(in: context)
        XCTAssertEqual(original.count, 2)
        var remote = try XCTUnwrap(original.first { $0.kind == .activity })
        remote.activity?.amount = 7
        try AccountRecords.apply([remote], in: context)
        let next = try AccountRecords.snapshot(in: context)
        XCTAssertEqual(next.first { $0.kind == .activity }?.activity?.amount, 7)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Habit>()), 2)
        try AccountRecords.apply([remote.tombstone()], in: context)
        XCTAssertEqual(try AccountRecords.snapshot(in: context).count, 1)
    }

    @MainActor func testDecrementUsesHabitDayAndStepClampsAtZeroAndSurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([Habit.self, Activity.self])
        let url = directory.appendingPathComponent("correction.store")
        func container() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        let context = ModelContext(try container())
        let habit = Habit(name: "Read", symbol: "emoji:📚", colorIndex: 0, target: 10, step: 5, unit: "pages")
        habit.timeZoneID = "Pacific/Auckland"
        let now = ISO8601DateFormatter().date(from: "2026-03-28T12:00:00Z")!
        let start = habit.snapshot.calendar.startOfDay(for: now)
        let end = habit.snapshot.calendar.date(byAdding: .day, value: 1, to: start)!
        context.insert(habit)
        for (amount, timestamp) in [(4.0, now.addingTimeInterval(-60)), (3, now), (99, start.addingTimeInterval(-1)), (77, end)] {
            context.insert(Activity(habitID: habit.id, amount: amount, timestamp: timestamp))
        }
        let otherID = UUID()
        context.insert(Activity(habitID: otherID, amount: 20, timestamp: now))
        try context.save()
        try SharedStore.decrement(habit, in: context, now: now)
        let reopened = ModelContext(try container())
        let savedHabit = try XCTUnwrap(reopened.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(savedHabit.symbol, "emoji:📚")
        var entries = try reopened.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(HabitEngine.progress(for: savedHabit.snapshot, on: now, activities: entries.map(\.snapshot)).quantity, 2)
        try SharedStore.decrement(savedHabit, in: reopened, now: now)
        try SharedStore.decrement(savedHabit, in: reopened, now: now)
        entries = try ModelContext(container()).fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(HabitEngine.progress(for: savedHabit.snapshot, on: now, activities: entries.map(\.snapshot)).quantity, 0)
        XCTAssertEqual(entries.map(\.amount).sorted(), [20, 77, 99])
        XCTAssertEqual(entries.first(where: { $0.habitID == otherID })?.amount, 20)
    }

    func testEmojiValidationSupportsSequencesAndRejectsOrdinaryText() {
        for emoji in ["🌱", "☀️", "👨‍👩‍👧‍👦", "🇮🇹", "👍🏽", "1️⃣", "©️"] {
            XCTAssertTrue(HabitAppearance.validEmoji(emoji))
            XCTAssertEqual(HabitAppearance.emoji(in: "emoji:\(emoji)"), emoji)
        }
        for value in ["", "a", "1", "hello", "🌱💧"] { XCTAssertFalse(HabitAppearance.validEmoji(value)) }
        XCTAssertNil(HabitAppearance.emoji(in: "leaf"))
        XCTAssertNil(HabitAppearance.emoji(in: "emoji:invalid"))
    }

    @MainActor func testFractionalDecrementDoesNotLeaveRoundingResidue() async throws {
        let container = try ModelContainer(for: Habit.self, Activity.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let habit = Habit(name: "Fraction", symbol: "leaf", colorIndex: 0, target: 1, step: 0.3, unit: "units")
        context.insert(habit)
        for _ in 0..<3 { context.insert(Activity(habitID: habit.id, amount: 0.1)) }
        try context.save()
        try SharedStore.decrement(habit, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Activity>()), 0)
    }
    @MainActor func testAppAndWidgetContextsSeeEveryIncrementAndUndoPersistsAfterReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let schema = Schema([Habit.self, Activity.self])
        func container() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        let appStore = try container()
        let app = ModelContext(appStore)
        let habit = Habit(name: "Water", symbol: "drop", colorIndex: 1, target: 8, step: 1, unit: "glasses")
        app.insert(habit)
        try app.save()
        try SharedStore.log(habit, in: app)
        let widgetStore = try container()
        let widget = ModelContext(widgetStore)
        let widgetHabit = try XCTUnwrap(widget.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(widgetHabit.id, habit.id)
        try SharedStore.log(widgetHabit, in: widget, source: "widget")
        try SharedStore.log(habit, in: app)
        let reopened = ModelContext(try container())
        let entries = try reopened.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.amount }, 3)
        let widgetEntry = try XCTUnwrap(entries.first { $0.source == "widget" })
        reopened.delete(widgetEntry)
        try reopened.save()
        let final = ModelContext(try container())
        XCTAssertEqual(try final.fetchCount(FetchDescriptor<Activity>()), 2)
        XCTAssertEqual(try final.fetchCount(FetchDescriptor<Habit>()), 1)
    }

    @MainActor func testArchivedHabitsCannotBeIncrementedByStaleWidget() async throws {
        let container = try ModelContainer(for: Habit.self, Activity.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let habit = Habit(name: "Read", symbol: "book", colorIndex: 0, target: 20, step: 5, unit: "pages")
        context.insert(habit); habit.archived = true; try context.save()
        try SharedStore.log(habit, in: context, source: "widget")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Activity>()), 0)
    }
}
