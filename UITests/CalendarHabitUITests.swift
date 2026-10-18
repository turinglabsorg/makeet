import XCTest

final class CalendarHabitUITests: XCTestCase {
    @MainActor private func launch(demo: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"] + (demo ? ["--demo"] : [])
        app.launch(); return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func attach(_ name: String, _ app: XCUIApplication) {
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = name; proof.lifetime = .keepAlways; add(proof)
    }
    @MainActor func testHeaderAndWeeklyCreationEditingAndEmptySelection() {
        let app = launch(demo:false)
        XCTAssertLessThan(app.buttons["addHabit"].frame.maxX, app.buttons["accountSettings"].frame.minX)
        XCTAssertFalse(app.staticTexts["Account"].exists)
        XCTAssertFalse(app.buttons["Abitudini archiviate"].exists)
        app.buttons["addHabit"].tap()
        let name=app.textFields["habitName"]
        XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("Weekly habit")
        app.swipeDown()
        for day in 0..<7 { let button=app.buttons["weekday-\(day)"];XCTAssertTrue(button.exists);button.tap() }
        XCTAssertFalse(app.buttons["saveHabit"].isEnabled)
        for day in [0,1,3] { app.buttons["weekday-\(day)"].tap() }
        attach("Weekdays chosen on creation",app)
        app.buttons["saveHabit"].tap()
        app.tabBars.buttons["Calendario"].tap()
        let edit=app.buttons["edit-habit-Weekly habit"];reveal(edit,in:app);edit.tap()
        let monday=app.buttons["weekday-0"];XCTAssertTrue(monday.exists);monday.tap();monday.tap()
        for day in 0..<7 { XCTAssertEqual(app.buttons["weekday-\(day)"].isSelected,[0,1,3].contains(day)) }
        app.swipeDown();app.swipeDown()
        XCTAssertTrue(name.waitForExistence(timeout:5));name.tap()
        name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:"Weekly habit".count)+"Weekly edited")
        app.buttons["saveHabit"].tap()
        XCTAssertTrue(app.buttons["edit-habit-Weekly edited"].waitForExistence(timeout:5))
        attach("Edited habit in monthly calendar",app)
    }
    @MainActor func testPastDayCorrectionSavesCancelsAndKeepsTodaySeparate() {
        let app=launch()
        app.tabBars.buttons["Calendario"].tap()
        let previous=Calendar.current.date(byAdding:.day,value:-1,to:Date())!
        if !Calendar.current.isDate(previous,equalTo:Date(),toGranularity:.month) { app.buttons["previousMonth"].tap() }
        app.buttons["calendar-day-\(Calendar.current.component(.day,from:previous))"].tap()
        let edit=app.buttons["editCalendarDay"];reveal(edit,in:app);XCTAssertTrue(edit.isEnabled);edit.tap()
        let quantity=app.staticTexts["day-quantity-Bere acqua"]
        XCTAssertTrue(quantity.waitForExistence(timeout:5))
        let original=quantity.label
        app.buttons["day-increment-Bere acqua"].tap()
        let updated=quantity.label;XCTAssertNotEqual(original,updated)
        app.buttons["saveCalendarDay"].tap()
        reveal(edit,in:app);edit.tap()
        XCTAssertTrue(quantity.waitForExistence(timeout:5));XCTAssertEqual(quantity.label,updated)
        app.buttons["day-decrement-Bere acqua"].tap()
        app.buttons["Annulla"].tap()
        reveal(edit,in:app);edit.tap()
        XCTAssertTrue(quantity.waitForExistence(timeout:5));XCTAssertEqual(quantity.label,updated)
        attach("Past day correction persisted",app)
        app.buttons["Annulla"].tap()
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.staticTexts["4 / 8 bicchieri"].waitForExistence(timeout:5))
    }
    @MainActor func testPermanentDeletionRequiresConfirmationAndSurvivesNavigation() {
        let app=launch()
        app.staticTexts["Bere acqua"].tap()
        app.buttons["deleteHabit"].tap()
        XCTAssertTrue(app.buttons["confirmDeleteHabit"].waitForExistence(timeout:5))
        attach("Permanent deletion review",app)
        app.buttons["Annulla"].tap()
        XCTAssertTrue(app.buttons["deleteHabit"].waitForExistence(timeout:5))
        app.buttons["deleteHabit"].tap()
        app.buttons["confirmDeleteHabit"].tap()
        XCTAssertTrue(app.staticTexts["Abitudine eliminata"].waitForExistence(timeout:10))
        app.buttons["Torna alle abitudini"].tap()
        XCTAssertFalse(app.buttons["increment-Bere acqua"].exists)
        XCTAssertTrue(app.buttons["increment-Leggere"].exists)
        app.tabBars.buttons["Calendario"].tap()
        reveal(app.buttons["edit-habit-Leggere"],in:app)
        XCTAssertFalse(app.buttons["edit-habit-Bere acqua"].exists)
        app.tabBars.buttons["Andamento"].tap()
        XCTAssertFalse(app.staticTexts["Bere acqua"].exists)
        XCTAssertTrue(app.staticTexts["Leggere"].exists)
        attach("Deleted habit absent across screens",app)
    }
    @MainActor func testPlanningHorizonCopyAndReviewCancellation() {
        let app=launch()
        app.tabBars.buttons["Il tuo piano"].tap()
        XCTAssertFalse(app.staticTexts["Calendari del dispositivo collegati"].exists)
        let period=app.segmentedControls["planningHorizon"]
        XCTAssertTrue(period.waitForExistence(timeout:5))
        period.buttons["Oggi"].tap()
        let today=app.staticTexts["Cosa hai da fare oggi"];reveal(today,in:app);XCTAssertTrue(today.exists)
        period.buttons["2 settimane"].tap()
        let future=app.staticTexts["Cosa hai da fare nei prossimi giorni"];reveal(future,in:app);XCTAssertTrue(future.exists)
        let review=app.buttons["reviewFuturePlan"]
        if review.isEnabled {
            reveal(review,in:app);review.tap()
            XCTAssertTrue(app.buttons["confirmFuturePlan"].waitForExistence(timeout:5))
            attach("Future calendar plan awaits confirmation",app)
            app.buttons["Annulla"].tap()
            XCTAssertTrue(period.waitForExistence(timeout:5))
        } else {
            XCTAssertTrue(review.exists)
            XCTAssertTrue(app.buttons["Collega calendario"].exists)
        }
        attach("Multi-week planning",app)
    }
}

