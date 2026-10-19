import Foundation
import SwiftData
import WidgetKit
#if SWIFT_PACKAGE
import MakeetCore
#endif

struct HabitDayCorrection {
    let habitID: UUID
    let date: Date
    let quantity: Double
    let expectedQuantity: Double
    var confirmZero: Bool = false
}

enum DayCorrectionFailure: LocalizedError {
    case changed, invalidDay
    var errorDescription: String? {
        switch self {
        case .changed: String(localized: "I progressi sono cambiati. Riapri il giorno per usare i valori aggiornati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .invalidDay: String(localized: "Puoi correggere i giorni già trascorsi dalla data di inizio dell’abitudine.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
}

extension SharedStore {
    @MainActor static func deleteHabit(_ id: UUID, in context: ModelContext) throws {
        do {
            for entry in try context.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.habitID == id })) { context.delete(entry) }
            if let habit = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first { context.delete(habit) }
            try context.save()
        } catch { context.rollback(); throw error }
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor static func correct(_ corrections: [HabitDayCorrection], in context: ModelContext, now: Date = Date()) throws {
        do {
            var seen = Set<UUID>()
            for correction in corrections {
                guard seen.insert(correction.habitID).inserted, correction.quantity.isFinite else { throw DayCorrectionFailure.invalidDay }
                let id = correction.habitID
                guard let habit = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first, !habit.archived else { throw DayCorrectionFailure.invalidDay }
                guard correction.quantity >= 0 || habit.allowsNegative else { throw DayCorrectionFailure.invalidDay }
                let calendar = habit.snapshot.calendar
                let start = calendar.startOfDay(for: correction.date)
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                guard start >= calendar.startOfDay(for: habit.createdAt), start <= calendar.startOfDay(for: now) else { throw DayCorrectionFailure.invalidDay }
                let entries = try context.fetch(FetchDescriptor<Activity>(predicate: #Predicate {
                    $0.habitID == id && $0.timestamp >= start && $0.timestamp < end
                }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])).filter { $0.amount.isFinite }
                let quantity = QuantityTotal.sum(entries.map(\.amount))
                guard abs(quantity - correction.expectedQuantity) <= max(quantity.ulp, correction.expectedQuantity.ulp) * 8 else { throw DayCorrectionFailure.changed }
                let timestamp = calendar.isDate(start, inSameDayAs: now) ? now : calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start)!
                if correction.quantity == quantity {
                    if correction.confirmZero && habit.goal == .atMost && quantity == 0 && entries.isEmpty {
                        context.insert(Activity(habitID: id, amount: 0, timestamp: timestamp, source: "correction"))
                    }
                } else if habit.allowsNegative || entries.contains(where: { $0.amount < 0 }) || correction.quantity > quantity {
                    context.insert(Activity(habitID: id, amount: correction.quantity - quantity, timestamp: timestamp, source: "correction"))
                } else {
                    var remaining = quantity - correction.quantity
                    for entry in entries where remaining > 0 {
                        let removed = min(remaining, entry.amount)
                        remaining -= removed
                        if entry.amount - removed <= max(entry.amount.ulp, removed.ulp) * 8 { context.delete(entry) }
                        else { entry.amount -= removed }
                    }
                    if habit.goal == .atMost && correction.quantity == 0 {
                        context.insert(Activity(habitID: id, amount: 0, timestamp: timestamp, source: "correction"))
                    }
                }
            }
            try context.save()
        } catch { context.rollback(); throw error }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
