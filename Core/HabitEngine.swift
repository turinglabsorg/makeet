import Foundation

public struct HabitSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let target: Double
    public let step: Double
    public let createdAt: Date
    public let timeZoneID: String
    public let preferredHour: Int
    public let durationMinutes: Int

    public init(id: UUID = UUID(), name: String, target: Double, step: Double = 1,
                createdAt: Date, timeZoneID: String = TimeZone.current.identifier,
                preferredHour: Int = 18, durationMinutes: Int = 20) {
        self.id = id
        self.name = name
        self.target = target.isFinite && target > 0 ? target : 1
        self.step = step.isFinite && step > 0 ? step : 1
        self.createdAt = createdAt
        self.timeZoneID = timeZoneID
        self.preferredHour = min(23, max(0, preferredHour))
        self.durationMinutes = min(240, max(5, durationMinutes))
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }
}

public struct ActivitySnapshot: Sendable {
    public let id: UUID
    public let habitID: UUID
    public let amount: Double
    public let timestamp: Date

    public init(id: UUID = UUID(), habitID: UUID, amount: Double, timestamp: Date) {
        self.id = id
        self.habitID = habitID
        self.amount = amount
        self.timestamp = timestamp
    }
}

public struct DayProgress: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let quantity: Double
    public let target: Double
    public let registrations: Int
    public var fraction: Double { min(1, quantity / target) }
    public var completed: Bool { quantity >= target }
}

public struct HabitStatistics: Sendable {
    public let days: [DayProgress]
    public let currentStreak: Int
    public let longestStreak: Int
    public let hourlyRegistrations: [Int]
    public var completedDays: Int { days.filter(\.completed).count }
    public var completionRate: Double { days.isEmpty ? 0 : Double(completedDays) / Double(days.count) }
    public var total: Double { days.reduce(0) { $0 + $1.quantity } }
    public var average: Double { days.isEmpty ? 0 : total / Double(days.count) }
    public var activeDays: Int { days.filter { $0.quantity > 0 }.count }
}

public enum HabitEngine {
    public static func progress(for habit: HabitSnapshot, on date: Date,
                                activities: [ActivitySnapshot]) -> DayProgress {
        let calendar = habit.calendar
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let entries = activities.filter {
            $0.habitID == habit.id && $0.timestamp >= start && $0.timestamp < end
                && $0.amount.isFinite && $0.amount > 0
        }
        return DayProgress(date: start, quantity: entries.reduce(0) { $0 + $1.amount },
                           target: habit.target, registrations: entries.count)
    }

    public static func statistics(for habit: HabitSnapshot, activities: [ActivitySnapshot],
                                  now: Date = Date(), window: Int = 28) -> HabitStatistics {
        let calendar = habit.calendar
        let today = calendar.startOfDay(for: now)
        let created = calendar.startOfDay(for: habit.createdAt)
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let entries = activities.filter {
            $0.habitID == habit.id && $0.timestamp >= created && $0.timestamp < end
                && $0.amount.isFinite && $0.amount > 0
        }
        var totals: [Date: (quantity: Double, registrations: Int)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            let previous = totals[day, default: (0, 0)]
            totals[day] = (previous.quantity + entry.amount, previous.registrations + 1)
        }
        let allDays = days(from: created, through: today, calendar: calendar).map {
            let total = totals[$0, default: (0, 0)]
            return DayProgress(date: $0, quantity: total.quantity, target: habit.target, registrations: total.registrations)
        }
        var longest = 0
        var streak = 0
        for day in allDays {
            streak = day.completed ? streak + 1 : 0
            longest = max(longest, streak)
        }
        // An unfinished current day does not break yesterday's streak.
        let eligible = allDays.last?.completed == false ? allDays.dropLast() : allDays[...]
        let current = eligible.reversed().prefix(while: \.completed).count
        let visible = Array(allDays.suffix(max(1, window)))
        var hourly = [Int](repeating: 0, count: 24)
        if let start = visible.first?.date {
            for entry in entries where entry.timestamp >= start {
                hourly[calendar.component(.hour, from: entry.timestamp)] += 1
            }
        }
        return HabitStatistics(days: visible, currentStreak: current, longestStreak: longest, hourlyRegistrations: hourly)
    }

    public static func days(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }
}
