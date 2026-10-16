import Foundation
import SwiftData
import WidgetKit
#if SWIFT_PACKAGE
import MakeetCore
#endif

@Model final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "leaf"
    var colorIndex: Int = 0
    var target: Double = 1
    var step: Double = 1
    var unit: String = "volte"
    var createdAt: Date = Date()
    var timeZoneID: String = TimeZone.current.identifier
    var preferredHour: Int = 18
    var durationMinutes: Int = 20
    var archived: Bool = false
    var isDemo: Bool = false

    init(name: String, symbol: String, colorIndex: Int, target: Double, step: Double,
         unit: String, preferredHour: Int = 18, durationMinutes: Int = 20, createdAt: Date = Date()) {
        self.name = name; self.symbol = symbol; self.colorIndex = colorIndex
        self.target = target; self.step = step; self.unit = unit
        self.preferredHour = preferredHour; self.durationMinutes = durationMinutes
        self.createdAt = createdAt
    }

    var snapshot: HabitSnapshot {
        HabitSnapshot(id: id, name: name, target: target, step: step, createdAt: createdAt,
                      timeZoneID: timeZoneID, preferredHour: preferredHour, durationMinutes: durationMinutes)
    }
}

@Model final class Activity {
    var id: UUID = UUID()
    var habitID: UUID = UUID()
    var amount: Double = 1
    var timestamp: Date = Date()
    var source: String = "app"

    init(habitID: UUID, amount: Double, timestamp: Date = Date(), source: String = "app") {
        self.habitID = habitID; self.amount = amount; self.timestamp = timestamp; self.source = source
    }
    var snapshot: ActivitySnapshot {
        ActivitySnapshot(id: id, habitID: habitID, amount: amount, timestamp: timestamp)
    }
}

enum SharedStore {
    static let group = "group.org.turinglabs.makeet"
    static let cloudContainer = "iCloud.org.turinglabs.makeet"
    static var cloudEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "CloudSyncEnabled") as? Bool == true }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Habit.self, Activity.self])
        let configuration = ModelConfiguration("HabitStore", schema: schema,
            groupContainer: .identifier(group),
            cloudKitDatabase: cloudEnabled ? .private(cloudContainer) : .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor static func log(_ habit: Habit, in context: ModelContext, source: String = "app") throws {
        guard habit.step.isFinite, habit.step > 0, !habit.archived else { return }
        context.insert(Activity(habitID: habit.id, amount: habit.step, source: source))
        do { try context.save() } catch { context.rollback(); throw error }
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor static func decrement(_ habit: Habit, in context: ModelContext, now: Date = Date()) throws {
        guard habit.step.isFinite, habit.step > 0, !habit.archived else { return }
        let calendar = habit.snapshot.calendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let id = habit.id
        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate {
            $0.habitID == id && $0.timestamp >= start && $0.timestamp < end && $0.amount > 0
        }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let entries = try context.fetch(descriptor).filter { $0.amount.isFinite }
        var remaining = habit.step
        for entry in entries where remaining > 0 {
            let removed = min(remaining, entry.amount)
            let corrected = entry.amount - removed
            remaining -= removed
            if corrected <= max(entry.amount.ulp, removed.ulp) * 8 { context.delete(entry) }
            else { entry.amount = corrected }
        }
        do { try context.save() } catch { context.rollback(); throw error }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
