import SwiftUI
import SwiftData
import Charts
import WidgetKit

struct TrendsView: View {
    @Query(sort: \Habit.createdAt) private var allHabits: [Habit]
    @Query private var activities: [Activity]
    private var habits: [Habit] { allHabits.filter { !$0.archived } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(String(localized: "Ogni passo lascia\nun segno.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.system(.largeTitle, design: .default, weight: .semibold))
                Text(String(localized: "Guarda oltre la serie di giorni. Conta anche quanto fai, con quale frequenza e quando.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).foregroundStyle(.secondary)
                if habits.isEmpty {
                    ContentUnavailableView(String(localized: "I tuoi progressi iniziano qui", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "chart.bar.xaxis",
                        description: Text(String(localized: "Crea un’abitudine in Oggi per iniziare a misurarla.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
                }
                ForEach(habits) { habit in
                    let stats = HabitEngine.statistics(for: habit.snapshot, activities: activities.map(\.snapshot))
                    NavigationLink { HabitDetailView(habit: habit) } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label { Text(habit.name) } icon: { HabitMark(symbol: habit.symbol) }.font(.headline)
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(stats.total.quantityText).font(.system(.largeTitle, design: .default, weight: .medium))
                                Text(String(localized: "\(habit.unit) · \(stats.days.count) giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Chart(stats.days) { day in
                                BarMark(x: .value(String(localized: "Giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale), day.date, unit: .day), y: .value(String(localized: "Quantità", bundle: AppLanguage.bundle, locale: AppLanguage.locale), day.quantity))
                                    .foregroundStyle(Palette.habit(habit.colorIndex)).cornerRadius(2)
                            }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 70)
                            HStack {
                                Text(String(localized: "Obiettivo raggiunto: \(stats.completionRate.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale)))", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                Spacer()
                                Text(String(localized: "Serie: \(stats.currentStreak) g", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            }.font(.caption).foregroundStyle(.secondary)
                        }.journalCard()
                    }.buttonStyle(.plain)
                }
            }.padding(24).frame(maxWidth: 650)
        }.journalBackground().navigationTitle(String(localized: "Andamento", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct HabitDetailView: View {
    let habit: Habit
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Activity.timestamp, order: .reverse) private var activities: [Activity]
    @State private var window = 28
    @State private var error: String?
    @State private var archiving = false
    private var snapshots: [ActivitySnapshot] { activities.map(\.snapshot) }
    private var stats: HabitStatistics { HabitEngine.statistics(for: habit.snapshot, activities: snapshots, window: window) }
    private var todayEntries: [Activity] {
        activities.filter { $0.habitID == habit.id && habit.snapshot.calendar.isDateInToday($0.timestamp) }
    }
    private var tint: Color { Palette.habit(habit.colorIndex) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if habit.archived {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(String(localized: "Abitudine archiviata", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "archivebox").font(.headline)
                        Text(String(localized: "Lo storico è conservato. Puoi ripristinarla dall’archivio in Oggi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(String(localized: "Torna alle abitudini", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() }
                    }.journalCard()
                }
                HStack(spacing: 12) {
                    HabitMark(symbol: habit.symbol).font(.largeTitle).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name).font(.system(.largeTitle, design: .default))
                        Text(String(localized: "Obiettivo: \(habit.target.quantityText) \(habit.unit) al giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Picker(String(localized: "Periodo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $window) {
                    Text(String(localized: "7 giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(7); Text(String(localized: "28 giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(28); Text(String(localized: "12 settimane", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(84)
                }.pickerStyle(.segmented)
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
                                .foregroundStyle(tint).cornerRadius(3)
                        }
                        RuleMark(y: .value(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), habit.target)).foregroundStyle(tint.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .annotation(position: .top, alignment: .trailing) { Text(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption2) }
                    }.chartXAxis { AxisMarks(values: .stride(by: .day, count: window <= 7 ? 1 : 7)) { value in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    } }.frame(height: 180)
                    Text(String(localized: "\(stats.completedDays) giorni a obiettivo su \(stats.days.count) osservati. I giorni precedenti alla creazione sono esclusi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary)
                }.journalCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "La tua continuità", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                    let days = HabitEngine.statistics(for: habit.snapshot, activities: snapshots, window: 84).days
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 14), spacing: 5) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 4).fill(tint.opacity(day.quantity > 0 ? 0.2 + day.fraction * 0.8 : 0.07))
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
                        let count = activities.filter { $0.habitID == habit.id && $0.timestamp >= (stats.days.first?.date ?? Date()) && habit.snapshot.calendar.component(.hour, from: $0.timestamp) == hour }.count
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
                            Text(String(localized: "+\(entry.amount.quantityText) \(habit.unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            Button { remove(entry) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel(String(localized: "Annulla registrazione delle \(entry.timestamp.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale)))", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        }.font(.subheadline)
                    }
                    HStack {
                        Button(String(localized: "Togli \(habit.step.quantityText) \(habit.unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                            do { try SharedStore.decrement(habit, in: context) } catch { self.error = error.localizedDescription }
                        }.buttonStyle(.bordered).disabled(habit.archived || todayEntries.isEmpty)
                        Spacer()
                        Button(String(localized: "Aggiungi \(habit.step.quantityText) \(habit.unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        do { try SharedStore.log(habit, in: context) } catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).disabled(habit.archived)
                    }.controlSize(.large)
                }.journalCard()
            }.padding(24).frame(maxWidth: 650)
        }.journalBackground().navigationTitle(String(localized: "Dettaglio", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !habit.archived {
                Button { archiving = true } label: { Image(systemName: "archivebox") }.accessibilityLabel(String(localized: "Archivia abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            }
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
