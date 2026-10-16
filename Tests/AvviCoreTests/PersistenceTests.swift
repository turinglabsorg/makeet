import XCTest
import SwiftData
@testable import AvviPersistence

final class PersistenceTests: XCTestCase {
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
