import XCTest

final class ProfileEditorUITests: XCTestCase {
    @MainActor func testFreeAccountDeletionExplainsErasureAndAllowsCancellationInFiveLanguages() {
        for (language, connections, delete, erase, manage, cancel, warning) in [
            ("it", "Connessioni", "Elimina account", "Elimina account e dati", "Gestisci abbonamento", "Annulla", "non può essere annullata"),
            ("en", "Connections", "Delete account", "Delete account and data", "Manage subscription", "Cancel", "cannot be undone"),
            ("fr", "Connexions", "Supprimer le compte", "Supprimer le compte et les données", "Gérer l’abonnement", "Annuler", "est irréversible"),
            ("de", "Verbindungen", "Konto löschen", "Konto und Daten löschen", "Abonnement verwalten", "Abbrechen", "nicht rückgängig gemacht"),
            ("es", "Conexiones", "Eliminar cuenta", "Eliminar cuenta y datos", "Gestionar suscripción", "Cancelar", "no se puede deshacer")
        ] {
            let app = profileApp(language: language)
            app.launch()
            app.buttons["accountSettings"].tap()
            for attempt in 1...2 {
                app.buttons[delete].tap()
                XCTAssertTrue(app.buttons[erase].waitForExistence(timeout: 5), language)
                XCTAssertTrue(app.buttons[erase].isEnabled, language)
                XCTAssertFalse(app.buttons[manage].exists, language)
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", warning)).firstMatch.exists, language)
                attach("Free account erasure confirmation \(language) \(attempt)", app)
                cancelConfirmation(app, action: erase, cancel: cancel, navigation: connections)
                XCTAssertTrue(app.staticTexts["Alex Morgan"].exists, language)
                XCTAssertTrue(app.buttons["editProfile"].isHittable, language)
            }
            app.terminate()
        }
    }

