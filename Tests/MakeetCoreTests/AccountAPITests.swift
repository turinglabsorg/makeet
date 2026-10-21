import XCTest
import MakeetCore
import MakeetAccounts

private final class TestSessionStorage: SessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredSession?
    var rejectSaves = false
    init(_ value: StoredSession?) { self.value = value }
    func load() -> StoredSession? { lock.withLock { value } }
    func save(_ session: StoredSession) throws {
        try lock.withLock {
            if rejectSaves { throw CocoaError(.fileWriteNoPermission) }
            value = session
        }
    }
    func clear() { lock.withLock { value = nil } }
}

final class AccountAPITests: XCTestCase, @unchecked Sendable {
    private let accountID = UUID(uuidString: "d604b64a-f819-4822-840a-8c472d388632")!
    private func tokens(_ access: String = "fixture-old", _ refresh: String = "fixture-refresh", expires: Int = 900) throws -> AccountTokens {
        let raw = "{\"access_token\":\"\(access)\",\"refresh_token\":\"\(refresh)\",\"expires_in\":\(expires),\"user\":{\"id\":\"d604b64a-f819-4822-840a-8c472d388632\",\"email\":\"test@example.invalid\"}}"
        return try AccountCoding.decoder().decode(AccountTokens.self, from: Data(raw.utf8))
    }
    private func server() throws -> (Process, URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/account_http.py")
        process.arguments = [file.path]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let port = String(data: output.fileHandleForReading.availableData, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(port) else { process.terminate(); throw CocoaError(.coderReadCorrupt) }
        addTeardownBlock { process.terminate(); process.waitUntilExit() }
        return (process, URL(string: "http://127.0.0.1:\(number)")!)
    }
    func testPasswordLoginPersistsSessionAndEnrollmentStaysBoundToAccount() async throws {
        let (_, url) = try server()
        let storage = TestSessionStorage(nil)
        let api = try AccountAPI(baseURL: url, storage: storage)
        let available = try await api.passwordEnabled(); XCTAssertTrue(available)
        let user = try await api.passwordLogin(identifier: "qa.user", password: "fixture password for testing")
        XCTAssertEqual(user.id, accountID); XCTAssertNotNil(storage.load())
        let status = try await api.passwordStatus(userID: accountID); XCTAssertEqual(status.username, "qa.user")
        do {
            _ = try await api.requestPassword(username: "qa.user", email: "qa@example.invalid", password: "fixture password for testing", language: "en", userID: UUID())
            XCTFail("Cross-account credential enrollment accepted")
        } catch AccountAPIError.signedOut {}
        do {
            try await api.confirmPassword(requestID: "fixture-request", code: "00000000", userID: accountID)
            XCTFail("Invalid code accepted")
        } catch AccountAPIError.response(400, _) {}
        let retained = await api.currentUser(); XCTAssertEqual(retained?.id, accountID)
    }
    func testConcurrentRequestsRotateOncePersistThenUseReplacementOverHTTP() async throws {
        let (_, url) = try server()
        let storage = TestSessionStorage(StoredSession(tokens: try tokens(), now: .distantPast))
        let api = try AccountAPI(baseURL: url, storage: storage)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { _ = try await api.synchronize(SyncRequest(cursor: 0), userID: self.accountID) }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(storage.load()?.tokens.accessToken, "fixture-next")
        let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("counts"))
        let counts = try JSONDecoder().decode([String: Int].self, from: data)
        XCTAssertEqual(counts["refresh"], 1); XCTAssertEqual(counts["sync"], 12)
        let challenge = try await api.challenge("apple")
        XCTAssertEqual(challenge.expiresAt, 1_900_000_000)
    }
    func testFailedKeychainRotationDoesNotSendProtectedRequest() async throws {
        let (_, url) = try server()
        let storage = TestSessionStorage(StoredSession(tokens: try tokens(), now: .distantPast))
        storage.rejectSaves = true
        let api = try AccountAPI(baseURL: url, storage: storage)
        do { _ = try await api.synchronize(SyncRequest(cursor: 0), userID: accountID); XCTFail("Persistence failure ignored") } catch {}
        let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("counts"))
        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: data)["sync"], 0)
    }
    func testSignOutDuringRefreshCannotRestoreSession() async throws {
        let (_, url) = try server()
        let storage = TestSessionStorage(StoredSession(tokens: try tokens(), now: .distantPast))
        let api = try AccountAPI(baseURL: url, storage: storage)
        let request = Task { try await api.synchronize(SyncRequest(cursor: 0), userID: accountID) }
        for _ in 0..<100 {
            let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("counts"))
            if try JSONDecoder().decode([String: Int].self, from: data)["refresh"] == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await api.clearLocal()
        do { _ = try await request.value; XCTFail("Old session survived sign-out") } catch {}
        XCTAssertNil(storage.load())
        let user = await api.currentUser(); XCTAssertNil(user)
    }
    func testOldAccountCannotSendMutationsUsingNewSession() async throws {
        let (_, url) = try server()
        let storage = TestSessionStorage(StoredSession(tokens: try tokens()))
        let api = try AccountAPI(baseURL: url, storage: storage)
        do {
            _ = try await api.synchronize(SyncRequest(cursor: 0), userID: UUID())
            XCTFail("Cross-account mutation accepted")
        } catch AccountAPIError.signedOut {}
        let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("counts"))
        let counts = try JSONDecoder().decode([String: Int].self, from: data)
        XCTAssertEqual(counts["sync"], 0); XCTAssertEqual(counts["refresh"], 0)
    }
    func testProviderDeletionFailureRetainsSessionAndRetryConfirmsServerDeletion() async throws {
        let (_, url) = try server()
        let storage = TestSessionStorage(StoredSession(tokens: try tokens("fixture-next")))
        let api = try AccountAPI(baseURL: url, storage: storage)
        do { try await api.deleteAccount(); XCTFail("Provider failure reported as deleted") }
        catch AccountAPIError.response(503, let reason) { XCTAssertEqual(reason, "provider_revocation_unavailable") }
        XCTAssertNotNil(storage.load())
        try await api.deleteAccount()
        // The caller records local cleanup before removing the Keychain session.
        try await api.clearLocal()
        XCTAssertNil(storage.load())
    }
    func testPushWireRegistrationReceiptAndAccountGuardOverHTTP() async throws {
        let (_, url) = try server()
        let api = try AccountAPI(baseURL: url, storage: TestSessionStorage(StoredSession(tokens: try tokens("fixture-next"))))
        let id = UUID()
        let registration = PushRegistration(installationSecret: "fixture-installation", token: "abcdef",
            topic: "org.turinglabs.makeet", environment: "development", language: "it", timeZone: "Europe/Rome",
            remindersEnabled: true, reminderHour: 19, reminderMinute: 30)
        do {
            _ = try await api.registerPush(id: id, userID: UUID(), registration: registration)
            XCTFail("Old account registered a device")
        } catch AccountAPIError.signedOut {}
        let status = try await api.registerPush(id: id, userID: accountID, registration: registration)
        XCTAssertTrue(status.registered); XCTAssertEqual(status.acceptedAt, 123); XCTAssertEqual(status.confirmedAt, 0)
        let messageID = UUID()
        let test = try await api.testPush(id: id, userID: accountID, secret: "fixture-installation", messageID: messageID)
        XCTAssertEqual(test.messageID, messageID); XCTAssertEqual(test.status, "accepted"); XCTAssertEqual(test.confirmedAt, 0)
        try await api.confirmPush(id: id, userID: accountID, secret: "fixture-installation", messageID: messageID)
        try await api.removePush(id: id, userID: accountID, secret: "fixture-installation")
        let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("counts"))
        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: data)["push"], 1)
    }
    func testProfileWirePhotoAndRevisionStayBoundToCurrentAccount() async throws {
        let (_, url) = try server()
        let api = try AccountAPI(baseURL: url, storage: TestSessionStorage(StoredSession(tokens: try tokens("fixture-next"))))
        let draft = AccountProfile(name: "Alex Morgan", image: Data([1, 2, 3]))
        do { _ = try await api.updateProfile(draft, userID: UUID()); XCTFail("Wrong account changed profile") }
        catch AccountAPIError.signedOut {}
        let saved = try await api.updateProfile(draft, userID: accountID)
        XCTAssertEqual(saved.revision, 1); XCTAssertEqual(saved.image, draft.image)
        XCTAssertEqual(saved.initials, "AM")
        let loaded = try await api.profile(userID: accountID)
        XCTAssertEqual(loaded, saved)
        do { _ = try await api.updateProfile(draft, userID: accountID); XCTFail("Stale revision accepted") }
        catch AccountAPIError.response(409, let error) { XCTAssertEqual(error, "profile_conflict") }
        let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("counts"))
        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: data)["profile"], 1)
    }
    func testSubscriptionAndExportWireDataStayBoundToCurrentAccount() async throws {
        let (_, url) = try server()
        let api = try AccountAPI(baseURL: url, storage: TestSessionStorage(StoredSession(tokens: try tokens("fixture-next"))))
        let enabled = try await api.billingEnabled(); XCTAssertTrue(enabled)
        let free = try await api.entitlement(userID: accountID); XCTAssertFalse(free.active)
        let active = try await api.submitTransaction("fixture-signed-transaction", userID: accountID)
        XCTAssertTrue(active.active); XCTAssertEqual(active.expiresAt, 1_900_000_000)
        let data = try await api.export(userID: accountID)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int, 1)
        do { _ = try await api.submitTransaction("fixture-signed-transaction", userID: UUID()); XCTFail("Wrong account submitted purchase") }
        catch AccountAPIError.signedOut {}
        do { _ = try await api.export(userID: UUID()); XCTFail("Wrong account exported data") }
        catch AccountAPIError.signedOut {}
    }

}
