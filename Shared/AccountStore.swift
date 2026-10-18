import Foundation
import SwiftData
import WidgetKit
import Darwin
#if SWIFT_PACKAGE
import MakeetCore
#endif

enum StoreScope: Equatable, Sendable {
    case local
    case account(UUID)
    var key: String {
        switch self {
        case .local: return "local"
        case .account(let id): return "account-" + id.uuidString.lowercased()
        }
    }
}

struct AccountStoreLocation {
    let root: URL
    init(root: URL? = nil) throws {
        if let root { self.root = root }
        else if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.group) {
            self.root = group.appendingPathComponent("Accounts", isDirectory: true)
        } else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
    }
    func directory(for id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        return url
    }
    func container(for id: UUID) throws -> ModelContainer {
        let schema = Schema([Habit.self, Activity.self])
        let url = try directory(for: id).appendingPathComponent("habits.store")
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }
    func ledgerURL(for id: UUID) throws -> URL { try directory(for: id).appendingPathComponent("sync.json") }
}

enum WidgetAccountScope {
    static func current() throws -> String? { try ScopeRegistry().read() }
    static func activate(_ scope: StoreScope?) throws {
        try ScopeRegistry().write(scope?.key ?? "signed-out")
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func withContainer<T>(expected: String? = nil, _ operation: (ModelContainer, String) throws -> T) throws -> T {
        try ScopeRegistry().withScope(expected: expected) { key in
            if key == StoreScope.local.key { return try operation(SharedStore.makeContainer(), key) }
            guard key.hasPrefix("account-"), let id = UUID(uuidString: String(key.dropFirst(8))) else {
                throw CocoaError(.userCancelled)
            }
            return try operation(AccountStoreLocation().container(for: id), key)
        }
    }
}

struct ScopeRegistry {
    private let root: URL
    init(root: URL? = nil) throws { self.root = try AccountStoreLocation(root: root).root }
    func read() throws -> String? { try locked { try readUnlocked() } }
    func write(_ value: String) throws {
        try locked { try Data(value.utf8).write(to: root.appendingPathComponent("active-scope"), options: .atomic) }
    }
    func withScope<T>(expected: String?, _ operation: (String) throws -> T) throws -> T {
        try locked {
            let current = try readUnlocked() ?? StoreScope.local.key
            guard expected == nil || current == expected else { throw CocoaError(.userCancelled) }
            return try operation(current)
        }
    }
    private func readUnlocked() throws -> String? {
        let url = root.appendingPathComponent("active-scope")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = open(root.appendingPathComponent("scope.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

extension Habit {
    var syncRecord: SyncRecord {
        SyncRecord(id: id, habit: HabitRecord(name: name, symbol: symbol, colorIndex: colorIndex, target: target, step: step,
            unit: unit, createdAt: createdAt, timeZoneID: timeZoneID, preferredHour: preferredHour,
            durationMinutes: durationMinutes, archived: archived, weekdayMask: weekdayMask))
    }
}

extension Activity {
    var syncRecord: SyncRecord {
        SyncRecord(id: id, activity: ActivityRecord(habitID: habitID, amount: amount, timestamp: timestamp, source: source))
    }
}

enum AccountRecords {
    @MainActor static func snapshot(in context: ModelContext) throws -> [SyncRecord] {
        let habits = try context.fetch(FetchDescriptor<Habit>()).filter { !$0.isDemo }
        let ids = Set(habits.map(\.id))
        let activities = try context.fetch(FetchDescriptor<Activity>()).filter { ids.contains($0.habitID) && $0.source != "demo" }
        let records = habits.map(\.syncRecord) + activities.map(\.syncRecord)
        // Use exactly the wire date precision when detecting local edits.
        return try AccountCoding.decoder().decode([SyncRecord].self, from: AccountCoding.encoder().encode(records))
    }
    @MainActor static func apply(_ records: [SyncRecord], in context: ModelContext) throws {
        let habits = try context.fetch(FetchDescriptor<Habit>())
        let activities = try context.fetch(FetchDescriptor<Activity>())
        for record in records {
            if record.kind == .habit {
                let existing = habits.first { $0.id == record.id }
                if record.deleted {
                    for entry in activities where entry.habitID == record.id { context.delete(entry) }
                    if let existing { context.delete(existing) }; continue
                }
                guard let data = record.habit else { continue }
                let habit = existing ?? Habit(name: data.name, symbol: data.symbol, colorIndex: data.colorIndex,
                    target: data.target, step: data.step, unit: data.unit)
                if existing == nil { habit.id = record.id; context.insert(habit) }
                habit.name = data.name; habit.symbol = data.symbol; habit.colorIndex = data.colorIndex
                habit.target = data.target; habit.step = data.step; habit.unit = data.unit; habit.createdAt = data.createdAt
                habit.timeZoneID = data.timeZoneID; habit.preferredHour = data.preferredHour
                habit.durationMinutes = data.durationMinutes; habit.archived = data.archived; habit.isDemo = false
                habit.weekdayMask = data.weekdayMask
            } else {
                let existing = activities.first { $0.id == record.id }
                if record.deleted { if let existing { context.delete(existing) }; continue }
                guard let data = record.activity else { continue }
                let parent = data.habitID
                guard try context.fetchCount(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == parent })) > 0 else { continue }
                let activity = existing ?? Activity(habitID: data.habitID, amount: data.amount)
                if existing == nil { activity.id = record.id; context.insert(activity) }
                activity.habitID = data.habitID; activity.amount = data.amount; activity.timestamp = data.timestamp
                activity.source = data.source
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
