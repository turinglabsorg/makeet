import Foundation

public enum HabitGoal: String, Codable, Sendable {
    case atLeast = "at_least"
    case atMost = "at_most"
}

public struct HabitSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let target: Double
    public let step: Double
    public let createdAt: Date
    public let timeZoneID: String
    public let preferredHour: Int
    public let durationMinutes: Int
    public let weekdayMask: Int
    public let goal: HabitGoal
    public let allowsNegative: Bool

    public init(id: UUID = UUID(), name: String, target: Double, step: Double = 1,
                createdAt: Date, timeZoneID: String = TimeZone.current.identifier,
                preferredHour: Int = 18, durationMinutes: Int = 20, weekdayMask: Int = 127,
                goal: HabitGoal = .atLeast, allowsNegative: Bool = false) {
        self.id = id
        self.name = name
        self.target = target.isFinite && (target > 0 || (goal == .atMost && target == 0)) ? target : 1
        self.step = step.isFinite && step > 0 ? step : 1
        self.createdAt = createdAt
        self.timeZoneID = timeZoneID
        self.preferredHour = min(23, max(0, preferredHour))
        self.durationMinutes = min(240, max(5, durationMinutes))
        self.weekdayMask = (weekdayMask & 127) == 0 ? 127 : weekdayMask & 127
        self.goal = goal
        self.allowsNegative = allowsNegative
    }

    public func isScheduled(on date: Date) -> Bool {
        calendar.startOfDay(for: date) >= calendar.startOfDay(for: createdAt)
            && weekdayMask & (1 << ((calendar.component(.weekday, from: date) + 5) % 7)) != 0
    }

    public func date(forCalendarDay date: Date, displayedIn display: Calendar) -> Date {
        var components = display.dateComponents([.year, .month, .day], from: date)
        components.hour = 12
        return calendar.date(from: components)!
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
    public var scheduled: Bool = true
    public var goal: HabitGoal = .atLeast
    public var fraction: Double {
        if goal == .atMost {
            guard registrations > 0 else { return 0 }
            if quantity <= target { return 1 }
            return target > 0 ? max(0, target / quantity) : 0
        }
        return min(1, max(0, quantity / target))
    }
    public var completed: Bool {
        scheduled && (goal == .atMost ? registrations > 0 && quantity <= target : quantity >= target)
    }
    public var malus: Double { max(0, goal == .atMost ? quantity - target : -quantity) }
}

public struct HabitStatistics: Sendable {
    public let days: [DayProgress]
    public let currentStreak: Int
    public let longestStreak: Int
    public let hourlyRegistrations: [Int]
    public var completedDays: Int { days.filter(\.completed).count }
    public var scheduledDays: Int { days.filter(\.scheduled).count }
    public var completionRate: Double { scheduledDays == 0 ? 0 : Double(completedDays) / Double(scheduledDays) }
    public var total: Double { days.reduce(0) { $0 + $1.quantity } }
    public var average: Double { days.isEmpty ? 0 : total / Double(days.count) }
    public var activeDays: Int { days.filter { $0.registrations > 0 }.count }
}

public struct CalendarDayProgress: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let scheduledGoals: Int
    public let completedGoals: Int
    public let fraction: Double
    public let hasActivity: Bool
    public var hasMalus: Bool = false
}

public struct QuantityTotal: Sendable {
    private var sum = 0.0
    private var magnitude = 0.0
    public init() {}
    public mutating func add(_ amount: Double) {
        guard amount.isFinite else { return }
        sum += amount
        magnitude += abs(amount)
    }
    public var value: Double {
        abs(sum) <= magnitude.ulp * 8 ? 0 : sum
    }
    public static func sum<S: Sequence>(_ amounts: S) -> Double where S.Element == Double {
        var total = Self()
        for amount in amounts { total.add(amount) }
        return total.value
    }
}

