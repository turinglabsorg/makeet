#if DEBUG && targetEnvironment(simulator)
import Foundation

@MainActor struct PasswordUITestFixture {
    let api: AccountAPI
    let storage: PasswordFixtureSession
    init() throws {
        let id = UUID(uuidString: ProcessInfo.processInfo.environment["MAKEET_PASSWORD_FIXTURE_ID"] ?? "") ?? UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("password-ui-" + id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = PasswordFixtureSession(file: directory.appendingPathComponent("session.json"))
        if ProcessInfo.processInfo.arguments.contains("--password-account-fixture"), try storage.load() == nil {
            try storage.save(StoredSession(tokens: AccountTokens(accessToken: "password-ui-access", refreshToken: "password-ui-refresh", expiresIn: 3600, user: AccountUser(id: id, email: "provider@example.invalid"))))
        }
        PasswordFixtureProtocol.configure(directory: directory, userID: id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PasswordFixtureProtocol.self]
        api = try AccountAPI(baseURL: URL(string: "https://password-fixture.makeet.invalid")!, storage: storage, http: URLSession(configuration: configuration))
    }
}
struct PasswordFixtureSession: SessionStorage {
    let file: URL
    func load() throws -> StoredSession? { FileManager.default.fileExists(atPath: file.path) ? try AccountCoding.decoder().decode(StoredSession.self, from: Data(contentsOf: file)) : nil }
    func save(_ session: StoredSession) throws { try AccountCoding.encoder().encode(session).write(to: file, options: .atomic) }
    func clear() throws { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
}
private final class PasswordFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var directory: URL!
    private static var userID = UUID()
    static func configure(directory: URL, userID: UUID) { lock.lock(); defer { lock.unlock() }; self.directory = directory; self.userID = userID }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "password-fixture.makeet.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        do {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:]
            let server = Self.directory.appendingPathComponent("credentials.json")
            var credentials = (try? JSONSerialization.jsonObject(with: Data(contentsOf: server))) as? [String: String] ?? [:]
            var status = 200
            var result: [String: Any] = [:]
            switch request.url!.path {
            case "/v1/auth/password/register", "/v1/me/password" where request.httpMethod == "POST":
                let pending = Self.directory.appendingPathComponent("pending.json")
                try JSONSerialization.data(withJSONObject: body).write(to: pending, options: .atomic)
                result = ["request_id": "password-ui-request"]; status = 202
            case "/v1/auth/password/recover": result = ["request_id": "password-ui-recovery"]; status = 202
            case "/v1/auth/password/confirm", "/v1/me/password/confirm":
                if body["code"] != "12345678" { status = 400; result = ["error":"invalid_verification"] }
                else {
                    if body["request_id"] == "password-ui-recovery" { credentials["password"] = body["password"] }
                    else { credentials = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.directory.appendingPathComponent("pending.json"))) as? [String: String] ?? [:] }
                    try JSONSerialization.data(withJSONObject: credentials).write(to: server, options: .atomic)
                    result = ["confirmed":true]
                }
            case "/v1/auth/password/login":
                if body["identifier"] == credentials["username"], body["password"] == credentials["password"], !credentials.isEmpty {
                    result = ["access_token":"password-ui-access", "refresh_token":"password-ui-refresh", "expires_in":3600, "user":["id":Self.userID.uuidString,"email":credentials["email"] ?? "qa@example.invalid"]]
                } else { status = 401; result = ["error":"invalid_credentials"] }
            case "/v1/me/password": result = ["enabled": !credentials.isEmpty, "username":credentials["username"] ?? "", "email":credentials["email"] ?? ""]
            case "/v1/auth/logout": status = 204
            default: throw URLError(.unsupportedURL)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: result))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
