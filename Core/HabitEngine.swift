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
    public let weekdayMask: Int

    public init(id: UUID = UUID(), name: String, target: Double, step: Double = 1,
                createdAt: Date, timeZoneID: String = TimeZone.current.identifier,
                preferredHour: Int = 18, durationMinutes: Int = 20, weekdayMask: Int = 127) {
        self.id = id
        self.name = name
        self.target = target.isFinite && target > 0 ? target : 1
        self.step = step.isFinite && step > 0 ? step : 1
        self.createdAt = createdAt
        self.timeZoneID = timeZoneID
        self.preferredHour = min(23, max(0, preferredHour))
        self.durationMinutes = min(240, max(5, durationMinutes))
        self.weekdayMask = (weekdayMask & 127) == 0 ? 127 : weekdayMask & 127
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
    public var fraction: Double { min(1, quantity / target) }
    public var completed: Bool { scheduled && quantity >= target }
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
    public var activeDays: Int { days.filter { $0.quantity > 0 }.count }
}

public struct CalendarDayProgress: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let scheduledGoals: Int
    public let completedGoals: Int
    public let fraction: Double
    public let hasActivity: Bool
}

public enum HabitEngine {
    public static func calendarDays(habits: [HabitSnapshot], activities: [ActivitySnapshot], dates: [Date],
                                    displayCalendar: Calendar, excludedGoals: Set<UUID> = []) -> [CalendarDayProgress] {
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        var quantities: [UUID: [Date: Double]] = [:]
        for entry in activities where entry.amount.isFinite && entry.amount > 0 {
            guard let habit = byID[entry.habitID] else { continue }
            quantities[habit.id, default: [:]][habit.calendar.startOfDay(for: entry.timestamp), default: 0] += entry.amount
        }
        return dates.map { date in
            var scheduled = 0, completed = 0
            var fraction = 0.0, hasActivity = false
            for habit in habits {
                let day = habit.date(forCalendarDay: date, displayedIn: displayCalendar)
                let quantity = quantities[habit.id]?[habit.calendar.startOfDay(for: day)] ?? 0
                hasActivity = hasActivity || quantity > 0
                guard !excludedGoals.contains(habit.id), habit.isScheduled(on: day) else { continue }
                scheduled += 1
                if quantity >= habit.target { completed += 1 }
                fraction += min(1, quantity / habit.target)
            }
            return CalendarDayProgress(date: date, scheduledGoals: scheduled, completedGoals: completed,
                fraction: scheduled > 0 ? fraction / Double(scheduled) : 0, hasActivity: hasActivity)
        }
    }
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
                           target: habit.target, registrations: entries.count, scheduled: habit.isScheduled(on: date))
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
            return DayProgress(date: $0, quantity: total.quantity, target: habit.target, registrations: total.registrations,
                               scheduled: habit.isScheduled(on: $0))
        }
        var longest = 0
        var streak = 0
        let scheduled = allDays.filter(\.scheduled)
        for day in scheduled {
            streak = day.completed ? streak + 1 : 0
            longest = max(longest, streak)
        }
        // An unfinished current day does not break yesterday's streak.
        let eligible = scheduled.last?.date == today && scheduled.last?.completed == false ? scheduled.dropLast() : scheduled[...]
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
