import XCTest
import EventKit
@testable import Avvi

final class CalendarServiceTests: XCTestCase {
    @MainActor func testConfirmedBlockIsIdempotentAndConflictRecheckPreventsOverlap() async throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Calendar integration tests only run in Simulator.")
        }
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw XCTSkip("Grant calendar permission to the Simulator test host before running this test.")
        }
        let sources = store.sources
        let source = try XCTUnwrap(sources.first(where: { $0.sourceType == .local }) ?? store.defaultCalendarForNewEvents?.source)
        let isolatedCalendar = EKCalendar(for: .event, eventStore: store)
        isolatedCalendar.title = "Avvi Integration Test \(UUID().uuidString)"
        isolatedCalendar.source = source
        try store.saveCalendar(isolatedCalendar, commit: true)
        let defaults = UserDefaults.standard
        let oldSources = defaults.object(forKey: "calendarSources")
        let oldDestination = defaults.object(forKey: "calendarDestination")
        defer {
            try? store.removeCalendar(isolatedCalendar, commit: true)
            defaults.set(oldSources, forKey: "calendarSources")
            defaults.set(oldDestination, forKey: "calendarDestination")
        }
        defaults.set([isolatedCalendar.calendarIdentifier], forKey: "calendarSources")
        defaults.set(isolatedCalendar.calendarIdentifier, forKey: "calendarDestination")
        let service = CalendarService()
        XCTAssertTrue(service.authorized)
        let habit = Habit(name: "Integration walk", symbol: "figure.walk", colorIndex: 0,
                          target: 30, step: 10, unit: "minutes")
        let today = Calendar.current.startOfDay(for: Date())
        let start = max(Date().addingTimeInterval(120), today.addingTimeInterval(18 * 3600))
        let proposal = ScheduleProposal(habitID: habit.id, start: start,
                                       end: start.addingTimeInterval(1800), reason: .preferredHour)
        try service.save(proposal, habit: habit)
        try service.save(proposal, habit: habit)
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-60),
            end: start.addingTimeInterval(3600), calendars: [isolatedCalendar])
        let events = store.events(matching: predicate)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Integration walk")
        XCTAssertEqual(events.first?.url?.scheme, "avvi")
        XCTAssertTrue(service.plannedHabitIDs.contains(habit.id))
        let anotherHabit = Habit(name: "Conflicting read", symbol: "book", colorIndex: 1,
                                target: 20, step: 5, unit: "pages")
        let conflicting = ScheduleProposal(habitID: anotherHabit.id, start: start.addingTimeInterval(900),
            end: start.addingTimeInterval(2700), reason: .preferredHour)
        XCTAssertThrowsError(try service.save(conflicting, habit: anotherHabit)) { error in
            guard case CalendarFailure.conflict = error else { return XCTFail("Expected calendar conflict, got \(error)") }
        }
        XCTAssertEqual(store.events(matching: predicate).count, 1)
    }
}
