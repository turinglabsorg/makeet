import Foundation

public struct AccountUser: Codable, Equatable, Sendable {
    public let id: UUID
    public let email: String
}

public struct AccountTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let user: AccountUser
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", user
    }
}

public struct AccountChallenge: Codable, Sendable {
    public let id: String
    public let nonce: String
    public let expiresAt: Int64
    enum CodingKeys: String, CodingKey { case id, nonce, expiresAt = "expires_at" }
}

public struct HabitRecord: Codable, Equatable, Sendable {
    public var name: String
    public var symbol: String
    public var colorIndex: Int
    public var target: Double
    public var step: Double
    public var unit: String
    public var createdAt: Date
    public var timeZoneID: String
    public var preferredHour: Int
    public var durationMinutes: Int
    public var archived: Bool
    public init(name: String, symbol: String, colorIndex: Int, target: Double, step: Double, unit: String,
                createdAt: Date, timeZoneID: String, preferredHour: Int, durationMinutes: Int, archived: Bool) {
        self.name = name; self.symbol = symbol; self.colorIndex = colorIndex; self.target = target
        self.step = step; self.unit = unit; self.createdAt = createdAt; self.timeZoneID = timeZoneID
        self.preferredHour = preferredHour; self.durationMinutes = durationMinutes; self.archived = archived
    }
    enum CodingKeys: String, CodingKey {
        case name, symbol, target, step, unit, archived
        case colorIndex = "color_index", createdAt = "created_at", timeZoneID = "time_zone_id"
        case preferredHour = "preferred_hour", durationMinutes = "duration_minutes"
    }
}

public struct ActivityRecord: Codable, Equatable, Sendable {
    public var habitID: UUID
    public var amount: Double
    public var timestamp: Date
    public var source: String
    public init(habitID: UUID, amount: Double, timestamp: Date, source: String) {
        self.habitID = habitID; self.amount = amount; self.timestamp = timestamp; self.source = source
    }
    enum CodingKeys: String, CodingKey { case habitID = "habit_id", amount, timestamp, source }
}

public struct SyncRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case habit, activity }
    public var kind: Kind
    public var id: UUID
    public var revision: Int64
    public var deleted: Bool
    public var habit: HabitRecord?
    public var activity: ActivityRecord?
    public var key: String { kind.rawValue + ":" + id.uuidString.lowercased() }
    public init(id: UUID, revision: Int64 = 0, habit: HabitRecord) {
        kind = .habit; self.id = id; self.revision = revision; deleted = false; self.habit = habit
    }
    public init(id: UUID, revision: Int64 = 0, activity: ActivityRecord) {
        kind = .activity; self.id = id; self.revision = revision; deleted = false; self.activity = activity
    }
    public func tombstone() -> SyncRecord {
        var copy = self; copy.deleted = true; copy.habit = nil; copy.activity = nil; return copy
    }
    public func sameContent(as other: SyncRecord) -> Bool {
        kind == other.kind && id == other.id && deleted == other.deleted && habit == other.habit && activity == other.activity
    }
    enum CodingKeys: String, CodingKey { case kind, id, revision, deleted, data }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind); id = try c.decode(UUID.self, forKey: .id)
        revision = try c.decode(Int64.self, forKey: .revision); deleted = try c.decode(Bool.self, forKey: .deleted)
        if !deleted {
            if kind == .habit { habit = try c.decode(HabitRecord.self, forKey: .data) }
            else { activity = try c.decode(ActivityRecord.self, forKey: .data) }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind); try c.encode(id.uuidString.lowercased(), forKey: .id)
        try c.encode(revision, forKey: .revision); try c.encode(deleted, forKey: .deleted)
        if deleted { try c.encode([String: String](), forKey: .data) }
        else if kind == .habit { try c.encode(habit, forKey: .data) }
        else { try c.encode(activity, forKey: .data) }
    }
}

public struct SyncRequest: Codable, Equatable, Sendable {
    public var cursor: Int64
    public var mutationID: String
    public var changes: [SyncRecord]
    public init(cursor: Int64, mutationID: String = "", changes: [SyncRecord] = []) {
        self.cursor = cursor; self.mutationID = mutationID; self.changes = changes
    }
    enum CodingKeys: String, CodingKey { case cursor, mutationID = "mutation_id", changes }
}

public struct SyncResponse: Codable, Sendable {
    public var cursor: Int64
    public var hasMore: Bool
    public var changes: [SyncRecord]
    public var applied: [SyncRecord]
    public init(cursor: Int64, hasMore: Bool = false, changes: [SyncRecord], applied: [SyncRecord] = []) {
        self.cursor = cursor; self.hasMore = hasMore; self.changes = changes; self.applied = applied
    }
    enum CodingKeys: String, CodingKey { case cursor, hasMore = "has_more", changes, applied }
}

public enum AccountCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: true).timeSeparator(.colon).timeZone(separator: .colon)))
        }
        return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer(); let raw = try c.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid server date")
            }
            return date
        }
        return decoder
    }
}
