import SwiftUI
import SwiftData
import Charts
import WidgetKit

struct TrendsView: View {
    @Query(sort: \Habit.createdAt) private var allHabits: [Habit]
    @Query private var activities: [Activity]
    @State private var now = Date()
    private var habits: [Habit] { allHabits.filter { !$0.archived } }
    var body: some View {
        let snapshots = activities.map(\.snapshot)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "Ultimi 3 mesi e mese corrente", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chart.xyaxis.line").foregroundStyle(Palette.accent)
                }
                if habits.contains(where: \.isDemo) {
                    Label(String(localized: "Dati dimostrativi", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "flask").font(.caption).foregroundStyle(.secondary)
                }
                if habits.isEmpty {
                    ContentUnavailableView(String(localized: "I tuoi progressi iniziano qui", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "chart.bar.xaxis",
                        description: Text(String(localized: "Crea un’abitudine in Oggi per iniziare a misurarla.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
                }
                ForEach(habits) { habit in
                    NavigationLink { HabitDetailView(habit: habit) } label: {
                        HabitHistoryRow(habit: habit, activities: snapshots, now: now)
                    }.buttonStyle(.plain).accessibilityIdentifier("history-\(habit.name)")
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.ink.opacity(0.15)).frame(width: 9, height: 9)
                    Text(String(localized: "Nessuna registrazione", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    Spacer(minLength: 12)
                    Text(String(localized: "Poco", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    ForEach(1..<5) { level in
                        RoundedRectangle(cornerRadius: 2).fill(Palette.accent.opacity(Double(level) / 4)).frame(width: 9, height: 9)
                    }
                    Text(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }.font(.caption2).foregroundStyle(.secondary).accessibilityElement(children: .combine)
            }.padding(16).frame(maxWidth: 650)
        }.journalBackground().navigationTitle(String(localized: "Andamento", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            while !Task.isCancelled {
                now = Date()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }
}

struct HabitHistoryRow: View {
    private let habit: HabitSnapshot
    private let symbol: String
    private let unit: String
    private let tint: Color
    private let months: [HistoryMonth]
    private let statistics: HabitStatistics
    private let progressByDay: [Date: DayProgress]

    init(habit: Habit, activities: [ActivitySnapshot], now: Date) {
        self.habit = habit.snapshot
        symbol = habit.symbol; unit = habit.unit; tint = Palette.habit(habit.colorIndex)
        let calendar = habit.snapshot.calendar
        let current = calendar.dateInterval(of: .month, for: now)!.start
        let first = calendar.date(byAdding: .month, value: -3, to: current)!
        months = (0..<4).map { offset in
            let start = calendar.date(byAdding: .month, value: offset, to: first)!
            let count = calendar.range(of: .day, in: .month, for: start)!.count
            return HistoryMonth(start: start, dates: (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! })
        }
        let window = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: now)).day! + 1
        let stats = HabitEngine.statistics(for: habit.snapshot, activities: activities, now: now, window: window)
        statistics = stats
        progressByDay = Dictionary(uniqueKeysWithValues: stats.days.map { ($0.date, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HabitMark(symbol: symbol).foregroundStyle(tint)
                Text(habit.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                Text(statistics.total.quantityText + " " + unit).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }.frame(minHeight: 24)
            ForEach(months) { month in
                HStack(spacing: 6) {
                    Text(month.start.formatted(.dateTime.month(.abbreviated).locale(AppLanguage.locale)))
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                    HStack(spacing: 2) {
                        ForEach(0..<31, id: \.self) { index in
                            if index < month.dates.count {
                                let date = month.dates[index]
                                let day = progressByDay[date]
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(day.map { $0.malus > 0 ? Palette.warning : tint.opacity($0.registrations > 0 ? 0.2 + $0.fraction * 0.8 : 0.04) } ?? .clear)
                                    .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(tint.opacity(0.15), lineWidth: 0.5) }
                                    .frame(maxWidth: .infinity).frame(height: 9)
                            } else { Color.clear.frame(maxWidth: .infinity).frame(height: 9) }
                        }
                    }.accessibilityHidden(true)
                }.accessibilityElement(children: .ignore)
                    .accessibilityLabel(month.start.formatted(.dateTime.month(.wide).year().locale(AppLanguage.locale)))
                    .accessibilityValue(monthSummary(month))
                    .accessibilityIdentifier("history-month-\(habit.name)-\(habit.calendar.component(.month, from: month.start))")
            }
            HStack {
                Text(String(localized: "Obiettivo raggiunto: \(statistics.completionRate.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale)))", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                Spacer()
                Text(String(localized: "Serie: \(statistics.currentStreak) g", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            }.font(.caption2).foregroundStyle(.secondary)
        }.journalCard(padding: 10)
    }

    private func monthSummary(_ month: HistoryMonth) -> String {
        let days = month.dates.compactMap { progressByDay[$0] }
        guard days.contains(where: { $0.registrations > 0 }) else {
            return String(localized: "Nessuna registrazione", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
        return QuantityTotal.sum(days.map(\.quantity)).quantityText + " " + unit + "; " +
            String(localized: "\(days.filter(\.completed).count) di \(days.filter(\.scheduled).count) obiettivi raggiunti", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
}

private struct HistoryMonth: Identifiable {
    var id: Date { start }
    let start: Date
    let dates: [Date]
}

struct HabitDetailView: View {
    let habit: Habit
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Activity.timestamp, order: .reverse) private var activities: [Activity]
    @Environment(AccountManager.self) private var account
    private struct Deletion: Identifiable {
        let id: UUID
        let name: String
        let calendar: CalendarService
    }
    @State private var deletion: Deletion?
    @State private var deletedName: String?
    @State private var deletionCalendar: CalendarService?
    @State private var cleanupID: UUID?
    @State private var cleanupError: String?
    @State private var window = 28
    @State private var error: String?
    @State private var archiving = false
    @State private var editing = false
    private var todayEntries: [Activity] {
        activities.filter { $0.habitID == habit.id && habit.snapshot.calendar.isDateInToday($0.timestamp) }
    }
    private var tint: Color { Palette.habit(habit.colorIndex) }

    var body: some View {
        Group {
            if let deletedName {
                VStack(alignment: .leading, spacing: 20) {
                    Label(String(localized: "Abitudine eliminata", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "checkmark.circle").font(.title2.weight(.semibold))
                    Text(deletedName).font(.headline)
                    if let cleanupError {
                        Text(cleanupError).foregroundStyle(.secondary)
                        Button(String(localized: "Riprova a rimuovere i blocchi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { cleanCalendar() }
                    }
                    Button(String(localized: "Torna alle abitudini", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() }.buttonStyle(.borderedProminent)
                }.padding(24).frame(maxWidth: 650, alignment: .leading).journalBackground()
            } else { detail }
        }
        .sheet(item: $deletion) { destination in
            HabitDeletionReview(name: destination.name, calendar: destination.calendar) { removeBlocks in
                delete(destination, removeBlocks: removeBlocks)
            }
        }
        .sheet(isPresented: $editing) { AddHabitView(habit: habit) }
    }

    @ViewBuilder private var detail: some View {
        let snapshot = habit.snapshot
        let snapshots = activities.map(\.snapshot)
        let stats = HabitEngine.statistics(for: snapshot, activities: snapshots, window: window)
        let continuity = window == 84 ? stats : HabitEngine.statistics(for: snapshot, activities: snapshots, window: 84)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if habit.archived {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(String(localized: "Abitudine archiviata", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "archivebox").font(.headline)
                        Text(String(localized: "Lo storico è conservato. Puoi ripristinarla dall’archivio nelle impostazioni.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(String(localized: "Torna alle abitudini", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() }
                    }.journalCard()
                }
                HStack(spacing: 12) {
                    HabitMark(symbol: habit.symbol).font(.largeTitle).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name).font(.system(.largeTitle, design: .default))
                        Text(habit.goal == .atMost ? String(localized: "Limite: \(habit.target.quantityText) \(habit.unit) al giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Obiettivo: \(habit.target.quantityText) \(habit.unit) al giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Picker(String(localized: "Periodo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $window) {
                    Text(String(localized: "7 giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(7); Text(String(localized: "28 giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(28); Text(String(localized: "12 settimane", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(84)
                }.pickerStyle(.segmented).accessibilityIdentifier("statisticsPeriod")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    metric(stats.total.quantityText, label: String(localized: "\(habit.unit) totali", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    metric(stats.average.quantityText, label: String(localized: "media al giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    metric(stats.completionRate.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale)), label: String(localized: "giorni a obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    metric("\(stats.currentStreak)", label: String(localized: "giorni di serie attuale", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Quanto, giorno per giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                    Chart {
                        ForEach(stats.days) { day in
                            BarMark(x: .value(String(localized: "Giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale), day.date, unit: .day), y: .value(habit.unit, day.quantity))
                                .foregroundStyle(day.malus > 0 ? Palette.warning : tint).cornerRadius(3)
                        }
                        RuleMark(y: .value(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), habit.target)).foregroundStyle(tint.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .annotation(position: .top, alignment: .trailing) { Text(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption2) }
                    }.chartXAxis { AxisMarks(values: .stride(by: .day, count: window <= 7 ? 1 : 7)) { value in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    } }.frame(height: 180)
                    Text(String(localized: "\(stats.completedDays) giorni a obiettivo su \(stats.scheduledDays) osservati. I giorni precedenti alla creazione sono esclusi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "I giorni di riposo non interrompono le serie e non contano come obiettivi mancati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                }.journalCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "La tua continuità", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                    let days = continuity.days
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 14), spacing: 5) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 4).fill(day.malus > 0 ? Palette.warning : tint.opacity(day.registrations > 0 ? 0.2 + day.fraction * 0.8 : 0.07))
                                .aspectRatio(1, contentMode: .fit)
                                .accessibilityLabel(String(localized: "\(day.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.locale))): \(day.quantity.quantityText) \(habit.unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        }
                    }
                    HStack { Text(String(localized: "Ultimi \(days.count) giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)); Spacer(); Text(String(localized: "Poco", bundle: AppLanguage.bundle, locale: AppLanguage.locale)); ForEach(1..<5) { index in
                        RoundedRectangle(cornerRadius: 2).fill(tint.opacity(Double(index) / 4)).frame(width: 10, height: 10)
                    }; Text(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }.font(.caption2).foregroundStyle(.secondary)
                    Text(String(localized: "Serie migliore: \(stats.longestStreak) giorni · \(stats.activeDays) giorni attivi nel periodo selezionato", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary)
                }.journalCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Quando trovi il tuo ritmo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                    Chart(0..<24, id: \.self) { hour in
                        let count = stats.hourlyRegistrations[hour]
                        BarMark(x: .value(String(localized: "Ora", bundle: AppLanguage.bundle, locale: AppLanguage.locale), hour), y: .value(String(localized: "Registrazioni", bundle: AppLanguage.bundle, locale: AppLanguage.locale), count)).foregroundStyle(tint)
                    }.frame(height: 130)
                    Text(String(localized: "Registrazioni per ora, nel fuso \(habit.timeZoneID). Descrivono quando registri: non dimostrano quale orario funzioni meglio.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary)
                }.journalCard()
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text(String(localized: "Registrazioni di oggi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline); Spacer(); Text("\(todayEntries.count)").foregroundStyle(.secondary) }
                    if todayEntries.isEmpty { Text(String(localized: "C’è spazio per il primo passo.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(todayEntries) { entry in
                        HStack {
                            Text(entry.timestamp, style: .time).monospacedDigit()
                            Spacer()
                            Text(verbatim: "\(entry.amount > 0 ? "+" : "")\(entry.amount.quantityText) \(habit.unit)")
                            Button { remove(entry) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel(String(localized: "Annulla registrazione delle \(entry.timestamp.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale)))", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        }.font(.subheadline)
                    }
                    HStack {
                        Button(String(localized: "Togli \(habit.step.quantityText) \(habit.unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                            do { try SharedStore.decrement(habit, in: context) } catch { self.error = error.localizedDescription }
                        }.buttonStyle(.bordered).disabled(habit.archived || (!habit.allowsNegative && todayEntries.reduce(0, { $0 + $1.amount }) <= 0))
                        Spacer()
                        Button(String(localized: "Aggiungi \(habit.step.quantityText) \(habit.unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        do { try SharedStore.log(habit, in: context) } catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).disabled(habit.archived)
                    }.controlSize(.large)
                }.journalCard()
            }.padding(16).frame(maxWidth: 650)
        }.journalBackground().navigationTitle(String(localized: "Dettaglio", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !habit.archived {
                Button { editing = true } label: { Image(systemName: "pencil") }.accessibilityLabel(String(localized: "Modifica abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .accessibilityIdentifier("editHabit")
                Button { archiving = true } label: { Image(systemName: "archivebox") }.accessibilityLabel(String(localized: "Archivia abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            }
            Button(role: .destructive) {
                deletion = Deletion(id: habit.id, name: habit.name, calendar: CalendarService(scope: account.scope.key))
            } label: { Image(systemName: "trash") }
                .accessibilityLabel(String(localized: "Elimina definitivamente", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).accessibilityIdentifier("deleteHabit")

        }
        .confirmationDialog(String(localized: "Archiviare questa abitudine? Lo storico verrà conservato.", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: $archiving, titleVisibility: .visible) {
            Button(String(localized: "Archivia", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                habit.archived = true
                do { try context.save(); WidgetCenter.shared.reloadAllTimelines() }
                catch { context.rollback(); self.error = error.localizedDescription }
            }
        }
        .alert(String(localized: "Operazione non riuscita", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func delete(_ destination: Deletion, removeBlocks: Bool) {
        deletedName = destination.name
        do {
            try SharedStore.deleteHabit(destination.id, in: context)
            deletion = nil
            if removeBlocks {
                deletionCalendar = destination.calendar; cleanupID = destination.id; cleanCalendar()
            }
        } catch { deletedName = nil; deletion = nil; self.error = error.localizedDescription }
    }

    private func cleanCalendar() {
        guard let cleanupID, let deletionCalendar else { return }
        do { try deletionCalendar.removeFutureBlocks(for: cleanupID); self.cleanupID = nil; cleanupError = nil }
        catch { cleanupError = error.localizedDescription }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(.title, design: .default, weight: .medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).journalCard()
    }

    private func remove(_ entry: Activity) {
        context.delete(entry)
        do { try context.save(); WidgetCenter.shared.reloadAllTimelines() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
