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
                Text("Ogni passo lascia\nun segno.").font(.system(.largeTitle, design: .default, weight: .semibold))
                Text("Guarda oltre la serie di giorni. Conta anche quanto fai, con quale frequenza e quando.").foregroundStyle(.secondary)
                if habits.isEmpty {
                    ContentUnavailableView("I tuoi progressi iniziano qui", systemImage: "chart.bar.xaxis",
                        description: Text("Crea un’abitudine in Oggi per iniziare a misurarla."))
                }
                ForEach(habits) { habit in
                    let stats = HabitEngine.statistics(for: habit.snapshot, activities: activities.map(\.snapshot))
                    NavigationLink { HabitDetailView(habit: habit) } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label(habit.name, systemImage: habit.symbol).font(.headline)
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(stats.total.quantityText).font(.system(.largeTitle, design: .default, weight: .medium))
                                Text("\(habit.unit) · \(stats.days.count) giorni").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Chart(stats.days) { day in
                                BarMark(x: .value("Giorno", day.date, unit: .day), y: .value("Quantità", day.quantity))
                                    .foregroundStyle(Palette.habit(habit.colorIndex)).cornerRadius(2)
                            }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 70)
                            HStack {
                                Text("Obiettivo raggiunto: \(stats.completionRate.formatted(.percent.precision(.fractionLength(0))))")
                                Spacer()
                                Text("Serie: \(stats.currentStreak) g")
                            }.font(.caption).foregroundStyle(.secondary)
                        }.journalCard()
                    }.buttonStyle(.plain)
                }
            }.padding(24).frame(maxWidth: 650)
        }.journalBackground().navigationTitle("Andamento")
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
                        Label("Abitudine archiviata", systemImage: "archivebox").font(.headline)
                        Text("Lo storico è conservato. Puoi ripristinarla dall’archivio in Oggi.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Torna alle abitudini") { dismiss() }
                    }.journalCard()
                }
                HStack(spacing: 12) {
                    Image(systemName: habit.symbol).font(.largeTitle).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name).font(.system(.largeTitle, design: .default))
                        Text("Obiettivo: \(habit.target.quantityText) \(habit.unit) al giorno").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Picker("Periodo", selection: $window) {
                    Text("7 giorni").tag(7); Text("28 giorni").tag(28); Text("12 settimane").tag(84)
                }.pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    metric(stats.total.quantityText, label: "\(habit.unit) totali")
                    metric(stats.average.quantityText, label: "media al giorno")
                    metric(stats.completionRate.formatted(.percent.precision(.fractionLength(0))), label: "giorni a obiettivo")
                    metric("\(stats.currentStreak)", label: "giorni di serie attuale")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quanto, giorno per giorno").font(.headline)
                    Chart {
                        ForEach(stats.days) { day in
                            BarMark(x: .value("Giorno", day.date, unit: .day), y: .value(habit.unit, day.quantity))
                                .foregroundStyle(tint).cornerRadius(3)
                        }
                        RuleMark(y: .value("Obiettivo", habit.target)).foregroundStyle(tint.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .annotation(position: .top, alignment: .trailing) { Text("Obiettivo").font(.caption2) }
                    }.chartXAxis { AxisMarks(values: .stride(by: .day, count: window <= 7 ? 1 : 7)) { value in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    } }.frame(height: 180)
                    Text("\(stats.completedDays) giorni a obiettivo su \(stats.days.count) osservati. I giorni precedenti alla creazione sono esclusi.")
                        .font(.caption).foregroundStyle(.secondary)
                }.journalCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text("La tua continuità").font(.headline)
                    let days = HabitEngine.statistics(for: habit.snapshot, activities: snapshots, window: 84).days
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 14), spacing: 5) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 4).fill(tint.opacity(day.quantity > 0 ? 0.2 + day.fraction * 0.8 : 0.07))
                                .aspectRatio(1, contentMode: .fit)
                                .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.quantity.quantityText) \(habit.unit)")
                        }
                    }
                    HStack { Text("Ultimi \(days.count) giorni"); Spacer(); Text("Poco"); ForEach(1..<5) { index in
                        RoundedRectangle(cornerRadius: 2).fill(tint.opacity(Double(index) / 4)).frame(width: 10, height: 10)
                    }; Text("Obiettivo") }.font(.caption2).foregroundStyle(.secondary)
                    Text("Serie migliore: \(stats.longestStreak) giorni · \(stats.activeDays) giorni attivi nel periodo selezionato")
                        .font(.caption).foregroundStyle(.secondary)
                }.journalCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quando trovi il tuo ritmo").font(.headline)
                    Chart(0..<24, id: \.self) { hour in
                        let count = activities.filter { $0.habitID == habit.id && $0.timestamp >= (stats.days.first?.date ?? Date()) && habit.snapshot.calendar.component(.hour, from: $0.timestamp) == hour }.count
                        BarMark(x: .value("Ora", hour), y: .value("Registrazioni", count)).foregroundStyle(tint)
                    }.frame(height: 130)
                    Text("Registrazioni per ora, nel fuso \(habit.timeZoneID). Descrivono quando registri: non dimostrano quale orario funzioni meglio.")
                        .font(.caption).foregroundStyle(.secondary)
                }.journalCard()
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Registrazioni di oggi").font(.headline); Spacer(); Text("\(todayEntries.count)").foregroundStyle(.secondary) }
                    if todayEntries.isEmpty { Text("C’è spazio per il primo passo.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(todayEntries) { entry in
                        HStack {
                            Text(entry.timestamp, style: .time).monospacedDigit()
                            Spacer()
                            Text("+\(entry.amount.quantityText) \(habit.unit)")
                            Button { remove(entry) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel("Annulla registrazione delle \(entry.timestamp.formatted(date: .omitted, time: .shortened))")
                        }.font(.subheadline)
                    }
                    Button("Aggiungi \(habit.step.quantityText) \(habit.unit)") {
                        do { try SharedStore.log(habit, in: context) } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(habit.archived)
                }.journalCard()
            }.padding(24).frame(maxWidth: 650)
        }.journalBackground().navigationTitle("Dettaglio")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !habit.archived {
                Button { archiving = true } label: { Image(systemName: "archivebox") }.accessibilityLabel("Archivia abitudine")
            }
        }
        .confirmationDialog("Archiviare questa abitudine? Lo storico verrà conservato.", isPresented: $archiving, titleVisibility: .visible) {
            Button("Archivia") {
                habit.archived = true
                do { try context.save(); WidgetCenter.shared.reloadAllTimelines() }
                catch { context.rollback(); self.error = error.localizedDescription }
            }
        }
        .alert("Operazione non riuscita", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
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
