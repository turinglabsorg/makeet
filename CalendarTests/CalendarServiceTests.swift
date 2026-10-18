import XCTest
import EventKit
@testable import Makeet

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
        isolatedCalendar.title = "Makeet Integration Test \(UUID().uuidString)"
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
        XCTAssertEqual(events.first?.url?.scheme, "makeet")
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

extension CalendarServiceTests {
    @MainActor func testFutureBatchAllDayRecurrenceAndConfirmedCleanup() async throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else { throw XCTSkip("Only isolated Simulator calendars may be changed.") }
        guard EKEventStore.authorizationStatus(for:.event) == .fullAccess else { throw XCTSkip("Grant calendar permission to this Simulator test host.") }
        let store=EKEventStore()
        let calendar=EKCalendar(for:.event,eventStore:store)
        calendar.title="Makeet Future Test \(UUID().uuidString)"
        calendar.source=try XCTUnwrap(store.sources.first(where:{$0.sourceType == .local}) ?? store.defaultCalendarForNewEvents?.source)
        try store.saveCalendar(calendar,commit:true)
        let scope="calendar-test-"+UUID().uuidString
        let defaults=UserDefaults.standard
        defaults.set([calendar.calendarIdentifier],forKey:scope+".calendarSources")
        defaults.set(calendar.calendarIdentifier,forKey:scope+".calendarDestination")
        defer {
            try? store.removeCalendar(calendar,commit:true)
            defaults.removeObject(forKey:scope+".calendarSources");defaults.removeObject(forKey:scope+".calendarDestination")
        }
        let service=CalendarService(scope:scope)
        let habit=Habit(name:"Future test",symbol:"leaf",colorIndex:0,target:1,step:1,unit:"times",weekdayMask:11)
        let initial=ScheduleEngine.propose(habits:[habit.snapshot],activities:[],busy:[],days:14)
        XCTAssertGreaterThanOrEqual(initial.count,5)
        let last=try XCTUnwrap(initial.last)
        let blocker=EKEvent(eventStore:store);blocker.calendar=calendar;blocker.title="Keep external event"
        blocker.startDate=last.start;blocker.endDate=last.end;try store.save(blocker,span:.thisEvent)
        service.refresh()
        XCTAssertThrowsError(try service.save(initial,habits:[habit]))
        XCTAssertEqual(service.events.count,1)
        let plans=ScheduleEngine.propose(habits:[habit.snapshot],activities:[],busy:service.busy,days:14)
        try service.save(plans,habits:[habit]);try service.save(plans,habits:[habit])
        XCTAssertEqual(service.plannedOccurrences.count,plans.count)
        XCTAssertTrue(service.plannedOccurrences.allSatisfy { habit.snapshot.isScheduled(on:$0.start) })
        XCTAssertTrue(ScheduleEngine.propose(habits:[habit.snapshot],activities:[],busy:service.busy,days:14,planned:service.plannedOccurrences).isEmpty)
        let tomorrow=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:Date()))!
        let repeated=EKEvent(eventStore:store);repeated.calendar=calendar;repeated.title="Keep recurring all-day"
        repeated.startDate=tomorrow;repeated.endDate=Calendar.current.date(byAdding:.day,value:2,to:tomorrow)!;repeated.isAllDay=true
        repeated.recurrenceRules=[EKRecurrenceRule(recurrenceWith:.weekly,interval:1,end:EKRecurrenceEnd(occurrenceCount:3))]
        try store.save(repeated,span:.thisEvent)
        service.show(Calendar.current.dateInterval(of:.month,for:Calendar.current.date(byAdding:.month,value:-1,to:Date())!)!)
        XCTAssertEqual(service.events.filter{$0.title == "Keep recurring all-day"}.count,3)
        XCTAssertEqual(Set(service.events.map(\.occurrenceID)).count,service.events.count)
        XCTAssertTrue(service.events(on:Calendar.current.date(byAdding:.day,value:1,to:tomorrow)!).contains{$0.title == "Keep recurring all-day"})
        try service.removeFutureBlocks(for:habit.id)
        XCTAssertFalse(service.events.contains{$0.makeetHabitID == habit.id})
        XCTAssertTrue(service.events.contains{$0.title == "Keep external event"})
        XCTAssertEqual(service.events.filter{$0.title == "Keep recurring all-day"}.count,3)
    }
}
