import SwiftData
import SwiftUI
import XCTest
@testable import Makeet

@MainActor final class HabitCardLifecycleTests: XCTestCase {
    func testCardCanFinishLayoutAfterItsArchiveIsReleased() throws {
        var container: ModelContainer? = try ModelContainer(for: Habit.self, Activity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        weak var oldArchive = container
        let habit = Habit(name: "Layout regression", symbol: "drop", colorIndex: 1,
                          target: 8, step: 1, unit: "glasses")
        container!.mainContext.insert(habit)
        let activity = Activity(habitID: habit.id, amount: 3)
        container!.mainContext.insert(activity)
        try container!.mainContext.save()
        let card = HabitCard(habit: habit, activities: [activity], now: Date(),
                             decrement: {}, increment: {})
        container = nil
        XCTAssertNil(oldArchive)

        let renderer = ImageRenderer(content: NavigationStack {
            card.frame(width: 390).padding()
        }.frame(width: 430, height: 420))
        XCTAssertNotNil(renderer.uiImage)
    }
}
