import Foundation

public struct BusyInterval: Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

public struct ScheduleProposal: Identifiable, Sendable {
    public var id: String { "\(habitID.uuidString)-\(Int(start.timeIntervalSince1970))" }
    public let habitID: UUID
    public let start: Date
    public let end: Date
    public let reason: ProposalReason
}

public enum ProposalReason: Sendable {
    case historicalHour(samples: Int)
    case preferredHour
}

public struct PlannedOccurrence: Sendable {
    public let habitID: UUID
    public let start: Date
    public init(habitID: UUID, start: Date) { self.habitID = habitID; self.start = start }
}

public enum ScheduleEngine {
    public static func propose(habits: [HabitSnapshot], activities: [ActivitySnapshot],
                               busy: [BusyInterval], now: Date = Date(), days: Int = 1,
                               planned: [PlannedOccurrence] = []) -> [ScheduleProposal] {
        var occupied = busy.filter { $0.end > $0.start }
        var result: [ScheduleProposal] = []
        for offset in 0..<min(28, max(1, days)) {
          for habit in habits {
            guard habit.goal == .atLeast else { continue }
            let calendar = habit.calendar
            let actualToday = calendar.startOfDay(for: now)
            let today = calendar.date(byAdding: .day, value: offset, to: actualToday)!
            guard habit.isScheduled(on: today),
                  !planned.contains(where: { $0.habitID == habit.id && calendar.isDate($0.start, inSameDayAs: today) }),
                  !HabitEngine.progress(for: habit, on: today, activities: activities).completed else { continue }
            let cutoff = calendar.date(byAdding: .day, value: -28, to: actualToday)!
            let history = activities.filter {
                $0.habitID == habit.id && $0.timestamp >= cutoff && $0.timestamp < actualToday && $0.amount.isFinite && $0.amount > 0
            }
            let hours = Dictionary(grouping: history) { calendar.component(.hour, from: $0.timestamp) }
            let bestHour = hours.keys.sorted {
                let lhs = hours[$0]!.count, rhs = hours[$1]!.count
                return lhs == rhs ? $0 < $1 : lhs > rhs
            }.first
            let enoughHistory = history.count >= 5
            let hour = enoughHistory ? (bestHour ?? habit.preferredHour) : habit.preferredHour
            let duration = TimeInterval(habit.durationMinutes * 60)
            guard let opening = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today),
                  let closing = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today) else { continue }
            var candidates: [Date] = []
            var cursor = opening
            while cursor.addingTimeInterval(duration) <= closing {
                let end = cursor.addingTimeInterval(duration)
                if cursor >= now && !occupied.contains(where: { cursor < $0.end && end > $0.start }) {
                    candidates.append(cursor)
                }
                cursor = cursor.addingTimeInterval(15 * 60)
            }
            let preferred = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today)!
            guard let start = candidates.min(by: {
                let lhs = abs($0.timeIntervalSince(preferred)), rhs = abs($1.timeIntervalSince(preferred))
                return lhs == rhs ? $0 < $1 : lhs < rhs
            }) else { continue }
            let end = start.addingTimeInterval(duration)
            result.append(ScheduleProposal(habitID: habit.id, start: start, end: end,
                reason: enoughHistory ? .historicalHour(samples: history.count) : .preferredHour))
            occupied.append(BusyInterval(start: start, end: end))
          }
        }
        return result.sorted { $0.start < $1.start }
    }
}
