import Foundation

public struct AccountProfile: Codable, Equatable, Sendable {
    public var name: String
    public var image: Data?
    public var revision: Int64
    public init(name: String = "", image: Data? = nil, revision: Int64 = 0) {
        self.name = name; self.image = image; self.revision = revision
    }
    public var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
