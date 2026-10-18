import SwiftUI
import SwiftData
import EventKit

struct CalendarOverview: View {
    let calendar: CalendarService
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var activities: [Activity]
    @State private var month = Date()
    @State private var selected = Date()
    @State private var editingDay = false
    @State private var editingHabit: Habit?
    @State private var connections = false
    private var display: Calendar { var value = Calendar(identifier: .gregorian); value.firstWeekday = 2; value.locale = AppLanguage.locale; return value }
    private var range: DateInterval { display.dateInterval(of: .month, for: month)! }
    private var dates: [Date] { HabitEngine.days(from: range.start, through: range.end.addingTimeInterval(-1), calendar: display) }
    private var active: [Habit] { habits.filter { !$0.archived } }

    var body: some View {
        let snapshots = activities.map(\.snapshot)
        let days = HabitEngine.calendarDays(habits: habits.map(\.snapshot), activities: snapshots, dates: dates, displayCalendar: display, excludedGoals: Set(habits.filter(\.archived).map(\.id)))
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    monthButton(-1, symbol: "chevron.left", label: String(localized: "Mese precedente", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year().locale(AppLanguage.locale))).font(.title2.weight(.semibold))
                        .accessibilityIdentifier("calendarMonth")
                    Spacer()
                    monthButton(1, symbol: "chevron.right", label: String(localized: "Mese successivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                VStack(spacing: 8) {
                    HStack {
                        ForEach(0..<7) { index in
                            Text(display.veryShortStandaloneWeekdaySymbols[(index + 1) % 7]).font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity).foregroundStyle(.secondary)
                        }
                    }.accessibilityHidden(true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach(0..<((display.component(.weekday, from: range.start) + 5) % 7), id: \.self) { _ in Color.clear.frame(height: 52) }
                        ForEach(days) { day in
                            let chosen = display.isDate(day.date, inSameDayAs: selected)
                            let future = day.date > display.startOfDay(for: Date())
                            Button { selected = day.date } label: {
                                VStack(spacing: 3) {
                                    Text(day.date, format: .dateTime.day().locale(AppLanguage.locale)).font(.subheadline.weight(chosen ? .bold : .medium))
                                    if future { Image(systemName: calendar.events(on: day.date).contains(where: { $0.makeetHabitID != nil }) ? "calendar.badge.checkmark" : "minus").font(.system(size: 9)) }
                                    else { Text("\(day.completedGoals)/\(day.scheduledGoals)").font(.system(size: 9)).monospacedDigit() }
                                }.frame(maxWidth: .infinity, minHeight: 52)
                                    .foregroundStyle(day.fraction >= 0.65 ? .white : Palette.ink)
                                    .background(Palette.accent.opacity(day.fraction > 0 ? 0.2 + 0.8 * day.fraction : (day.hasActivity ? 0.2 : 0.05)), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(chosen ? Palette.ink : .clear, lineWidth: 2) }
                            }.buttonStyle(.plain).accessibilityIdentifier("calendar-day-\(display.component(.day, from: day.date))")
                                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(AppLanguage.locale)))
                                .accessibilityValue(String(localized: "\(day.completedGoals) di \(day.scheduledGoals) obiettivi raggiunti", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    Text(String(localized: "Più colore, più progressi. Tocca un giorno per vedere abitudini ed eventi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                HStack(alignment: .top) {
                    Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))).font(.headline)
                    Spacer()
                    Button(String(localized: "Modifica progressi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { editingDay = true }
                        .font(.subheadline.weight(.semibold)).accessibilityIdentifier("editCalendarDay")
                        .disabled(display.startOfDay(for: selected) > display.startOfDay(for: Date()) || active.isEmpty)
                }
                VStack(spacing: 16) {
                    ForEach(habits) { habit in
                        let snapshot = habit.snapshot
                        let date = snapshot.date(forCalendarDay: selected, displayedIn: display)
                        let progress = HabitEngine.progress(for: snapshot, on: date, activities: snapshots)
                        HStack(spacing: 12) {
                            HabitMark(symbol: habit.symbol).foregroundStyle(Palette.habit(habit.colorIndex)).frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                NavigationLink { HabitDetailView(habit: habit) } label: { Text(habit.name).font(.subheadline.weight(.semibold)) }.buttonStyle(.plain)
                                Text("\(progress.quantity.quantityText) / \(habit.target.quantityText) \(habit.unit)").font(.caption).monospacedDigit()
                                    .accessibilityIdentifier("calendar-progress-\(habit.name)")
                                if !progress.scheduled { Text(String(localized: "Non in programma", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if !habit.archived {
                                Button { editingHabit = habit } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                                    .buttonStyle(.plain).accessibilityLabel(String(localized: "Modifica abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                    .accessibilityIdentifier("edit-habit-\(habit.name)")
                            }
                        }
                    }
                    if habits.isEmpty { Text(String(localized: "Crea la prima abitudine nell’app.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).foregroundStyle(.secondary) }
                }.journalCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Eventi del giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                    if !calendar.authorized {
                        Button(String(localized: "Collega calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { connections = true }
                        Text(String(localized: "Gli eventi Apple e Google configurati sul dispositivo restano aggiornati tramite Calendario.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                    } else if calendar.events(on: selected).isEmpty {
                        Text(String(localized: "Nessun evento nei calendari selezionati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(calendar.events(on: selected), id: \.occurrenceID) { event in
                        CalendarEventRow(event: event)
                    }
                }.journalCard()
            }.padding(.vertical, 24).padding(.horizontal, 16).frame(maxWidth: 650)
        }.journalBackground().navigationTitle(String(localized: "Calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button(String(localized: "Oggi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { month = Date(); selected = display.startOfDay(for: Date()) }
            Button { connections = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel(String(localized: "Connessioni", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
        .task(id: month) { calendar.show(range) }
        .refreshable { calendar.refresh() }
        .sheet(isPresented: $editingDay) { CalendarDayEditor(date: selected, habits: active, activities: snapshots, display: display) }
        .sheet(item: $editingHabit) { AddHabitView(habit: $0) }
        .sheet(isPresented: $connections) { ConnectionsView(calendar: calendar) }
    }

    private func monthButton(_ offset: Int, symbol: String, label: String) -> some View {
        Button {
            month = display.date(byAdding: .month, value: offset, to: range.start)!
            selected = month
        } label: { Image(systemName: symbol).frame(width: 44, height: 44) }
            .accessibilityLabel(label).accessibilityIdentifier(offset < 0 ? "previousMonth" : "nextMonth")
    }
}

struct CalendarEventRow: View {
    let event: EKEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.makeetHabitID == nil ? "calendar" : "leaf").foregroundStyle(Palette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? String(localized: "Abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline.weight(.medium))
                if event.isAllDay { Text(String(localized: "Tutto il giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption) }
                else { Text(event.startDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.locale)) + " – " + event.endDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.locale))).font(.caption).monospacedDigit() }
                Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DayDraft: Identifiable {
    let id: UUID
    let date: Date
    let name: String
    let symbol: String
    let color: Int
    let step: Double
    let unit: String
    let original: Double
    var quantity: Double
}

struct CalendarDayEditor: View {
    let date: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [DayDraft]
    @State private var error: String?
    init(date: Date, habits: [Habit], activities: [ActivitySnapshot], display: Calendar) {
        self.date = date
        _drafts = State(initialValue: habits.compactMap { habit in
            let snapshot = habit.snapshot
            let mapped = snapshot.date(forCalendarDay: date, displayedIn: display)
            guard snapshot.calendar.startOfDay(for: mapped) >= snapshot.calendar.startOfDay(for: snapshot.createdAt) else { return nil }
            let quantity = HabitEngine.progress(for: snapshot, on: mapped, activities: activities).quantity
            return DayDraft(id: habit.id, date: mapped, name: habit.name, symbol: habit.symbol, color: habit.colorIndex, step: habit.step, unit: habit.unit, original: quantity, quantity: quantity)
        })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(AppLanguage.locale))).font(.title2.weight(.semibold))
                    Text(String(localized: "Correggi le quantità e salva. Le nuove registrazioni nei giorni passati sono indicate come correzioni manuali alle 12:00, nel fuso dell’abitudine.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                    ForEach($drafts) { $draft in
                        HStack(spacing: 12) {
                            Button { draft.quantity = max(0, draft.quantity - draft.step) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                                .buttonStyle(.bordered).disabled(draft.quantity <= 0).accessibilityIdentifier("day-decrement-\(draft.name)")
                            VStack(alignment: .leading, spacing: 6) {
                                Label { Text(draft.name) } icon: { HabitMark(symbol: draft.symbol) }.font(.headline)
                                Text("\(draft.quantity.quantityText) \(draft.unit)").font(.subheadline).monospacedDigit().accessibilityIdentifier("day-quantity-\(draft.name)")
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button { draft.quantity += draft.step } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                                .buttonStyle(.bordered).disabled(!(draft.quantity + draft.step).isFinite).accessibilityIdentifier("day-increment-\(draft.name)")
                        }.tint(Palette.habit(draft.color)).journalCard()
                    }
                    if drafts.isEmpty {
                        Text(String(localized: "Nessuna abitudine era ancora iniziata. Puoi cambiare la data di inizio modificando l’abitudine.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 24).padding(.horizontal, 16).frame(maxWidth: 650)
            }.journalBackground().navigationTitle(String(localized: "Modifica progressi", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Salva", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                            do {
                                try SharedStore.correct(drafts.filter { $0.quantity != $0.original }.map {
                                    HabitDayCorrection(habitID: $0.id, date: $0.date, quantity: $0.quantity, expectedQuantity: $0.original)
                                }, in: context)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("saveCalendarDay")
                    }
                }
                .alert(String(localized: "Salvataggio non riuscito", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
                } message: { Text(error ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 550)
        #endif
    }
}