    @MainActor func testAccountActionsAskForConfirmationAndCanBeCancelled() {
        let app = profileApp()
        app.launch()
        app.buttons["accountSettings"].tap()
        app.buttons["Importa l’archivio locale"].tap()
        XCTAssertTrue(app.buttons["Conferma importazione"].waitForExistence(timeout: 5))
        attach("Account import confirmation", app)
        cancelConfirmation(app, action: "Conferma importazione")
        XCTAssertTrue(app.navigationBars["Connessioni"].waitForExistence(timeout: 5))
        app.buttons["Elimina account"].tap()
        XCTAssertTrue(app.buttons["Elimina account e dati"].waitForExistence(timeout: 5))
        attach("Account deletion confirmation", app)
        cancelConfirmation(app, action: "Elimina account e dati")
        XCTAssertTrue(app.navigationBars["Connessioni"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alex Morgan"].exists)
    }

    @MainActor func testProfilePhotoSelectionRemovalAndPickerCancellation() {
        let app = profileApp(extra: ["--profile-photo-fixture"])
        app.launch()
        app.buttons["accountSettings"].tap()
        app.buttons["editProfile"].tap()
        XCTAssertTrue(app.buttons["removeProfilePhoto"].waitForExistence(timeout: 5))
        app.buttons["chooseProfilePhoto"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Foto"].waitForExistence(timeout: 10))
        attach("System photo picker", app)
        app.navigationBars["Foto"].buttons["Cancel"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Foto"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertTrue(app.textFields["profileName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["profileName"].isHittable)
        XCTAssertTrue(app.buttons["removeProfilePhoto"].exists)
        app.buttons["removeProfilePhoto"].tap()
        XCTAssertFalse(app.buttons["removeProfilePhoto"].exists)
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 5))
        app.buttons["editProfile"].tap()
        XCTAssertTrue(app.textFields["profileName"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["removeProfilePhoto"].exists)
        attach("Removed photo remains absent", app)
        app.buttons["chooseProfilePhoto"].tap()
        let sample = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()
        XCTAssertTrue(app.buttons["removeProfilePhoto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["saveProfile"].isEnabled)
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 5))
        app.buttons["editProfile"].tap()
        XCTAssertTrue(app.buttons["removeProfilePhoto"].waitForExistence(timeout: 5))
        attach("Selected system photo persists", app)
    }

    @MainActor func testConflictDoesNotOverwriteAnotherDeviceOnRetry() {
        let app = profileApp(extra: ["--profile-save-conflict"])
        app.launch()
        app.buttons["accountSettings"].tap()
        app.buttons["editProfile"].tap()
        let name = app.textFields["profileName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replace(name, with: "Stale draft")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["profileError"].waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Stale draft")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["profileError"].waitForExistence(timeout: 5))
        XCTAssertTrue(name.exists)
        app.buttons["Annulla"].tap()
        XCTAssertTrue(app.staticTexts["Other device"].waitForExistence(timeout: 5))
        app.buttons["editProfile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Other device")
    }

    @MainActor func testAuthenticatedUpdateGuideCanEditProfileWithoutFinishingEarly() {
        let app = profileApp(extra: ["--onboarding"])
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 5))
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.buttons["onboardingProfile"].waitForExistence(timeout: 5))
        app.buttons["onboardingProfile"].tap()
        let name = app.textFields["profileName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replace(name, with: "Guide profile")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Guide profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingFinish"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.buttons["onboardingFinish"].tap()
        XCTAssertTrue(app.tabBars.buttons["Oggi"].waitForExistence(timeout: 5))
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.staticTexts["Guide profile"].waitForExistence(timeout: 5))
    }

    @MainActor func testProfileEditorSavesCancelsAndReopensFromTodayAndPlanner() {
        let app = profileApp()
        app.launch()
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.staticTexts["Alex Morgan"].waitForExistence(timeout: 5))
        app.buttons["editProfile"].tap()
        let name = app.textFields["profileName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.isHittable)
        attach("Profile editor opened from Today", app)
        replace(name, with: "Taylor Green")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Taylor Green"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Connessioni"].exists)
        app.buttons["editProfile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Taylor Green")
        replace(name, with: "Unsaved change")
        app.buttons["Annulla"].tap()
        XCTAssertTrue(app.staticTexts["Taylor Green"].waitForExistence(timeout: 5))
        app.buttons["Fine"].tap()
        app.tabBars.buttons["Il tuo piano"].tap()
        app.buttons["Connessioni"].tap()
        app.buttons["editProfile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Taylor Green")
        app.buttons["Annulla"].tap()
        app.buttons["Fine"].tap()
        XCTAssertTrue(app.tabBars.buttons["Il tuo piano"].isSelected)
        app.terminate(); app.launch()
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.staticTexts["Taylor Green"].waitForExistence(timeout: 5))
        attach("Saved profile after relaunch", app)
    }

    @MainActor func testFailedSaveKeepsTheEditorAndDraft() {
        let app = profileApp(extra: ["--profile-save-error"])
        app.launch()
        app.buttons["accountSettings"].tap()
        app.buttons["editProfile"].tap()
        let name = app.textFields["profileName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replace(name, with: "Retry this name")
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["profileError"].waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Retry this name")
        XCTAssertTrue(app.staticTexts["profileError"].isHittable)
        XCTAssertTrue(app.buttons["saveProfile"].isEnabled)
        attach("Failed save retains draft", app)
        app.buttons["Annulla"].tap()
        XCTAssertTrue(app.staticTexts["Alex Morgan"].waitForExistence(timeout: 5))
    }

    @MainActor private func profileApp(extra: [String] = [], language: String = "it") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--profile-fixture", "-AppleLanguages", "(\(language))"] + extra
        app.launchEnvironment["MAKEET_PROFILE_FIXTURE_ID"] = UUID().uuidString
        return app
    }
    @MainActor private func cancelConfirmation(_ app: XCUIApplication, action: String, cancel: String = "Annulla", navigation: String = "Connessioni") {
        if app.buttons[cancel].exists { app.buttons[cancel].tap() }
        else { app.navigationBars[navigation].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons[action])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }
    @MainActor private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + text)
    }
    @MainActor private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
