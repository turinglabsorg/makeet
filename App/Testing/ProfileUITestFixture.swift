#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit

@MainActor struct ProfileUITestFixture {
    let user: AccountUser
    let service: AccountProfileService

    init() throws {
        let id = UUID(uuidString: ProcessInfo.processInfo.environment["MAKEET_PROFILE_FIXTURE_ID"] ?? "") ?? UUID()
        user = AccountUser(id: id, email: "alex@example.invalid")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("profile-ui-" + id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let remote = directory.appendingPathComponent("server.json")
        let cache = directory.appendingPathComponent("profile.json")
        if !FileManager.default.fileExists(atPath: remote.path) {
            let image: Data?
            if ProcessInfo.processInfo.arguments.contains("--profile-photo-fixture") {
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
                image = try ProfileImage.normalize(renderer.pngData { context in
                    UIColor.systemGreen.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                })
            } else { image = nil }
            let initial = try AccountCoding.encoder().encode(AccountProfile(name: "Alex Morgan", image: image, revision: 1))
            try initial.write(to: remote); try initial.write(to: cache)
        }
        ProfileFixtureProtocol.configure(file: remote, failing: ProcessInfo.processInfo.arguments.contains("--profile-save-error"),
                                         conflicting: ProcessInfo.processInfo.arguments.contains("--profile-save-conflict"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileFixtureProtocol.self]
        let api = try AccountAPI(baseURL: URL(string: "https://profile-fixture.makeet.invalid")!,
                                 storage: ProfileFixtureSession(user: user), http: URLSession(configuration: configuration))
        service = try AccountProfileService(userID: user.id, api: api, cacheURL: cache)
    }
}

private struct ProfileFixtureSession: SessionStorage {
    let user: AccountUser
    func load() throws -> StoredSession? {
        StoredSession(tokens: AccountTokens(accessToken: "profile-ui-fixture", refreshToken: "unused", expiresIn: 3600, user: user))
    }
    func save(_ session: StoredSession) throws {}
    func clear() throws {}
}

private final class ProfileFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var file: URL?
    private static var failing = false
    private static var conflicting = false

    static func configure(file: URL, failing: Bool, conflicting: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.file = file; self.failing = failing; self.conflicting = conflicting
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "profile-fixture.makeet.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        do {
            guard let file = Self.file, request.url?.path == "/v1/me/profile",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer profile-ui-fixture" else { throw URLError(.unsupportedURL) }
            var profile = try AccountCoding.decoder().decode(AccountProfile.self, from: Data(contentsOf: file))
            var status = 200
            if request.httpMethod == "PUT" {
                if Self.failing { status = 503 }
                else {
                    if Self.conflicting {
                        Self.conflicting = false
                        profile = AccountProfile(name: "Other device", image: profile.image, revision: profile.revision + 1)
                        try AccountCoding.encoder().encode(profile).write(to: file, options: .atomic)
                    }
                    let stream = request.httpBodyStream
                    stream?.open(); defer { stream?.close() }
                    var body = request.httpBody ?? Data()
                    if let stream {
                        var bytes = [UInt8](repeating: 0, count: 4096)
                        while stream.hasBytesAvailable {
                            let count = stream.read(&bytes, maxLength: bytes.count)
                            if count <= 0 { break }
                            body.append(contentsOf: bytes.prefix(count))
                        }
                    }
                    let draft = try AccountCoding.decoder().decode(AccountProfile.self, from: body)
                    if draft.revision != profile.revision { status = 409 }
                    else {
                        profile = AccountProfile(name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), image: draft.image, revision: profile.revision + 1)
                        try AccountCoding.encoder().encode(profile).write(to: file, options: .atomic)
                    }
                }
            }
            let data = status == 200 ? try AccountCoding.encoder().encode(profile) : Data("{\"error\":\"fixture_failure\"}".utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
