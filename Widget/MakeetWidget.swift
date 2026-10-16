import SwiftUI
import WidgetKit
import SwiftData
import AppIntents

struct WidgetHabit: Identifiable {
    let id: UUID
    let name: String
    let symbol: String
    let colorIndex: Int
    let unit: String
    let quantity: Double
    let target: Double
    let step: Double
}

struct ProgressEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabit]
    var unavailable = false
    var scope = "local"
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), habits: [WidgetHabit(id: UUID(), name: String(localized: "Bere acqua"), symbol: "drop",
            colorIndex: 1, unit: String(localized: "bicchieri"), quantity: 4, target: 8, step: 1)])
    }
    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)) }
        else { Task { @MainActor in completion(load()) } }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        Task { @MainActor in
            let entry = load()
            let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            let refresh = min(midnight, Date().addingTimeInterval(900))
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
    @MainActor private func load() -> ProgressEntry {
        do {
            return try WidgetAccountScope.withContainer { container, scope in
                let context = ModelContext(container)
                let habits = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { !$0.archived }, sortBy: [SortDescriptor(\.createdAt)]))
                let activities = try context.fetch(FetchDescriptor<Activity>()).map(\.snapshot)
                let values = habits.map { habit in
                    let progress = HabitEngine.progress(for: habit.snapshot, on: Date(), activities: activities)
                    return WidgetHabit(id: habit.id, name: habit.name, symbol: habit.symbol, colorIndex: habit.colorIndex,
                        unit: habit.unit, quantity: progress.quantity, target: habit.target, step: habit.step)
                }.sorted { lhs, rhs in
                    let leftDone = lhs.quantity >= lhs.target, rightDone = rhs.quantity >= rhs.target
                    return leftDone != rightDone ? !leftDone : lhs.name < rhs.name
                }
                return ProgressEntry(date: Date(), habits: values, scope: scope)
            }
        } catch { return ProgressEntry(date: Date(), habits: [], unavailable: true) }
    }
}

struct LogHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Registra un passo"
    static var description = IntentDescription("Aggiunge la quantità scelta all’abitudine, senza aprire Makeet.")
    static var openAppWhenRun = false
    @Parameter(title: "Abitudine") var habitID: String
    @Parameter(title: "Archivio") var storeScope: String
    init() {}
    init(habitID: UUID, scope: String) { self.habitID = habitID.uuidString; storeScope = scope }
    @MainActor func perform() async throws -> some IntentResult {
        try HabitIntentStore.change(habitID, scope: storeScope, subtract: false)
        return .result()
    }
}

struct DecrementHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Togli un passo"
    static var description = IntentDescription("Riduce la quantità di oggi, senza scendere sotto zero o aprire Makeet.")
    static var openAppWhenRun = false
    @Parameter(title: "Abitudine") var habitID: String
    @Parameter(title: "Archivio") var storeScope: String
    init() {}
    init(habitID: UUID, scope: String) { self.habitID = habitID.uuidString; storeScope = scope }
    @MainActor func perform() async throws -> some IntentResult {
        try HabitIntentStore.change(habitID, scope: storeScope, subtract: true)
        return .result()
    }
}

enum HabitIntentStore {
    @MainActor static func change(_ habitID: String, scope: String, subtract: Bool) throws {
        guard let id = UUID(uuidString: habitID) else { throw IntentFailure.missingHabit }
        try WidgetAccountScope.withContainer(expected: scope) { container, _ in
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id && !$0.archived })
            guard let habit = try context.fetch(descriptor).first else { throw IntentFailure.missingHabit }
            if subtract { try SharedStore.decrement(habit, in: context) }
            else { try SharedStore.log(habit, in: context, source: "widget") }
        }
    }
}

enum IntentFailure: LocalizedError {
    case missingHabit
    var errorDescription: String? { String(localized: "Questa abitudine non è più disponibile. Apri Makeet per aggiornare il widget.") }
}

struct ProgressWidgetView: View {
    let entry: ProgressEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: "makeet").font(.system(.headline, design: .default))
                Spacer()
                Image(systemName: "leaf").foregroundStyle(Palette.accent)
            }
            if entry.habits.isEmpty {
                Text(entry.unavailable ? String(localized: "Apri Makeet per accedere ai tuoi dati.") : String(localized: "Un piccolo passo, oggi."))
                    .font(.subheadline)
                Text(entry.unavailable ? String(localized: "Archivio non disponibile") : String(localized: "Crea la prima abitudine nell’app."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.habits.prefix(family == .systemSmall ? 1 : 2))) { habit in
                    if family == .systemSmall {
                        info(habit)
                        HStack { minus(habit); Spacer(minLength: 0); plus(habit) }
                        ProgressView(value: min(habit.quantity / habit.target, 1)).tint(Palette.habit(habit.colorIndex))
                    } else {
                        HStack(spacing: 10) { minus(habit); info(habit); Spacer(minLength: 0); plus(habit) }
                    }
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .containerBackground(Palette.paper, for: .widget)
        .widgetURL(URL(string: "makeet://habit"))
    }

    private func info(_ habit: WidgetHabit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label { Text(habit.name) } icon: { HabitMark(symbol: habit.symbol) }
                .font(.subheadline.weight(.medium)).lineLimit(1)
            Text(String(localized: "\(habit.quantity.quantityText) / \(habit.target.quantityText) \(habit.unit)"))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func minus(_ habit: WidgetHabit) -> some View {
        Button(intent: DecrementHabitIntent(habitID: habit.id, scope: entry.scope)) {
            Text("−\(habit.step.quantityText)").font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(Palette.habit(habit.colorIndex))
            .background(Palette.habit(habit.colorIndex).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .disabled(habit.quantity <= 0).opacity(habit.quantity > 0 ? 1 : 0.35)
            .accessibilityLabel(String(localized: "Togli \(habit.step.quantityText) \(habit.unit) da \(habit.name)"))
    }

    private func plus(_ habit: WidgetHabit) -> some View {
        Button(intent: LogHabitIntent(habitID: habit.id, scope: entry.scope)) {
            Text("+\(habit.step.quantityText)").font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(Palette.habit(habit.colorIndex))
            .background(Palette.habit(habit.colorIndex).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(String(localized: "Aggiungi \(habit.step.quantityText) \(habit.unit) a \(habit.name)"))
    }
}

@main struct MakeetWidget: Widget {
    let kind = "MakeetProgress"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressProvider()) { ProgressWidgetView(entry: $0) }
            .configurationDisplayName("Un passo con Makeet")
            .description(String(localized: "I tuoi progressi e un tocco per registrarli."))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
