import Foundation
#if SWIFT_PACKAGE
import MakeetCore
#endif

public protocol SessionStorage: Sendable {
    func load() throws -> StoredSession?
    func save(_ session: StoredSession) throws
    func clear() throws
}

public struct StoredSession: Codable, Sendable {
    public let tokens: AccountTokens
    public let expiresAt: Date
    public init(tokens: AccountTokens, now: Date = Date()) {
        self.tokens = tokens; expiresAt = now.addingTimeInterval(TimeInterval(tokens.expiresIn))
    }
}

public enum AccountAPIError: Error, Sendable {
    case response(Int, String)
    case invalidResponse
    case signedOut
    case conflict([SyncRecord])
}

public actor AccountAPI {
    private let baseURL: URL
    private let http: URLSession
    private let storage: any SessionStorage
    private var session: StoredSession?
    private var refreshing: Task<StoredSession, Error>?
    private var generation = UUID()

    public init(baseURL: URL = URL(string: "https://api.makeet.app")!, storage: any SessionStorage,
                http: URLSession? = nil) throws {
        self.baseURL = baseURL; self.storage = storage
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        self.http = http ?? URLSession(configuration: configuration, delegate: AccountRedirectGuard(), delegateQueue: nil)
        session = try storage.load()
    }
    public func currentUser() -> AccountUser? { session?.tokens.user }
    public func providers() async throws -> [String] {
        struct Config: Decodable { let providers: [String] }
        let data = try await send("GET", "/v1/config")
        return try AccountCoding.decoder().decode(Config.self, from: data).providers
    }
    public func billingEnabled() async throws -> Bool {
        struct Config: Decodable { let billing_enabled: Bool? }
        return try AccountCoding.decoder().decode(Config.self, from: await send("GET", "/v1/config")).billing_enabled ?? false
    }
    public func challenge(_ provider: String) async throws -> AccountChallenge {
        let data = try await send("POST", "/v1/auth/challenges", body: AccountCoding.encoder().encode(["provider": provider]))
        return try AccountCoding.decoder().decode(AccountChallenge.self, from: data)
    }
    public func exchange(provider: String, challenge: AccountChallenge, token: String, code: String = "") async throws -> AccountUser {
        let epoch = generation
        let body = try AccountCoding.encoder().encode(["provider": provider, "challenge_id": challenge.id, "id_token": token, "authorization_code": code])
        let data = try await send("POST", "/v1/auth/exchange", body: body)
        let next = StoredSession(tokens: try AccountCoding.decoder().decode(AccountTokens.self, from: data))
        guard epoch == generation else { throw AccountAPIError.signedOut }
        try storage.save(next); generation = UUID(); session = next
        refreshing?.cancel(); refreshing = nil
        return next.tokens.user
    }
    public func synchronize(_ request: SyncRequest, userID: UUID) async throws -> SyncResponse {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        let data = try await authenticated("POST", "/v1/sync", body: AccountCoding.encoder().encode(request))
        return try AccountCoding.decoder().decode(SyncResponse.self, from: data)
    }
    public func profile(userID: UUID) async throws -> AccountProfile {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        let data = try await authenticated("GET", "/v1/me/profile")
        return try AccountCoding.decoder().decode(AccountProfile.self, from: data)
    }
    public func updateProfile(_ profile: AccountProfile, userID: UUID) async throws -> AccountProfile {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        let data = try await authenticated("PUT", "/v1/me/profile", body: AccountCoding.encoder().encode(profile))
        return try AccountCoding.decoder().decode(AccountProfile.self, from: data)
    }
    public func entitlement(userID: UUID) async throws -> AccountEntitlement {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        return try AccountCoding.decoder().decode(AccountEntitlement.self, from: await authenticated("GET", "/v1/me/entitlement"))
    }
    public func submitTransaction(_ signed: String, userID: UUID) async throws -> AccountEntitlement {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        let data = try await authenticated("POST", "/v1/me/transactions", body: AccountCoding.encoder().encode(["signed_transaction": signed]))
        return try AccountCoding.decoder().decode(AccountEntitlement.self, from: data)
    }
    public func export(userID: UUID) async throws -> Data {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        return try await authenticated("GET", "/v1/me/export")
    }
    public func logout() async throws -> Bool {
        var revoked = false
        do { _ = try await authenticated("POST", "/v1/auth/logout"); revoked = true } catch {}
        try clearLocal()
        return revoked
    }
    public func registerPush(id: UUID, userID: UUID, registration: PushRegistration) async throws -> PushRegistrationStatus {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        let data = try await authenticated("PUT", "/v1/devices/" + id.uuidString, body: AccountCoding.encoder().encode(registration))
        return try AccountCoding.decoder().decode(PushRegistrationStatus.self, from: data)
    }
    public func removePush(id: UUID, userID: UUID, secret: String) async throws {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        _ = try await authenticated("DELETE", "/v1/devices/" + id.uuidString,
                                    body: AccountCoding.encoder().encode(["installation_secret": secret]))
    }
    public func testPush(id: UUID, userID: UUID, secret: String, messageID: UUID) async throws -> PushTestStatus {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        let data = try await authenticated("POST", "/v1/devices/" + id.uuidString + "/test",
            body: AccountCoding.encoder().encode(["installation_secret": secret, "message_id": messageID.uuidString]))
        return try AccountCoding.decoder().decode(PushTestStatus.self, from: data)
    }
    public func confirmPush(id: UUID, userID: UUID, secret: String, messageID: UUID) async throws {
        guard session?.tokens.user.id == userID else { throw AccountAPIError.signedOut }
        _ = try await authenticated("POST", "/v1/devices/" + id.uuidString + "/receipts",
            body: AccountCoding.encoder().encode(["installation_secret": secret, "message_id": messageID.uuidString]))
    }
    public func deleteAccount() async throws {
        _ = try await authenticated("DELETE", "/v1/me", body: AccountCoding.encoder().encode(["confirmation": "DELETE"]))
    }
    public func clearLocal() throws {
        try storage.clear(); generation = UUID(); session = nil
        refreshing?.cancel(); refreshing = nil
    }
    private func access() async throws -> String {
        guard let session else { throw AccountAPIError.signedOut }
        if session.expiresAt.timeIntervalSinceNow > 30 { return session.tokens.accessToken }
        return try await refresh().tokens.accessToken
    }
    private func refresh() async throws -> StoredSession {
        if let refreshing { return try await refreshing.value }
        guard let previous = session else { throw AccountAPIError.signedOut }
        let epoch = generation
        let task = Task {
            do {
                let body = try AccountCoding.encoder().encode(["refresh_token": previous.tokens.refreshToken])
                let data = try await self.send("POST", "/v1/auth/refresh", body: body)
                let next = StoredSession(tokens: try AccountCoding.decoder().decode(AccountTokens.self, from: data))
                guard epoch == self.generation else { throw AccountAPIError.signedOut }
                guard next.tokens.user.id == previous.tokens.user.id else { throw AccountAPIError.invalidResponse }
                try self.storage.save(next)
                self.session = next; self.refreshing = nil
                return next
            } catch {
                if epoch == self.generation {
                    self.refreshing = nil
                    if case AccountAPIError.response(401, _) = error { try self.clearLocal() }
                }
                throw error
            }
        }
        refreshing = task
        return try await task.value
    }
    private func authenticated(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        let epoch = generation
        let token = try await access()
        guard epoch == generation else { throw AccountAPIError.signedOut }
        do {
            let data = try await send(method, path, body: body, token: token)
            guard epoch == generation else { throw AccountAPIError.signedOut }
            return data
        } catch AccountAPIError.response(401, _) {
            let next: StoredSession
            if let session, session.tokens.accessToken != token { next = session }
            else { next = try await refresh() }
            guard epoch == generation else { throw AccountAPIError.signedOut }
            let data = try await send(method, path, body: body, token: next.tokens.accessToken)
            guard epoch == generation else { throw AccountAPIError.signedOut }
            return data
        }
    }
    private func send(_ method: String, _ path: String, body: Data? = nil, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { let error: String; let conflicts: [SyncRecord]? }
            let failure = try? AccountCoding.decoder().decode(Failure.self, from: data)
            if response.statusCode == 409, let conflicts = failure?.conflicts { throw AccountAPIError.conflict(conflicts) }
            throw AccountAPIError.response(response.statusCode, failure?.error ?? "request_failed")
        }
        return data
    }
}

private final class AccountRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
