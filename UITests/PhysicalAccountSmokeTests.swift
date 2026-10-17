import XCTest

final class PhysicalAccountSmokeTests: XCTestCase {
    @MainActor func testExistingAccountRestoresAndOpensSettings() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an explicitly selected physical iPhone with an existing Makeet account.")
        #else
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let settings = app.buttons["accountSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.buttons["accountSyncNow"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["lastAccountSync"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.state, .runningForeground)
        #endif
    }
}
