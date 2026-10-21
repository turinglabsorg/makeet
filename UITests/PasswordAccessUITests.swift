import XCTest

final class PasswordAccessUITests: XCTestCase {
    @MainActor func testRegistrationCodeErrorSessionReopenAndRecovery() {
        let app = application()
        app.launch()
        openPassword(app)
        app.buttons["passwordToggleRegister"].tap()
        capture("Password registration form", app)
        fill(app.textFields["passwordUsername"], "native.user")
        fill(app.textFields["passwordEmail"], "qa@example.invalid")
        fill(app.secureTextFields["passwordValue"], "native fixture password 123")
        fill(app.secureTextFields["passwordRepeat"], "native fixture password 123")
        capture("Password registration ready to send code", app)
        app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.textFields["passwordCode"].waitForExistence(timeout: 5))
        capture("Password verification form", app)
        fill(app.textFields["passwordCode"], "00000000")
        app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.staticTexts["passwordError"].waitForExistence(timeout: 5))
        fill(app.textFields["passwordCode"], "12345678")
        capture("Password verification retry", app)
        app.buttons["passwordSubmit"].tap()
        assertSignedIn(app)
        app.terminate(); app.launch()
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 5))
        app.buttons["Sign out"].tap()
        openPassword(app)
        app.buttons["passwordRecover"].tap()
        capture("Password recovery request", app)
        fill(app.textFields["passwordIdentifier"], "native.user")
        app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.textFields["passwordCode"].waitForExistence(timeout: 5))
        fill(app.textFields["passwordCode"], "12345678")
        fill(app.secureTextFields["passwordValue"], "replacement fixture password 456")
        fill(app.secureTextFields["passwordRepeat"], "replacement fixture password 456")
        capture("Password recovery new credentials", app)
        app.buttons["passwordSubmit"].tap()
        assertSignedIn(app)
        capture("Recovered password opens the same account", app)
    }
    @MainActor func testExistingAccountAddsCredentialsWithoutLeavingConnections() {
        let app = application(); app.launchArguments += ["--password-account-fixture"]
        app.launch(); app.buttons["accountSettings"].tap()
        app.buttons["managePassword"].tap()
        capture("Existing account add credentials form", app)
        fill(app.textFields["passwordUsername"], "provider.user")
        fill(app.textFields["passwordEmail"], "qa@example.invalid")
        fill(app.secureTextFields["passwordValue"], "provider fixture password 123")
        fill(app.secureTextFields["passwordRepeat"], "provider fixture password 123")
        capture("Existing account credentials ready to verify", app)
        XCTAssertTrue(app.buttons["passwordSubmit"].isEnabled)
        app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.textFields["passwordCode"].waitForExistence(timeout: 5))
        fill(app.textFields["passwordCode"], "12345678"); app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.staticTexts["Credentials saved. You can use them on your other device too."].waitForExistence(timeout: 5))
        capture("Existing account credentials confirmed", app)
        app.buttons["passwordDone"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["passwordDone"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 5))
        app.buttons["managePassword"].tap()
        let username = app.staticTexts["passwordAccountUsername"]
        if !username.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(username.label.contains("provider.user"))
        capture("Existing account username after reopening", app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["editProfile"].exists)
    }
    @MainActor func testLoginFailureAndCancelledRegistrationKeepLocalMode() {
        let app = application()
        app.launch(); openPassword(app)
        fill(app.textFields["passwordIdentifier"], "missing.user")
        fill(app.secureTextFields["passwordValue"], "wrong fixture password")
        app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.staticTexts["passwordError"].waitForExistence(timeout: 5))
        capture("Password login failure", app)
        app.buttons["passwordToggleRegister"].tap()
        fill(app.textFields["passwordUsername"], "cancelled.user")
        app.buttons["passwordCancel"].tap()
        app.navigationBars["Connections"].buttons["Done"].tap()
        app.buttons["accountSettings"].tap()
        XCTAssertFalse(app.buttons["editProfile"].exists)
        capture("Cancelled registration retains local account", app)
    }
    @MainActor func testItalianOnboardingPasswordRegistrationAndCancellation() {
        let app = application()
        app.launchArguments = ["--ui-testing", "--password-fixture", "--onboarding", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        app.buttons["onboardingContinue"].tap()
        app.buttons["onboardingAccountChoice"].tap()
        app.buttons["onboardingAccount"].tap()
        XCTAssertTrue(app.buttons["showPasswordAccess"].waitForExistence(timeout: 5))
        capture("Italian onboarding provider access", app)
        app.buttons["showPasswordAccess"].tap()
        XCTAssertTrue(app.textFields["passwordIdentifier"].waitForExistence(timeout: 5))
        capture("Italian password login sheet", app)
        app.buttons["passwordCancel"].tap()
        XCTAssertTrue(app.buttons["showPasswordAccess"].isHittable)
        app.buttons["showPasswordAccess"].tap()
        app.buttons["passwordToggleRegister"].tap()
        fill(app.textFields["passwordUsername"], "onboarding.user")
        fill(app.textFields["passwordEmail"], "qa@example.invalid")
        fill(app.secureTextFields["passwordValue"], "native fixture password 123")
        fill(app.secureTextFields["passwordRepeat"], "native fixture password 123")
        capture("Italian password registration sheet", app)
        app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.textFields["passwordCode"].waitForExistence(timeout: 5))
        capture("Italian password verification sheet", app)
        fill(app.textFields["passwordCode"], "12345678")
        app.buttons["passwordSubmit"].tap()
        XCTAssertTrue(app.buttons["onboardingFinish"].waitForExistence(timeout: 10))
        capture("Onboarding guide retained after password login", app)
        app.buttons["onboardingFinish"].tap()
        XCTAssertTrue(app.buttons["accountSettings"].waitForExistence(timeout: 5))
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 5))
    }
    @MainActor private func assertSignedIn(_ app: XCUIApplication) {
        let account = app.buttons["accountSettings"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: account)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        account.tap()
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 5))
    }
    @MainActor private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--password-fixture", "-AppleLanguages", "(en)"]
        app.launchEnvironment["MAKEET_PASSWORD_FIXTURE_ID"] = UUID().uuidString
        return app
    }
    @MainActor private func openPassword(_ app: XCUIApplication, openAccount: Bool = true) {
        if openAccount { app.buttons["accountSettings"].tap() }
        XCTAssertTrue(app.buttons["showPasswordAccess"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["showPasswordAccess"].frame.width, app.buttons["appleSignIn"].frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(app.buttons["showPasswordAccess"].frame.height + 0.001, 54)
        capture("Password access alongside Apple and Google", app)
        app.buttons["showPasswordAccess"].tap()
        XCTAssertTrue(app.textFields["passwordIdentifier"].waitForExistence(timeout: 5))
        capture("Password login form", app)
    }
    @MainActor private func fill(_ field: XCUIElement, _ value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        if field.elementType == .secureTextField {
            let app = XCUIApplication()
            let firstNewPassword = field.identifier == "passwordValue" && app.secureTextFields["passwordRepeat"].exists
            let suggestion = app.buttons["GenerateStrongPasswordButton"]
            if suggestion.waitForExistence(timeout: firstNewPassword ? 10 : 1) {
                let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "iOS Password AutoFill choice"; proof.lifetime = .keepAlways; add(proof)
                app.buttons["xmark"].tap()
                let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: suggestion)
                XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            }
        }
        let previous = field.value as? String ?? ""
        if previous != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count)) }
        field.typeText(value)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            let done = app.toolbars.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Fine"])).firstMatch
            if done.isHittable { done.tap() }
        }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
