import Foundation

public struct PushRegistration: Encodable, Sendable {
    public let installationSecret: String
    public let token: String
    public let topic: String
    public let environment: String
    public let language: String
    public let timeZone: String
    public let remindersEnabled: Bool
    public let reminderHour: Int
    public let reminderMinute: Int
    enum CodingKeys: String, CodingKey {
        case installationSecret = "installation_secret", token, topic, environment, language
        case timeZone = "time_zone", remindersEnabled = "reminders_enabled"
        case reminderHour = "reminder_hour", reminderMinute = "reminder_minute"
    }
    public init(installationSecret: String, token: String, topic: String, environment: String,
                language: String, timeZone: String, remindersEnabled: Bool, reminderHour: Int, reminderMinute: Int) {
        self.installationSecret = installationSecret; self.token = token; self.topic = topic
        self.environment = environment; self.language = language; self.timeZone = timeZone
        self.remindersEnabled = remindersEnabled; self.reminderHour = reminderHour; self.reminderMinute = reminderMinute
    }
}
public struct PushRegistrationStatus: Decodable, Sendable {
    public let registered: Bool
    public let acceptedAt: Int64
    public let confirmedAt: Int64
    enum CodingKeys: String, CodingKey { case registered, acceptedAt = "accepted_at", confirmedAt = "confirmed_at" }
}
public struct PushTestStatus: Decodable, Sendable {
    public let messageID: UUID
    public let status: String
    public let confirmedAt: Int64
    enum CodingKeys: String, CodingKey { case messageID = "message_id", status, confirmedAt = "confirmed_at" }
}
