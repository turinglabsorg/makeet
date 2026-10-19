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
    @Environment(AccountManager.self) private var account
    @State private var settings: SettingsDestination?
    private var habits: [Habit] { allHabits.filter { !$0.archived && $0.snapshot.isScheduled(on: now) } }
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
                    Label(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale)), systemImage: "sun.max")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("MAKEET").font(.caption.weight(.bold)).tracking(3)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Un po’ ogni giorno.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.system(.largeTitle, design: .default, weight: .semibold))
                    Text(String(localized: "Fai spazio a ciò che ti fa bene.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).foregroundStyle(.secondary)
                }
                if demoMode {
                    HStack {
                        Label(String(localized: "Dati dimostrativi", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "flask").font(.caption)
                        Spacer()
                        Button(String(localized: "Svuota", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { resetting = true }.font(.caption.weight(.semibold))
                    }.padding(12).background(Palette.soft, in: RoundedRectangle(cornerRadius: 12))
                }
                if habits.isEmpty && !allHabits.contains(where: { !$0.archived }) { emptyState }
                else if habits.isEmpty {
                    ContentUnavailableView(String(localized: "Oggi puoi riposare", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "leaf",
                        description: Text(String(localized: "Non hai abitudini in programma. Nel Calendario puoi vedere e correggere tutti i tuoi progressi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
                }
                else {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle().stroke(Palette.accent.opacity(0.12), lineWidth: 7)
                            Circle().trim(from: 0, to: dailyFraction).stroke(Palette.accent,
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                            Text(dailyFraction, format: .percent.precision(.fractionLength(0)))
                                .font(.system(.title3, design: .default, weight: .semibold)).monospacedDigit()
                        }.frame(width: 72, height: 72).accessibilityElement(children: .ignore)
                            .accessibilityLabel(String(localized: "Progresso giornaliero \(Int(dailyFraction * 100)) per cento", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "La tua giornata", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                            Text(String(localized: "\(completed) di \(habits.count) obiettivi raggiunti", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).foregroundStyle(.secondary)
                            Text(String(localized: "Anche i piccoli passi contano.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.journalCard()
                    HStack {
                        Text(String(localized: "LE TUE ABITUDINI", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption.weight(.semibold)).tracking(1.6)
                        Spacer()
                        Text(String(localized: "Oggi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 14) {
                        ForEach(habits) { habit in
                            HabitCard(habit: habit, activities: activities, now: now,
                                      decrement: { subtract(habit) }, increment: { log(habit) }, confirmZero: {
                                do { try SharedStore.confirmZero(habit, in: context) }
                                catch { self.error = error.localizedDescription }
                            })
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles").font(.title3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Le abitudini incontrano la tua agenda.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline.weight(.semibold))
                            Text(String(localized: "In “Il tuo piano” trovi gli orari proposti in base ai tuoi progressi e agli spazi liberi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(18).background(Palette.soft, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(24).frame(maxWidth: 650)
        }
        .journalBackground()
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { addButton }
            ToolbarItem(placement: .topBarTrailing) { profileButton }
            #else
            ToolbarItem(placement: .navigation) { addButton }
            ToolbarItem(placement: .primaryAction) { profileButton }
            #endif
        }
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(Palette.paper, for: .navigationBar)
        #endif
        .sheet(isPresented: $adding) { AddHabitView() }
        .sheet(item: $settings) { ConnectionsView(calendar: $0.calendar) }
        .alert(String(localized: "Operazione non riuscita", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog(String(localized: "Eliminare tutti i dati dimostrativi?", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: $resetting, titleVisibility: .visible) {
            Button(String(localized: "Elimina demo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .destructive) {
                do {
                    for entry in activities where entry.source == "demo" { context.delete(entry) }
                    for habit in allHabits where habit.isDemo {
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

    private var addButton: some View {
        Button { adding = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
            .accessibilityLabel(String(localized: "Nuova abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).accessibilityIdentifier("addHabit")
    }

    private var profileButton: some View {
        Button { settings = SettingsDestination(calendar: CalendarService(scope: account.scope.key)) } label: {
            Group {
                if account.user != nil { ProfileAvatar(profile: account.profile?.value ?? AccountProfile(), size: 34) }
                else { Image(systemName: "person.crop.circle.fill").font(.system(size: 34)).foregroundStyle(Palette.accent) }
            }.frame(width: 44, height: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel(account.user == nil ? String(localized: "Accedi", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Account", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            .accessibilityIdentifier("accountSettings")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "leaf").font(.system(size: 42, weight: .light)).foregroundStyle(Palette.accent)
            Text(String(localized: "Inizia da una cosa.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.system(.title2, design: .default))
            Text(String(localized: "Scegli un’abitudine, la quantità che vuoi raggiungere e il tuo momento ideale. Al resto diamo forma insieme.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .foregroundStyle(.secondary)
            Button(String(localized: "Crea la prima abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { adding = true }.buttonStyle(.borderedProminent).controlSize(.large)
            Button(String(localized: "Esplora con dati demo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                do { try DemoData.insert(in: context); demoMode = true }
                catch { self.error = error.localizedDescription }
            }.font(.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading).journalCard()
    }

    private func log(_ habit: Habit) {
        do { try SharedStore.log(habit, in: context) }
        catch { self.error = error.localizedDescription }
    }

    private func subtract(_ habit: Habit) {
        do { try SharedStore.decrement(habit, in: context) }
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
                    ContentUnavailableView(String(localized: "Nessuna abitudine archiviata", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "archivebox",
                        description: Text(String(localized: "Le abitudini archiviate conservano tutto lo storico.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
                }
                ForEach(habits) { habit in
                    HStack {
                        NavigationLink { HabitDetailView(habit: habit) } label: { Label { Text(habit.name) } icon: { HabitMark(symbol: habit.symbol) } }
                        Spacer()
                        Button(String(localized: "Ripristina", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                            habit.archived = false
                            do { try context.save(); WidgetCenter.shared.reloadAllTimelines() }
                            catch { context.rollback(); self.error = error.localizedDescription }
                        }.buttonStyle(.bordered)
                    }
                }
            }.navigationTitle(String(localized: "Archiviate", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Fine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } } }
                .alert(String(localized: "Ripristino non riuscito", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
                } message: { Text(error ?? "") }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }
}

struct HabitCard: View {
    private let habit: Habit
    private let snapshot: HabitSnapshot
    private let symbol: String
    private let unit: String
    private let colorIndex: Int
    private let activities: [ActivitySnapshot]
    private let now: Date
    let decrement: () -> Void
    let increment: () -> Void
    let confirmZero: () -> Void
    init(habit: Habit, activities: [Activity], now: Date,
         decrement: @escaping () -> Void, increment: @escaping () -> Void, confirmZero: @escaping () -> Void = {}) {
        self.habit = habit
        snapshot = habit.snapshot
        symbol = habit.symbol; unit = habit.unit; colorIndex = habit.colorIndex
        self.activities = activities.map(\.snapshot)
        self.now = now; self.decrement = decrement; self.increment = increment
        self.confirmZero = confirmZero
    }

    private var progress: DayProgress { HabitEngine.progress(for: snapshot, on: now, activities: activities) }
    private var tint: Color { Palette.habit(colorIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button(action: decrement) {
                    Text("−\(snapshot.step.quantityText)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .frame(minWidth: 44, minHeight: 44).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).foregroundStyle(tint).disabled(!snapshot.allowsNegative && progress.quantity <= 0)
                    .opacity(snapshot.allowsNegative || progress.quantity > 0 ? 1 : 0.35)
                    .accessibilityLabel(String(localized: "Togli \(snapshot.step.quantityText) \(unit) da \(snapshot.name)", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .accessibilityIdentifier("decrement-\(snapshot.name)")
                NavigationLink { HabitDetailView(habit: habit) } label: {
                    HStack(spacing: 10) {
                        HabitMark(symbol: symbol).font(.title3).foregroundStyle(tint)
                            .frame(width: 42, height: 42).background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.name).font(.headline).foregroundStyle(Palette.ink)
                            Text(HabitText.quantity(progress.quantity, target: snapshot.target, unit: unit, goal: snapshot.goal))
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                .accessibilityIdentifier("progress-\(snapshot.name)")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain)
                Button(action: increment) {
                    Text("+\(snapshot.step.quantityText)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .frame(minWidth: 50, minHeight: 44).background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).foregroundStyle(tint)
                    .accessibilityLabel(String(localized: "Aggiungi \(snapshot.step.quantityText) \(unit) a \(snapshot.name)", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .accessibilityIdentifier("increment-\(snapshot.name)")
            }
            HabitProgressStatus(progress: progress, unit: unit).font(.caption)
            if snapshot.goal == .atMost && progress.registrations == 0 {
                Button(String(localized: "Conferma zero", bundle: AppLanguage.bundle, locale: AppLanguage.locale), action: confirmZero)
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityIdentifier("confirm-zero-\(snapshot.name)")
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.10))
                    Capsule().fill(progress.malus > 0 ? Palette.warning : tint).frame(width: max(0, geometry.size.width * progress.fraction))
                }
            }.frame(height: 4).accessibilityHidden(true)
            HStack(spacing: 5) {
                ForEach(0..<14, id: \.self) { index in
                    let date = snapshot.calendar.date(byAdding: .day, value: index - 13, to: now)!
                    let day = HabitEngine.progress(for: snapshot, on: date, activities: activities)
                    RoundedRectangle(cornerRadius: 4).fill(day.malus > 0 ? Palette.warning : tint.opacity(day.registrations > 0 ? 0.20 + day.fraction * 0.80 : 0.07))
                        .frame(maxWidth: .infinity).frame(height: 15)
                        .overlay { if day.completed { Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white) } }
                }
            }.accessibilityLabel(String(localized: "Attività degli ultimi 14 giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }.journalCard()
    }
}

private struct SettingsDestination: Identifiable {
    let id = UUID()
    let calendar: CalendarService
}
