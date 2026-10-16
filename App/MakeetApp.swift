import SwiftUI
import SwiftData

@main struct MakeetApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #else
    @NSApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #endif
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                container = try ModelContainer(for: Habit.self, Activity.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } else { container = try SharedStore.makeContainer() }
            startupError = nil
        }
        catch { container = nil; startupError = error.localizedDescription }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView().modelContainer(container).tint(Palette.accent)
                    .environment(NotificationService.shared)
            } else {
                ContentUnavailableView("Archivio non disponibile", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "Riapri l’app per riprovare."))
            }
        }
        #if os(macOS)
        .defaultSize(width: 540, height: 820)
        #endif
    }
}

struct RootView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var calendar = CalendarService()
    @State private var selection = 0
    @State private var error: String?
    @AppStorage("demoMode") private var demoMode = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView(demoMode: $demoMode) }
                .tabItem { Label("Oggi", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { TrendsView() }
                .tabItem { Label("Andamento", systemImage: "chart.xyaxis.line") }.tag(1)
            NavigationStack { PlannerView(calendar: calendar) }
                .tabItem { Label("Il tuo piano", systemImage: "sparkles") }.tag(2)
        }
        .foregroundStyle(Palette.ink)
        .task {
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await notifications.refresh() }
            if ProcessInfo.processInfo.arguments.contains("--demo"),
               !demoMode || ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                do { try DemoData.insert(in: context); demoMode = true }
                catch { self.error = error.localizedDescription }
            }
        }
        .onChange(of: phase) { _, value in
            if value == .active {
                calendar.refresh()
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { Task { await notifications.refresh() } }
            }
        }
        .onChange(of: notifications.destination, initial: true) { _, value in
            if let value {
                selection = value == "today" ? 0 : 2
                notifications.destination = nil
            }
        }
        .onOpenURL { url in
            if url.host == "habit" { selection = 0 }
            if url.host == "plan" { selection = 2 }
        }
        .alert("Operazione non riuscita", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

enum DemoData {
    @MainActor static func insert(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Habit>()) == 0 else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -83, to: today)!
        let habits = [
            Habit(name: "Bere acqua", symbol: "drop", colorIndex: 1, target: 8, step: 1, unit: "bicchieri", preferredHour: 10, durationMinutes: 5, createdAt: start),
            Habit(name: "Leggere", symbol: "book.closed", colorIndex: 0, target: 20, step: 5, unit: "pagine", preferredHour: 19, durationMinutes: 20, createdAt: start),
            Habit(name: "Muovermi", symbol: "figure.walk", colorIndex: 2, target: 30, step: 10, unit: "minuti", preferredHour: 18, durationMinutes: 30, createdAt: start)
        ]
        for (index, habit) in habits.enumerated() {
            habit.isDemo = true
            context.insert(habit)
            for offset in 0..<84 {
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                let steps = offset == 0 ? [4, 2, 0][index] : ((offset * 7 + index * 3) % 11 < 8 ? Int(habit.target / habit.step) : index + 1)
                for step in 0..<steps {
                    let hour = (habit.preferredHour + step) % 22
                    let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                    context.insert(Activity(habitID: habit.id, amount: habit.step,
                        timestamp: offset == 0 ? min(time, Date()) : time, source: "demo"))
                }
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
