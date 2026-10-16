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
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), habits: [WidgetHabit(id: UUID(), name: "Bere acqua", symbol: "drop",
            colorIndex: 1, unit: "bicchieri", quantity: 4, target: 8, step: 1)])
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
            let container = try SharedStore.makeContainer()
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
            return ProgressEntry(date: Date(), habits: values)
        } catch { return ProgressEntry(date: Date(), habits: [], unavailable: true) }
    }
}

struct LogHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Registra un passo"
    static var description = IntentDescription("Aggiunge la quantità scelta all’abitudine, senza aprire Makeet.")
    static var openAppWhenRun = false
    @Parameter(title: "Abitudine") var habitID: String
    init() {}
    init(habitID: UUID) { self.habitID = habitID.uuidString }
    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { throw IntentFailure.missingHabit }
        let container = try SharedStore.makeContainer()
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id && !$0.archived })
        guard let habit = try context.fetch(descriptor).first else { throw IntentFailure.missingHabit }
        try SharedStore.log(habit, in: context, source: "widget")
        return .result()
    }
}

enum IntentFailure: LocalizedError {
    case missingHabit
    var errorDescription: String? { "Questa abitudine non è più disponibile. Apri Makeet per aggiornare il widget." }
}

struct ProgressWidgetView: View {
    let entry: ProgressEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("makeet").font(.system(.headline, design: .default))
                Spacer()
                Image(systemName: "leaf").foregroundStyle(Palette.accent)
            }
            if entry.habits.isEmpty {
                Text(entry.unavailable ? "Apri Makeet per accedere ai tuoi dati." : "Un piccolo passo, oggi.")
                    .font(.subheadline)
                Text(entry.unavailable ? "Archivio non disponibile" : "Crea la prima abitudine nell’app.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.habits.prefix(family == .systemSmall ? 1 : 3))) { habit in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(habit.name, systemImage: habit.symbol).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(habit.quantity.quantityText) / \(habit.target.quantityText) \(habit.unit)")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        Button(intent: LogHabitIntent(habitID: habit.id)) {
                            Text("+\(habit.step.quantityText)").font(.subheadline.weight(.semibold))
                                .frame(minWidth: 38, minHeight: 38)
                        }.buttonStyle(.plain).foregroundStyle(Palette.habit(habit.colorIndex))
                            .background(Palette.habit(habit.colorIndex).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Aggiungi \(habit.step.quantityText) \(habit.unit) a \(habit.name)")
                    }
                    if family == .systemSmall {
                        ProgressView(value: min(habit.quantity / habit.target, 1)).tint(Palette.habit(habit.colorIndex))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .containerBackground(Palette.paper, for: .widget)
        .widgetURL(URL(string: "makeet://habit"))
    }
}

@main struct MakeetWidget: Widget {
    let kind = "MakeetProgress"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressProvider()) { ProgressWidgetView(entry: $0) }
            .configurationDisplayName("Un passo con Makeet")
            .description("I tuoi progressi e un tocco per registrarli.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
