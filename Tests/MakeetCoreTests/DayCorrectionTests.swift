import XCTest
import SwiftData
import MakeetCore
@testable import MakeetPersistence

final class DayCorrectionTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    @MainActor func testPastCorrectionsPreserveOtherDaysAndWeekdaysAfterReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([Habit.self, Activity.self])
        func open() throws -> ModelContainer { try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: directory.appendingPathComponent("data.store"), cloudKitDatabase: .none)]) }
        let context = ModelContext(try open())
        let day = date("2026-10-20T12:00:00Z"), now = date("2026-10-25T12:00:00Z")
        let habit = Habit(name: "Read", symbol: "book", colorIndex: 0, target: 5, step: 1, unit: "pages", createdAt: date("2026-10-19T00:00:00Z"), weekdayMask: 11)
        habit.timeZoneID = "UTC"
        context.insert(habit)
        context.insert(Activity(habitID: habit.id, amount: 3, timestamp: day.addingTimeInterval(-60)))
        context.insert(Activity(habitID: habit.id, amount: 2, timestamp: day))
        context.insert(Activity(habitID: habit.id, amount: 8, timestamp: now))
        try context.save()
        try SharedStore.correct([HabitDayCorrection(habitID: habit.id,date:day,quantity:1,expectedQuantity:5)],in:context,now:now)
        var reopened = ModelContext(try open())
        let saved = try XCTUnwrap(reopened.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(saved.weekdayMask,11)
        let savedSnapshot = saved.snapshot
        var entries = try reopened.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(entries.first(where:{$0.timestamp == day.addingTimeInterval(-60)})?.amount,1)
        XCTAssertEqual(entries.first(where:{$0.timestamp == now})?.amount,8)
        try SharedStore.correct([HabitDayCorrection(habitID:habit.id,date:day,quantity:7,expectedQuantity:1)],in:reopened,now:now)
        reopened = ModelContext(try open()); entries = try reopened.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(HabitEngine.progress(for:savedSnapshot,on:day,activities:entries.map(\.snapshot)).quantity,7)
        XCTAssertEqual(entries.first(where:{$0.source == "correction"})?.timestamp,day)
        XCTAssertEqual(try AccountRecords.snapshot(in:reopened).first(where:{$0.kind == .habit})?.habit?.weekdayMask,11)
        try SharedStore.deleteHabit(savedSnapshot.id,in:reopened)
        let final=ModelContext(try open())
        XCTAssertEqual(try final.fetchCount(FetchDescriptor<Habit>()),0)
        XCTAssertEqual(try final.fetchCount(FetchDescriptor<Activity>()),0)
    }
    @MainActor func testConcurrentChangeAndInvalidDaysRollbackEntireCorrection() throws {
        let container = try ModelContainer(for: Habit.self, Activity.self, configurations: ModelConfiguration(isStoredInMemoryOnly:true))
        let context = ModelContext(container)
        let day = date("2026-10-20T12:00:00Z"), now = date("2026-10-25T12:00:00Z")
        let first = Habit(name:"First",symbol:"leaf",colorIndex:0,target:1,step:1,unit:"times",createdAt:day)
        let second = Habit(name:"Second",symbol:"leaf",colorIndex:0,target:1,step:1,unit:"times",createdAt:day)
        first.timeZoneID="UTC"; second.timeZoneID="UTC"
        context.insert(first); context.insert(second);context.insert(Activity(habitID:second.id,amount:2,timestamp:day));try context.save()
        XCTAssertThrowsError(try SharedStore.correct([
            HabitDayCorrection(habitID:first.id,date:day,quantity:1,expectedQuantity:0),
            HabitDayCorrection(habitID:second.id,date:day,quantity:3,expectedQuantity:1)],in:context,now:now))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Activity>()),1)
        for invalid in [date("2026-10-19T12:00:00Z"),date("2026-10-26T12:00:00Z")] {
            XCTAssertThrowsError(try SharedStore.correct([HabitDayCorrection(habitID:first.id,date:invalid,quantity:1,expectedQuantity:0)],in:context,now:now))
        }
    }
}

extension DayCorrectionTests {
    @MainActor func testPermanentDeletionRemovesOnlyItsHistoryAndCreatesSyncTombstones() throws {
        let container = try ModelContainer(for: Habit.self, Activity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let first = Habit(name: "Remove", symbol: "leaf", colorIndex: 0, target: 1, step: 1, unit: "times")
        let second = Habit(name: "Keep", symbol: "leaf", colorIndex: 0, target: 1, step: 1, unit: "times")
        let removedID = first.id, keptID = second.id
        context.insert(first); context.insert(second)
        context.insert(Activity(habitID: removedID,amount: 3)); context.insert(Activity(habitID: keptID,amount: 7));try context.save()
        let before = try AccountRecords.snapshot(in: context)
        var ledger = SyncLedger(); _ = ledger.prepare(local: before)
        let accepted = before.map { record in var copy = record;copy.revision=1;return copy }
        _ = ledger.receive(SyncResponse(cursor: 4,changes: accepted,applied: accepted),local: before)
        try SharedStore.deleteHabit(removedID,in:context)
        let after = try AccountRecords.snapshot(in:context)
        XCTAssertEqual(after.count,2)
        XCTAssertEqual(after.first(where:{$0.kind == .habit})?.id,keptID)
        XCTAssertEqual(after.first(where:{$0.kind == .activity})?.activity?.amount,7)
        let deletes = ledger.prepare(local:after).changes
        XCTAssertEqual(deletes.count,2);XCTAssertTrue(deletes.allSatisfy(\.deleted))
        try SharedStore.deleteHabit(removedID,in:context)
        XCTAssertEqual(try AccountRecords.snapshot(in:context),after)
    }
    @MainActor func testRemoteParentDeletionDoesNotLeaveOrRecreateOrphanActivities() throws {
        let container=try ModelContainer(for:Habit.self,Activity.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let context=ModelContext(container)
        let habit=Habit(name:"Remove",symbol:"leaf",colorIndex:0,target:1,step:1,unit:"times")
        context.insert(habit);context.insert(Activity(habitID:habit.id,amount:4));try context.save()
        let before=try AccountRecords.snapshot(in:context)
        let parent=try XCTUnwrap(before.first(where:{$0.kind == .habit}))
        let child=try XCTUnwrap(before.first(where:{$0.kind == .activity}))
        try AccountRecords.apply([parent.tombstone()],in:context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Activity>()),0)
        try AccountRecords.apply([child],in:context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Activity>()),0)
        var ledger=SyncLedger();_=ledger.prepare(local:before)
        ledger.reject(conflicts:[parent.tombstone()],local:before)
        XCTAssertTrue(try XCTUnwrap(ledger.resolve(parent.key,keepLocal:true)).deleted)
    }
}
