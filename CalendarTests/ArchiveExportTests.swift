import XCTest
import SwiftData
@testable import Makeet

final class ArchiveExportTests: XCTestCase {
    @MainActor func testLocalExportIncludesProgressAndNeverCredentials() async throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { throw XCTSkip("Requires isolated in-memory test archive") }
        let account = AccountManager()
        let context = try XCTUnwrap(account.container?.mainContext)
        let habit = Habit(name: "Export habit", symbol: "leaf", colorIndex: 0, target: 2, step: 1, unit: "times", weekdayMask: 11)
        context.insert(habit); context.insert(Activity(habitID: habit.id, amount: 1)); try context.save()
        let data = try await account.exportData(in: context)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["device_records"] as? [Any])?.count, 2)
        XCTAssertNil(object["server_records"])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("Export habit")); XCTAssertTrue(text.contains("weekday_mask"))
        XCTAssertFalse(text.contains("access_token")); XCTAssertFalse(text.contains("refresh_token"))
    }
}
