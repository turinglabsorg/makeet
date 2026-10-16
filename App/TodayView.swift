import SwiftUI
import SwiftData
import WidgetKit

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Habit.createdAt), SortDescriptor(\Habit.name)]) private var allHabits: [Habit]
    @Query private var activities: [Activity]
    @Binding var demoMode: Bool
    @State private var adding = false
    @State private var error: String?
    @State private var resetting = false
    @State private var now = Date()
    @Environment(\.scenePhase) private var phase
    private var habits: [Habit] { allHabits.filter { !$0.archived } }
    private var snapshots: [ActivitySnapshot] { activities.map(\.snapshot) }
    private var completed: Int { habits.filter { HabitEngine.progress(for: $0.snapshot, on: now, activities: snapshots).completed }.count }
    private var dailyFraction: Double {
        guard !habits.isEmpty else { return 0 }
        return habits.reduce(0) { $0 + HabitEngine.progress(for: $1.snapshot, on: now, activities: snapshots).fraction } / Double(habits.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "it_IT"))), systemImage: "sun.max")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("MAKEET").font(.caption.weight(.bold)).tracking(3)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Un po’ ogni giorno.").font(.system(.largeTitle, design: .default, weight: .semibold))
                    Text("Fai spazio a ciò che ti fa bene.").foregroundStyle(.secondary)
                }
                if demoMode {
                    HStack {
                        Label("Dati dimostrativi", systemImage: "flask").font(.caption)
                        Spacer()
                        Button("Svuota") { resetting = true }.font(.caption.weight(.semibold))
                    }.padding(12).background(Palette.soft, in: RoundedRectangle(cornerRadius: 12))
                }
                if habits.isEmpty { emptyState }
                else {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle().stroke(Palette.accent.opacity(0.12), lineWidth: 7)
                            Circle().trim(from: 0, to: dailyFraction).stroke(Palette.accent,
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                            Text(dailyFraction, format: .percent.precision(.fractionLength(0)))
                                .font(.system(.title3, design: .default, weight: .semibold)).monospacedDigit()
                        }.frame(width: 72, height: 72).accessibilityElement(children: .ignore)
                            .accessibilityLabel("Progresso giornaliero \(Int(dailyFraction * 100)) per cento")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("La tua giornata").font(.headline)
                            Text("\(completed) di \(habits.count) obiettivi raggiunti").font(.subheadline).foregroundStyle(.secondary)
                            Text("Anche i piccoli passi contano.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.journalCard()
                    HStack {
                        Text("LE TUE ABITUDINI").font(.caption.weight(.semibold)).tracking(1.6)
                        Spacer()
                        Text("Oggi").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 14) {
                        ForEach(habits) { habit in
                            HabitCard(habit: habit, activities: activities, now: now) { log(habit) }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles").font(.title3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Le abitudini incontrano la tua agenda.").font(.subheadline.weight(.semibold))
                            Text("In “Il tuo piano” trovi gli orari proposti in base ai tuoi progressi e agli spazi liberi.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(18).background(Palette.soft, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(24).frame(maxWidth: 650)
        }
        .journalBackground()
        .toolbar {
            ToolbarItem {
                NavigationLink { ArchivedHabitsView() } label: { Image(systemName: "archivebox") }
                    .accessibilityLabel("Abitudini archiviate")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuova abitudine").accessibilityIdentifier("addHabit")
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(Palette.paper, for: .navigationBar)
        #endif
        .sheet(isPresented: $adding) { AddHabitView() }
        .alert("Operazione non riuscita", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("Eliminare tutti i dati dimostrativi?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Elimina demo", role: .destructive) {
                do {
                    for entry in activities where entry.source == "demo" { context.delete(entry) }
                    for habit in habits where habit.isDemo {
                        if activities.contains(where: { $0.habitID == habit.id && $0.source != "demo" }) {
                            habit.isDemo = false
                        } else { context.delete(habit) }
                    }
                    try context.save(); demoMode = false; WidgetCenter.shared.reloadAllTimelines()
                } catch { context.rollback(); self.error = error.localizedDescription }
            }
        }
        .onChange(of: phase) { _, value in if value == .active { now = Date() } }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)); now = Date() } catch { break }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "leaf").font(.system(size: 42, weight: .light)).foregroundStyle(Palette.accent)
            Text("Inizia da una cosa.").font(.system(.title2, design: .default))
            Text("Scegli un’abitudine, la quantità che vuoi raggiungere e il tuo momento ideale. Al resto diamo forma insieme.")
                .foregroundStyle(.secondary)
            Button("Crea la prima abitudine") { adding = true }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("Esplora con dati demo") {
                do { try DemoData.insert(in: context); demoMode = true }
                catch { self.error = error.localizedDescription }
            }.font(.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading).journalCard()
    }

    private func log(_ habit: Habit) {
        do { try SharedStore.log(habit, in: context) }
        catch { self.error = error.localizedDescription }
    }
}

struct ArchivedHabitsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Habit> { $0.archived }, sort: \Habit.name) private var habits: [Habit]
    @State private var error: String?
    var body: some View {
        List {
                if habits.isEmpty {
                    ContentUnavailableView("Nessuna abitudine archiviata", systemImage: "archivebox",
                        description: Text("Le abitudini archiviate conservano tutto lo storico."))
                }
                ForEach(habits) { habit in
                    HStack {
                        Label(habit.name, systemImage: habit.symbol)
                        Spacer()
                        Button("Ripristina") {
                            habit.archived = false
                            do { try context.save(); WidgetCenter.shared.reloadAllTimelines() }
                            catch { context.rollback(); self.error = error.localizedDescription }
                        }.buttonStyle(.bordered)
                    }
                }
            }.navigationTitle("Archiviate")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
                .alert("Ripristino non riuscito", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }
}

struct HabitCard: View {
    let habit: Habit
    let activities: [Activity]
    let now: Date
    let increment: () -> Void
    private var progress: DayProgress { HabitEngine.progress(for: habit.snapshot, on: now, activities: activities.map(\.snapshot)) }
    private var tint: Color { Palette.habit(habit.colorIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: habit.symbol).font(.title3).foregroundStyle(tint)
                    .frame(width: 42, height: 42).background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                NavigationLink { HabitDetailView(habit: habit) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(habit.name).font(.headline).foregroundStyle(Palette.ink)
                        Text("\(progress.quantity.quantityText) / \(habit.target.quantityText) \(habit.unit)")
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button(action: increment) {
                    Text("+\(habit.step.quantityText)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .frame(minWidth: 50, minHeight: 44).background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).foregroundStyle(tint)
                    .accessibilityLabel("Aggiungi \(habit.step.quantityText) \(habit.unit) a \(habit.name)")
                    .accessibilityIdentifier("increment-\(habit.name)")
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.10))
                    Capsule().fill(tint).frame(width: max(0, geometry.size.width * progress.fraction))
                }
            }.frame(height: 4).accessibilityHidden(true)
            HStack(spacing: 5) {
                ForEach(0..<14, id: \.self) { index in
                    let date = habit.snapshot.calendar.date(byAdding: .day, value: index - 13, to: now)!
                    let day = HabitEngine.progress(for: habit.snapshot, on: date, activities: activities.map(\.snapshot))
                    RoundedRectangle(cornerRadius: 4).fill(tint.opacity(day.quantity > 0 ? 0.20 + day.fraction * 0.80 : 0.07))
                        .frame(maxWidth: .infinity).frame(height: 15)
                        .overlay { if day.completed { Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white) } }
                }
            }.accessibilityLabel("Attività degli ultimi 14 giorni")
        }.journalCard()
    }
}