public enum HabitEngine {
    public static func calendarDays(habits: [HabitSnapshot], activities: [ActivitySnapshot], dates: [Date],
                                    displayCalendar: Calendar, excludedGoals: Set<UUID> = []) -> [CalendarDayProgress] {
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        var quantities: [UUID: [Date: QuantityTotal]] = [:]
        var registrations: [UUID: [Date: Int]] = [:]
        for entry in activities where entry.amount.isFinite {
            guard let habit = byID[entry.habitID] else { continue }
            let day = habit.calendar.startOfDay(for: entry.timestamp)
            quantities[habit.id, default: [:]][day, default: QuantityTotal()].add(entry.amount)
            registrations[habit.id, default: [:]][day, default: 0] += 1
        }
        return dates.map { date in
            var scheduled = 0, completed = 0
            var fraction = 0.0, hasActivity = false
            var hasMalus = false
            for habit in habits {
                let day = habit.date(forCalendarDay: date, displayedIn: displayCalendar)
                let start = habit.calendar.startOfDay(for: day)
                let quantity = quantities[habit.id]?[start]?.value ?? 0
                let count = registrations[habit.id]?[start] ?? 0
                hasActivity = hasActivity || count > 0
                guard !excludedGoals.contains(habit.id), habit.isScheduled(on: day) else { continue }
                scheduled += 1
                let progress = DayProgress(date: start, quantity: quantity, target: habit.target,
                                           registrations: count, goal: habit.goal)
                if progress.completed { completed += 1 }
                fraction += progress.fraction
                hasMalus = hasMalus || progress.malus > 0
            }
            return CalendarDayProgress(date: date, scheduledGoals: scheduled, completedGoals: completed,
                fraction: scheduled > 0 ? fraction / Double(scheduled) : 0, hasActivity: hasActivity, hasMalus: hasMalus)
        }
    }
    public static func progress(for habit: HabitSnapshot, on date: Date,
                                activities: [ActivitySnapshot]) -> DayProgress {
        let calendar = habit.calendar
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let entries = activities.filter {
            $0.habitID == habit.id && $0.timestamp >= start && $0.timestamp < end
                && $0.amount.isFinite
        }
        return DayProgress(date: start, quantity: QuantityTotal.sum(entries.map(\.amount)),
                           target: habit.target, registrations: entries.count, scheduled: habit.isScheduled(on: date), goal: habit.goal)
    }

    public static func statistics(for habit: HabitSnapshot, activities: [ActivitySnapshot],
                                  now: Date = Date(), window: Int = 28) -> HabitStatistics {
        let calendar = habit.calendar
        let today = calendar.startOfDay(for: now)
        let created = calendar.startOfDay(for: habit.createdAt)
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let entries = activities.filter {
            $0.habitID == habit.id && $0.timestamp >= created && $0.timestamp < end
                && $0.amount.isFinite
        }
        var totals: [Date: (quantity: QuantityTotal, registrations: Int)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            var previous = totals[day, default: (QuantityTotal(), 0)]
            previous.quantity.add(entry.amount)
            totals[day] = (previous.quantity, previous.registrations + 1)
        }
        let allDays = days(from: created, through: today, calendar: calendar).map {
            let total = totals[$0, default: (QuantityTotal(), 0)]
            return DayProgress(date: $0, quantity: total.quantity.value, target: habit.target, registrations: total.registrations,
                               scheduled: habit.isScheduled(on: $0), goal: habit.goal)
        }
        var longest = 0
        var streak = 0
        let scheduled = allDays.filter(\.scheduled)
        for day in scheduled {
            streak = day.completed ? streak + 1 : 0
            longest = max(longest, streak)
        }
        // An unfinished current day does not break yesterday's streak.
        let unfinishedToday = scheduled.last?.date == today && scheduled.last?.completed == false
            && (habit.goal == .atLeast || scheduled.last?.registrations == 0)
        let eligible = unfinishedToday ? scheduled.dropLast() : scheduled[...]
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
