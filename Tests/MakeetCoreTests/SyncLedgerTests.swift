import XCTest
import MakeetCore

final class SyncLedgerTests: XCTestCase {
    private func habit() -> SyncRecord {
        SyncRecord(id: UUID(), habit: HabitRecord(name: "Read", symbol: "emoji:📚", colorIndex: 0, target: 20, step: 5,
            unit: "pages", createdAt: Date(timeIntervalSince1970: 1_700_000_000), timeZoneID: "Europe/Rome",
            preferredHour: 18, durationMinutes: 20, archived: false))
    }

    func testDurableBatchRetryKeepsMutationAndPreservesEditsDuringRequest() throws {
        var ledger = SyncLedger(); let original = habit()
        let request = ledger.prepare(local: [original])
        var recovered = try AccountCoding.decoder().decode(SyncLedger.self, from: AccountCoding.encoder().encode(ledger))
        var edited = original; edited.habit?.name = "Read more"
        XCTAssertEqual(recovered.prepare(local: [edited]), request)
        var applied = original; applied.revision = 1
        XCTAssertTrue(recovered.receive(SyncResponse(cursor: 1, changes: [applied], applied: [applied]), local: [edited]).isEmpty)
        let next = recovered.prepare(local: [edited])
        XCTAssertNotEqual(next.mutationID, request.mutationID)
        XCTAssertEqual(next.changes.first?.revision, 1)
        XCTAssertEqual(next.changes.first?.habit?.name, "Read more")
    }

    func testLatestRemoteRevisionWinsWithoutFalseConflictAndOldPullDoesNotRegress() {
        var ledger = SyncLedger(); var first = habit(); first.revision = 1
        _ = ledger.prepare(local: [])
        var second = first; second.revision = 2; second.habit?.name = "Changed remotely"
        let updates = ledger.receive(SyncResponse(cursor: 2, changes: [first, second]), local: [])
        XCTAssertEqual(updates, [second]); XCTAssertTrue(ledger.conflicts.isEmpty)
        _ = ledger.prepare(local: [second])
        XCTAssertTrue(ledger.receive(SyncResponse(cursor: 3, changes: [first]), local: [second]).isEmpty)
        XCTAssertEqual(ledger.baseline[first.key]?.revision, 2)
    }

    func testEditDuringPullRequiresChoiceWhenAnotherDeviceChangedSameRecord() {
        var ledger = SyncLedger(); var cloud = habit(); cloud.revision = 1
        _ = ledger.prepare(local: [])
        _ = ledger.receive(SyncResponse(cursor: 1, changes: [cloud]), local: [])
        _ = ledger.prepare(local: [cloud])
        var mine = cloud; mine.habit?.name = "Edited while pulling"
        var theirs = cloud; theirs.revision = 2; theirs.habit?.name = "Other device"
        XCTAssertTrue(ledger.receive(SyncResponse(cursor: 2, changes: [theirs]), local: [mine]).isEmpty)
        XCTAssertEqual(ledger.conflicts.count, 1)
        XCTAssertEqual(ledger.resolve(theirs.key, keepLocal: false), theirs)
    }

    func testConflictingEditsRequireExplicitChoiceAndDeletionUsesTombstone() {
        var ledger = SyncLedger(); var cloud = habit(); cloud.revision = 1
        _ = ledger.prepare(local: [])
        _ = ledger.receive(SyncResponse(cursor: 1, changes: [cloud]), local: [])
        var mine = cloud; mine.habit?.name = "My change"
        _ = ledger.prepare(local: [mine])
        var theirs = cloud; theirs.revision = 2; theirs.habit?.name = "Their change"
        ledger.reject(conflicts: [theirs], local: [mine])
        XCTAssertEqual(ledger.conflicts.count, 1)
        XCTAssertTrue(ledger.prepare(local: [mine]).changes.isEmpty)
        _ = ledger.receive(SyncResponse(cursor: 2, changes: [theirs]), local: [mine])
        XCTAssertNil(ledger.resolve(theirs.key, keepLocal: true))
        XCTAssertEqual(ledger.prepare(local: [mine]).changes.first?.revision, 2)
        _ = ledger.receive(SyncResponse(cursor: 3, changes: [], applied: []), local: [mine])
        let deleted = ledger.prepare(local: []).changes
        XCTAssertEqual(deleted.count, 1); XCTAssertTrue(deleted[0].deleted)
    }

    func testIndependentActivityIDsSurviveAndBatchesStayBoundedWithHabitsFirst() {
        var ledger = SyncLedger(); let parent = habit()
        let entries = (0..<110).map { _ in SyncRecord(id: UUID(), activity: ActivityRecord(habitID: parent.id, amount: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), source: "widget")) }
        let request = ledger.prepare(local: entries + [parent])
        XCTAssertEqual(request.changes.count, 100); XCTAssertEqual(request.changes.first?.kind, .habit)
        XCTAssertEqual(Set(request.changes.map(\.key)).count, 100)
    }

    func testWireDecodesServerDatesAndTombstones() throws {
        let original = habit()
        let encoded = try AccountCoding.encoder().encode(original)
        XCTAssertEqual(try AccountCoding.decoder().decode(SyncRecord.self, from: encoded), original)
        let tombstone = original.tombstone()
        XCTAssertEqual(try AccountCoding.decoder().decode(SyncRecord.self, from: AccountCoding.encoder().encode(tombstone)), tombstone)
        let challenge = try AccountCoding.decoder().decode(AccountChallenge.self, from: Data("{\"id\":\"challenge\",\"nonce\":\"nonce\",\"expires_at\":1700000000}".utf8))
        XCTAssertEqual(challenge.expiresAt, 1_700_000_000)
    }
}
