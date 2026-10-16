import XCTest
import UserNotifications
@testable import Makeet

@MainActor final class NotificationServiceTests: XCTestCase {
    func testRefreshDoesNotPromptWithoutUserAction() async {
        let client = NotificationClientFixture()
        var registrations = 0
        let service = NotificationService(client: client, register: { registrations += 1 })
        await service.refresh()
        XCTAssertEqual(client.requests, 0)
        XCTAssertEqual(registrations, 0)
        XCTAssertFalse(service.authorized)
        XCTAssertEqual(service.permissionLabel, "Da attivare")
    }

    func testConsentRegistersAndTokenRefreshReplacesPreviousToken() async {
        let client = NotificationClientFixture()
        var registrations = 0
        let service = NotificationService(client: client, register: { registrations += 1 })
        await service.enable()
        XCTAssertEqual(client.requests, 1)
        XCTAssertEqual(registrations, 1)
        XCTAssertTrue(service.authorized)
        XCTAssertTrue(service.isRegistering)
        await service.refresh()
        XCTAssertEqual(registrations, 1)
        service.registered(token: Data([1, 2, 3]))
        service.registered(token: Data([4, 5, 6]))
        XCTAssertEqual(service.deviceToken, Data([4, 5, 6]))
        XCTAssertFalse(service.isRegistering)
        XCTAssertTrue(service.deliveryLabel.contains("server da collegare"))
    }

    func testDeniedPermissionNeverRegistersAndRevocationClearsToken() async {
        let client = NotificationClientFixture()
        client.status = .denied
        var registrations = 0
        let service = NotificationService(client: client, register: { registrations += 1 })
        await service.enable()
        XCTAssertEqual(client.requests, 0)
        XCTAssertEqual(registrations, 0)
        service.registered(token: Data([1]))
        XCTAssertNil(service.deviceToken)
        await service.refresh()
        XCTAssertNil(service.deviceToken)
        XCTAssertEqual(service.permissionLabel, "Non consentite")
    }

    func testRegistrationFailureNeedsExplicitRetry() async {
        let client = NotificationClientFixture()
        client.status = .authorized
        var registrations = 0
        let service = NotificationService(client: client, register: { registrations += 1 })
        await service.refresh()
        service.registrationDidFail()
        XCTAssertTrue(service.registrationFailed)
        XCTAssertNil(service.deviceToken)
        await service.refresh()
        XCTAssertEqual(registrations, 1)
        await service.enable()
        XCTAssertEqual(registrations, 2)
        XCTAssertFalse(service.registrationFailed)
    }

    func testPermissionErrorIsVisibleAndCanBeRetried() async {
        let client = NotificationClientFixture()
        client.shouldFail = true
        var registrations = 0
        let service = NotificationService(client: client, register: { registrations += 1 })
        await service.enable()
        XCTAssertTrue(service.permissionFailed)
        XCTAssertFalse(service.isRequesting)
        XCTAssertEqual(registrations, 0)
        client.shouldFail = false
        await service.enable()
        XCTAssertFalse(service.permissionFailed)
        XCTAssertEqual(registrations, 1)
    }
}

@MainActor private final class NotificationClientFixture: NotificationAuthorizationClient {
    var status: UNAuthorizationStatus = .notDetermined
    var requests = 0
    var shouldFail = false

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        requests += 1
        if shouldFail { throw NSError(domain: "NotificationTest", code: 1) }
        status = .authorized
        return true
    }
}
