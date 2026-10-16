import XCTest

final class MakeetUITests: XCTestCase {
    @MainActor func testCreateLogTwiceAndUndoOneRegistration() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["addHabit"].tap()
        let name = app.textFields["habitName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Focus test")
        app.buttons["saveHabit"].tap()
        let increment = app.buttons["increment-Focus test"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        increment.tap(); increment.tap()
        XCTAssertTrue(app.staticTexts["2 / 3 volte"].waitForExistence(timeout: 5))
        app.staticTexts["Focus test"].tap()
        let undo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Annulla registrazione")).firstMatch
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Annulla registrazione")).count, 1)
        attach("Habit detail", app)
        app.buttons["Archivia abitudine"].tap()
        app.buttons["Archivia"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.buttons["Torna alle abitudini"].waitForExistence(timeout: 5))
        app.buttons["Torna alle abitudini"].tap()
        app.buttons["Abitudini archiviate"].tap()
        XCTAssertTrue(app.staticTexts["Focus test"].waitForExistence(timeout: 5))
        app.buttons["Ripristina"].tap()
        app.buttons["Fine"].tap()
        XCTAssertTrue(app.buttons["increment-Focus test"].waitForExistence(timeout: 5))
    }

    @MainActor func testDemoScreensAndDisconnectedCalendarState() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Bere acqua"].waitForExistence(timeout: 10))
        attach("Today", app)
        app.tabBars.buttons["Andamento"].tap()
        XCTAssertTrue(app.staticTexts["Ogni passo lascia\nun segno."].waitForExistence(timeout: 5))
        attach("Trends", app)
        app.tabBars.buttons["Il tuo piano"].tap()
        app.buttons["Connessioni"].tap()
        XCTAssertTrue(app.staticTexts["notificationPermission"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["iCloud tra dispositivi, Da attivare"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Google diretto, Da integrare"].exists)
        attach("Connections", app)
    }

    @MainActor private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
