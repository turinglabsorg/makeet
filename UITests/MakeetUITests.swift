import XCTest

final class MakeetUITests: XCTestCase {
    @MainActor func testOnboardingRequiresExplicitStorageChoiceAndRemembersLocalMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--onboarding", "-AppleLanguages", "(it)"]
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attach("Onboarding welcome", app)
        app.buttons["onboardingContinue"].tap()
        XCTAssertTrue(app.buttons["onboardingAccountChoice"].exists)
        XCTAssertTrue(app.buttons["onboardingLocalChoice"].exists)
        XCTAssertFalse(app.buttons["onboardingLocal"].exists)
        app.buttons["onboardingAccountChoice"].tap()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.buttons["onboardingAccount"].tap()
        XCTAssertTrue(app.staticTexts["Accedi per sincronizzare"].waitForExistence(timeout: 5))
        app.buttons["Preferisco continuare senza account"].tap()
        attach("Onboarding local choice", app)
        app.buttons["onboardingLocal"].tap()
        XCTAssertTrue(app.tabBars.buttons["Oggi"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--onboarding", "--preserve-onboarding", "-AppleLanguages", "(it)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Oggi"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardingContinue"].exists)
    }

    @MainActor func testOnboardingInAllFiveLanguages() {
        for (language, headline, choice) in [
            ("it", "Un passo, poi un altro.", "Dove teniamo i tuoi progressi?"),
            ("en", "One step, then another.", "Where should your progress live?"),
            ("fr", "Un pas, puis un autre.", "Où conserver vos progrès ?"),
            ("de", "Ein Schritt, dann der nächste.", "Wo bleiben deine Fortschritte?"),
            ("es", "Un paso, luego otro.", "¿Dónde guardamos tu progreso?")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--onboarding", "-AppleLanguages", "(\(language))"]
            app.launch()
            XCTAssertTrue(app.staticTexts[headline].waitForExistence(timeout: 5))
            attach("Welcome \(language)", app)
            app.buttons["onboardingContinue"].tap()
            XCTAssertTrue(app.staticTexts[choice].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["onboardingAccountChoice"].exists)
            XCTAssertTrue(app.buttons["onboardingLocalChoice"].isHittable)
            attach("Storage choice \(language)", app)
            app.terminate()
        }
    }

    @MainActor func testAccountStatusInFiveLanguages() {
        for (language, plan, connections, heading, local) in [
            ("it", "Il tuo piano", "Connessioni", "Account Makeet", "I progressi restano su questo dispositivo finché non accedi."),
            ("en", "Your plan", "Connections", "Makeet account", "Your progress stays on this device until you sign in."),
            ("fr", "Votre programme", "Connexions", "Compte Makeet", "Vos progrès restent sur cet appareil tant que vous ne vous connectez pas."),
            ("de", "Dein Plan", "Verbindungen", "Makeet-Konto", "Deine Fortschritte bleiben auf diesem Gerät, bis du dich anmeldest."),
            ("es", "Tu plan", "Conexiones", "Cuenta Makeet", "Tu progreso permanece en este dispositivo hasta que inicies sesión.")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "-AppleLanguages", "(\(language))"]
            app.launch()
            app.tabBars.buttons[plan].tap()
            app.buttons[connections].tap()
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5), language)
            XCTAssertTrue(app.staticTexts[local].exists, language)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            attach("Account \(language)", app)
            app.terminate()
        }
    }

    @MainActor func testLanguageCanBeSelectedInAppAndPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(it)"]
        app.launch()
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.buttons["appLanguage"].waitForExistence(timeout: 5))
        app.buttons["appLanguage"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.staticTexts["Makeet account"].waitForExistence(timeout: 5))
        attach("English selected in app", app)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--preserve-language", "-AppleLanguages", "(it)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        app.buttons["accountSettings"].tap()
        app.buttons["appLanguage"].tap()
        app.buttons["Français"].tap()
        XCTAssertTrue(app.tabBars.buttons["Aujourd’hui"].waitForExistence(timeout: 5))
        app.buttons["accountSettings"].tap()
        XCTAssertTrue(app.staticTexts["Compte Makeet"].waitForExistence(timeout: 5))
        attach("French selected in app", app)
    }

    @MainActor func testCreateLogTwiceAndUndoOneRegistration() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        app.buttons["addHabit"].tap()
        let name = app.textFields["habitName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Focus test")
        app.buttons["saveHabit"].tap()
        let increment = app.buttons["increment-Focus test"]
        let decrement = app.buttons["decrement-Focus test"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        XCTAssertFalse(decrement.isEnabled)
        XCTAssertLessThan(decrement.frame.maxX, increment.frame.minX)
        increment.tap(); increment.tap()
        XCTAssertTrue(app.staticTexts["2 / 3 volte"].waitForExistence(timeout: 5))
        decrement.tap()
        XCTAssertTrue(app.staticTexts["1 / 3 volte"].waitForExistence(timeout: 5))
        decrement.tap()
        XCTAssertTrue(app.staticTexts["0 / 3 volte"].waitForExistence(timeout: 5))
        XCTAssertFalse(decrement.isEnabled)
        increment.tap(); increment.tap()
        attach("Quantity controls", app)
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
        app.launchArguments = ["--ui-testing", "--demo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
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
        XCTAssertTrue(app.staticTexts["Account Makeet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["I progressi restano su questo dispositivo finché non accedi."].exists)
        XCTAssertFalse(app.buttons["Elimina account"].exists)
        attach("Connections", app)
    }

    @MainActor func testCreateEmojiHabitAndUseLeftMinusRightPlus() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        app.buttons["addHabit"].tap()
        let name = app.textFields["habitName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Reading")
        app.segmentedControls["appearanceKind"].buttons["Emoji"].tap()
        app.buttons["emoji-preset-📚"].tap()
        attach("Emoji picker English", app)
        app.buttons["saveHabit"].tap()
        let plus = app.buttons["increment-Reading"]
        let minus = app.buttons["decrement-Reading"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["📚"].exists)
        XCTAssertTrue(app.staticTexts["0 / 3 times"].exists)
        XCTAssertFalse(app.staticTexts["Demo data"].exists)
        plus.tap(); minus.tap()
        XCTAssertTrue(app.staticTexts["0 / 3 times"].waitForExistence(timeout: 5))
        XCTAssertFalse(minus.isEnabled)
        attach("Emoji habit English", app)
    }

    @MainActor func testAllFiveLanguagesShowLocalizedNavigationAndCreation() {
        for (language, locale, today, title, example) in [
            ("it", "it_IT", "Oggi", "Nuova abitudine", "Bere acqua"),
            ("en", "en_GB", "Today", "New habit", "Drink water"),
            ("fr", "fr_FR", "Aujourd’hui", "Nouvelle habitude", "Boire de l’eau"),
            ("de", "de_DE", "Heute", "Neue Gewohnheit", "Wasser trinken"),
            ("es", "es_ES", "Hoy", "Nuevo hábito", "Beber agua")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--demo", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            XCTAssertTrue(app.tabBars.buttons[today].waitForExistence(timeout: 5), language)
            XCTAssertTrue(app.staticTexts[example].exists, language)
            attach("Today \(language)", app)
            app.buttons["addHabit"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), language)
            app.segmentedControls["appearanceKind"].buttons["Emoji"].tap()
            attach("Appearance \(language)", app)
            app.terminate()
        }
    }

    @MainActor private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
