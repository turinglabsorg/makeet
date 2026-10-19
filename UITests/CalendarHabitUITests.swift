import XCTest

final class CalendarHabitUITests: XCTestCase {
    @MainActor func testExternalPurchaseIntentCannotOpenSubscriptionsInTheFreeRelease() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--onboarding", "--demo", "--external-purchase-intent", "-AppleLanguages", "(it)"]
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plusDone"].exists)
        app.buttons["onboardingContinue"].tap()
        app.buttons["onboardingLocalChoice"].tap()
        app.buttons["onboardingLocal"].tap()
        app.buttons["onboardingFinish"].tap()
        XCTAssertTrue(app.buttons["increment-Bere acqua"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plusDone"].exists)
        XCTAssertFalse(app.buttons["purchase-org.turinglabs.makeet.plus.monthly"].exists)
        XCTAssertFalse(app.buttons["purchase-org.turinglabs.makeet.plus.yearly"].exists)
        XCTAssertTrue(app.buttons["increment-Bere acqua"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4 / 8 bicchieri"].exists)
    }

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
        guard name.waitForExistence(timeout:5) else { attach("New habit form missing",app);XCTFail("New habit name field did not appear");return }
        name.tap();name.typeText("Weekly habit")
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
        attach("Weekly editor before returning to name",app)
        let editedName=app.textFields["habitName"]
        guard editedName.waitForExistence(timeout:5) else { attach("Weekly editor missing name",app);XCTFail("Edited habit name field did not appear");return }
        editedName.tap()
        editedName.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:"Weekly habit".count)+"Weekly edited")
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
    @MainActor func testFreeAccessIncludesAccountSyncAndExportsData() {
        let app = launch()
        app.buttons["accountSettings"].tap()
        let free = app.staticTexts["freeAccessInfo"];reveal(free,in:app)
        XCTAssertTrue(free.label.contains("gratuite"))
        XCTAssertFalse(app.buttons["showMakeetPlus"].exists)
        attach("Account sync and all local features are free",app)
        let export = app.buttons["exportData"];reveal(export,in:app);export.tap()
        let saveExport = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(saveExport.waitForExistence(timeout:30))
        attach("System exporter ready to save",app)
        saveExport.tap()
        XCTAssertTrue(saveExport.waitForNonExistence(timeout:15))
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


extension CalendarHabitUITests {
    @MainActor private func createFlexibleHabit(_ name: String, limit: Bool, negative: Bool, in app: XCUIApplication) {
        app.buttons["addHabit"].tap()
        let field = app.textFields["habitName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
        if app.buttons["habitKeyboardDone"].exists { app.buttons["habitKeyboardDone"].tap() }
        let goal = app.segmentedControls["habitGoal"]
        reveal(goal.buttons.element(boundBy: 0), in: app)
        if limit {
            goal.buttons.element(boundBy: 1).tap()
            XCTAssertTrue(goal.buttons.element(boundBy: 1).isSelected)
            let target = app.textFields["habitTarget"]; reveal(target, in: app)
            XCTAssertEqual(target.value as? String, "0")
        }
        let toggle = app.switches["allowNegative"]; reveal(toggle, in: app)
        if negative {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        attach("Flexible goal editor \(name)", app)
        app.buttons["saveHabit"].tap()
        XCTAssertTrue(app.buttons["increment-\(name)"].waitForExistence(timeout: 5))
    }

    @MainActor func testZeroLimitMalusNegativeBalanceAndCalendarCorrection() {
        continueAfterFailure = false
        let app = launch(demo: false)
        createFlexibleHabit("Beer", limit: true, negative: false, in: app)
        XCTAssertTrue(app.buttons["confirm-zero-Beer"].exists)
        XCTAssertFalse(app.buttons["decrement-Beer"].isEnabled)
        app.buttons["confirm-zero-Beer"].tap()
        XCTAssertFalse(app.buttons["confirm-zero-Beer"].exists)
        app.buttons["increment-Beer"].tap(); app.buttons["increment-Beer"].tap()
        XCTAssertTrue(app.staticTexts["progress-Beer"].label.hasPrefix("2 /"))
        XCTAssertTrue(app.staticTexts["Malus: 2 volte"].exists)
        attach("Zero limit with two occurrences as malus", app)
        app.buttons["decrement-Beer"].tap(); app.buttons["decrement-Beer"].tap()
        XCTAssertTrue(app.staticTexts["progress-Beer"].label.hasPrefix("0 /"))
        XCTAssertFalse(app.buttons["confirm-zero-Beer"].exists)
        createFlexibleHabit("Balance", limit: false, negative: true, in: app)
        app.buttons["decrement-Balance"].tap()
        XCTAssertTrue(app.staticTexts["progress-Balance"].label.hasPrefix("-1 /"))
        attach("Signed negative balance in Today", app)
        app.tabBars.buttons["Calendario"].tap()
        let edit = app.buttons["editCalendarDay"]; reveal(edit, in: app); edit.tap()
        let minus = app.buttons["day-decrement-Balance"]; reveal(minus, in: app); minus.tap()
        XCTAssertTrue(app.staticTexts["day-quantity-Balance"].label.hasPrefix("-2 "))
        app.buttons["saveCalendarDay"].tap()
        reveal(edit, in: app); edit.tap()
        XCTAssertTrue(app.staticTexts["day-quantity-Balance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["day-quantity-Balance"].label.hasPrefix("-2 "))
        app.buttons["day-zero-Balance"].tap()
        app.buttons["Annulla"].tap()
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.staticTexts["progress-Balance"].label.hasPrefix("-2 /"))
        app.staticTexts["Balance"].tap()
        XCTAssertTrue(app.staticTexts["-1 volte"].waitForExistence(timeout: 5))
        attach("Negative values in statistics and registration history", app)
    }

    @MainActor func testZeroGoalCreationIsLocalizedInFiveLanguages() {
        continueAfterFailure = false
        for language in ["it", "en", "fr", "de", "es"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "-AppleLanguages", "(\(language))"]
            app.launch()
            createFlexibleHabit("Zero", limit: true, negative: true, in: app)
            XCTAssertTrue(app.buttons["confirm-zero-Zero"].exists, language)
            app.buttons["confirm-zero-Zero"].tap()
            XCTAssertTrue(app.buttons["decrement-Zero"].isEnabled, language)
            app.buttons["decrement-Zero"].tap()
            XCTAssertTrue(app.staticTexts["progress-Zero"].label.contains("1"), language)
            attach("Localized zero and signed goal \(language)", app)
            app.terminate()
        }
    }

    @MainActor func testPlanningAndLocalTrackingStayFreeWithoutPlus() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.staticTexts["4 / 8 bicchieri"].waitForExistence(timeout: 5))
        app.buttons["increment-Bere acqua"].tap()
        XCTAssertTrue(app.staticTexts["5 / 8 bicchieri"].exists)
        app.tabBars.buttons["Il tuo piano"].tap()
        XCTAssertTrue(app.segmentedControls["planningHorizon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Makeet Plus"].exists)
        attach("Planning is available without Plus", app)
        app.tabBars.buttons["Calendario"].tap()
        XCTAssertTrue(app.buttons["calendar-day-1"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Oggi"].tap()
        XCTAssertTrue(app.staticTexts["5 / 8 bicchieri"].waitForExistence(timeout: 5))
        app.buttons["decrement-Bere acqua"].tap()
        XCTAssertTrue(app.staticTexts["4 / 8 bicchieri"].exists)
        attach("Local tracking stays free", app)
    }
}