extension CalendarHabitUITests {
    @MainActor func testPlusExplainsFreeLocalUseAndExportsData() {
        let app = launch()
        app.buttons["accountSettings"].tap()
        let plus = app.buttons["showMakeetPlus"];reveal(plus,in:app);plus.tap()
        XCTAssertTrue(app.staticTexts["Makeet Plus"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["appleSignIn"].exists)
        XCTAssertTrue(app.buttons["googleSignIn"].exists)
        attach("Plus preserves the free local choice",app)
        app.buttons["plusDone"].tap()
        let export = app.buttons["exportData"];reveal(export,in:app);export.tap()
        let saveExport = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(saveExport.waitForExistence(timeout:5))
        attach("System exporter ready to save",app)
        saveExport.tap()
        XCTAssertTrue(saveExport.waitForNonExistence(timeout:5))
        XCTAssertTrue(app.buttons["exportData"].waitForExistence(timeout:5))
        app.buttons["Fine"].tap()
        XCTAssertTrue(app.buttons["increment-Bere acqua"].exists)
    }
}

extension CalendarHabitUITests {
    @MainActor func testCalendarSetupExplainsMissingSelectionWithoutSuccessBanner() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--profile-fixture", "--demo", "-AppleLanguages", "(it)"]
        app.launch()
        app.tabBars.buttons["Il tuo piano"].tap()
        XCTAssertFalse(app.staticTexts["Calendari del dispositivo collegati"].exists)
        let choose = app.buttons["choosePlanningCalendars"]
        if choose.exists { reveal(choose,in:app);choose.tap() }
        else { app.buttons["Connessioni"].tap() }
        let selectAll = app.buttons["Seleziona tutti i calendari"]
        let authorize = app.buttons["Consenti accesso al calendario"]
        for _ in 0..<6 {
            if selectAll.isHittable || authorize.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(selectAll.isHittable || authorize.isHittable)
        attach("Calendar setup offers an actionable choice",app)
        app.buttons["Fine"].tap()
        XCTAssertTrue(app.segmentedControls["planningHorizon"].waitForExistence(timeout:5))
    }
}
