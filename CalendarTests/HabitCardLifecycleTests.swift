import SwiftData
import SwiftUI
import Observation
import UIKit
import XCTest
@testable import Makeet

@MainActor final class HabitCardLifecycleTests: XCTestCase {
    func testTodaySurvivesReplacingItsArchiveWhileMounted() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Archive-transition fixtures run only in Simulator.")
        #else
        let state = ArchiveTransitionState(container: try fixtureArchive("Old archive"))
        var controller: UIHostingController<AnyView>? = UIHostingController(rootView: AnyView(ArchiveTransitionRoot(state: state)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(600))
        controller!.view.layoutIfNeeded()
        var retired: [WeakArchive] = []
        for index in 0..<6 {
            retired.append(WeakArchive(state.container))
            let next = try fixtureArchive("Archive \(index)", empty: index.isMultiple(of: 2))
            withAnimation(.linear(duration: 0.05)) {
                state.container = next
            }
            try await Task.sleep(for: .milliseconds(150))
            controller!.view.setNeedsLayout()
            controller!.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
        }
        XCTAssertNotNil(controller!.view.window)
        controller!.rootView = AnyView(EmptyView())
        window.isHidden = true
        window.rootViewController = nil
        controller = nil
        try await Task.sleep(for: .milliseconds(200))
        for archive in retired {
            XCTAssertNil(archive.value, "Retired archives must be released with the hosting hierarchy.")
        }
        #endif
    }

    private func fixtureArchive(_ name: String, empty: Bool = false) throws -> ModelContainer {
        let container = try ModelContainer(for: Habit.self, Activity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        if !empty {
            let habit = Habit(name: name, symbol: "drop", colorIndex: 1, target: 8, step: 1, unit: "glasses")
            container.mainContext.insert(habit)
            container.mainContext.insert(Activity(habitID: habit.id, amount: 3))
        }
        try container.mainContext.save()
        return container
    }

    func testCardCanFinishLayoutAfterItsArchiveIsReleased() async throws {
        let (card, oldArchive) = try detachedCardFixture()
        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            oldArchive.value == nil
        }, object: nil)
        await fulfillment(of: [released], timeout: 2)
        XCTAssertNil(oldArchive.value)

        let renderer = ImageRenderer(content: NavigationStack {
            card.frame(width: 390).padding()
        }.frame(width: 430, height: 420))
        XCTAssertNotNil(renderer.uiImage)
    }

    @inline(never) private func detachedCardFixture() throws -> (HabitCard, WeakArchive) {
        try autoreleasepool {
            let container = try ModelContainer(for: Habit.self, Activity.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            container.mainContext.autosaveEnabled = false
            let habit = Habit(name: "Layout regression", symbol: "drop", colorIndex: 1,
                              target: 8, step: 1, unit: "glasses")
            container.mainContext.insert(habit)
            let activity = Activity(habitID: habit.id, amount: 3)
            container.mainContext.insert(activity)
            try container.mainContext.save()
            return (HabitCard(habit: habit, activities: [activity], now: Date(),
                              decrement: {}, increment: {}), WeakArchive(container))
        }
    }
}

private final class WeakArchive {
    weak var value: ModelContainer?
    init(_ value: ModelContainer) { self.value = value }
}

@MainActor @Observable private final class ArchiveTransitionState {
    var container: ModelContainer
    init(container: ModelContainer) { self.container = container }
}

private struct ArchiveTransitionRoot: View {
    let state: ArchiveTransitionState
    @State private var account = AccountManager()
    var body: some View {
        ArchiveHost(container: state.container) { ArchiveTransitionContent() }
            .environment(account)
            .environment(NotificationService.shared)
    }
}

private struct ArchiveTransitionContent: View {
    @State private var presented = true
    var body: some View {
        NavigationStack { TodayView(demoMode: .constant(false)) }
            .sheet(isPresented: $presented) { ConnectionsView(calendar: CalendarService(scope: "local")) }
    }
}
