import SwiftUI
import SwiftData
import EventKit

struct PlannerView: View {
    let calendar: CalendarService
    @Query(filter: #Predicate<Habit> { !$0.archived }, sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var activities: [Activity]
    @State private var now = Date()
    @State private var connections = false
    @State private var reviewing: ScheduleProposal?
    @State private var error: String?
    @State private var saved = false

    private var proposals: [ScheduleProposal] {
        ScheduleEngine.propose(habits: habits.filter { !calendar.plannedHabitIDs.contains($0.id) }.map(\.snapshot), activities: activities.map(\.snapshot),
                               busy: calendar.busy, now: now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(String(localized: "IL TUO ASSISTENTE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "sparkles").font(.caption.weight(.semibold)).tracking(1.5)
                Text(String(localized: "Una giornata che\nfa spazio a te.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.system(.largeTitle, design: .default, weight: .semibold))
                Text(String(localized: "Un piano che parte dai tuoi progressi, dai tuoi orari e dagli impegni di oggi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: calendar.authorized ? "calendar.badge.checkmark" : "calendar.badge.plus").font(.title2)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(calendar.authorized ? String(localized: "Calendari del dispositivo collegati", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Facciamo spazio nella tua agenda", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                        Text(calendar.authorized ? String(localized: "\(calendar.selectedIDs.count) calendari selezionati. Le proposte evitano gli impegni occupati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Collega il calendario per trovare spazi liberi. Senza accesso, gli orari sono indicativi e potrebbero sovrapporsi ai tuoi impegni.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(calendar.authorized ? String(localized: "Gestisci calendari", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Collega calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { connections = true }
                            .font(.subheadline.weight(.semibold))
                    }
                }.journalCard()
                HStack {
                    Text(String(localized: "PROPOSTE PER OGGI", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption.weight(.semibold)).tracking(1.5)
                    Spacer()
                    Button { calendar.refresh(); now = Date() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel(String(localized: "Aggiorna proposte", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                if !calendar.plannedHabitIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Già nel tuo calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                        ForEach(calendar.events.filter { $0.url?.scheme == "makeet" && $0.url?.host == "plan" }, id: \.calendarItemIdentifier) { event in
                            HStack {
                                Text(event.startDate, style: .time).monospacedDigit()
                                Text(event.title ?? String(localized: "Abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                Spacer()
                                Image(systemName: "calendar.badge.checkmark")
                            }.font(.subheadline)
                        }
                        Text(String(localized: "Le abitudini già pianificate oggi non ricevono un secondo blocco. Registra i progressi in Oggi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            .font(.caption).foregroundStyle(.secondary)
                    }.journalCard()
                }
                if habits.isEmpty {
                    Text(String(localized: "Aggiungi la tua prima abitudine in Oggi. Poi le cerchiamo un posto nella giornata.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .foregroundStyle(.secondary).journalCard()
                } else if proposals.isEmpty {
                    ContentUnavailableView(String(localized: "Per oggi ci siamo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "moon.stars",
                        description: Text(String(localized: "Hai raggiunto gli obiettivi oppure non resta uno spazio sufficiente tra le 7 e le 22. Puoi comunque registrare attività in Oggi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
                }
                ForEach(proposals) { proposal in
                    if let habit = habits.first(where: { $0.id == proposal.habitID }) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(proposal.start, style: .time).font(.system(.title2, design: .default, weight: .semibold)).monospacedDigit()
                                    Text(String(localized: "\(habit.durationMinutes) min", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                                }.frame(minWidth: 65, alignment: .leading)
                                Rectangle().fill(Palette.habit(habit.colorIndex)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label { Text(habit.name) } icon: { HabitMark(symbol: habit.symbol) }.font(.headline)
                                    Text(reason(proposal)).font(.caption).foregroundStyle(.secondary)
                                    let progress = HabitEngine.progress(for: habit.snapshot, on: now, activities: activities.map(\.snapshot))
                                    Text(String(localized: "Ti mancano \(max(0, habit.target - progress.quantity).quantityText) \(habit.unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.fixedSize(horizontal: false, vertical: true)
                            Button(String(localized: "Rivedi e aggiungi al calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { reviewing = proposal }
                                .buttonStyle(.bordered).disabled(!calendar.authorized)
                        }.journalCard()
                    }
                }
                Text(String(localized: "Le proposte sono calcolate sul dispositivo. Dopo almeno 5 registrazioni precedenti a oggi, l’assistente considera l’ora in cui registri più spesso negli ultimi 28 giorni. Un blocco in agenda non completa un’abitudine.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 650)
        }.journalBackground().navigationTitle(String(localized: "Il tuo piano", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { Button { connections = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel(String(localized: "Connessioni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        .sheet(isPresented: $connections) { ConnectionsView(calendar: calendar) }
        .sheet(item: $reviewing) { proposal in
            if let habit = habits.first(where: { $0.id == proposal.habitID }) {
                PlanReviewView(proposal: proposal, habit: habit, calendar: calendar) {
                    reviewing = nil; saved = true; now = Date()
                }
            }
        }
        .onChange(of: calendar.revision) { _, _ in now = Date() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)); now = Date() } catch { break }
            }
        }
        .alert(String(localized: "Aggiunto al calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: $saved) { Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .cancel) {} }
    }

    private func reason(_ proposal: ScheduleProposal) -> String {
        let availability = calendar.authorized ? String(localized: "Spazio libero nei calendari selezionati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Orario indicativo: calendario non collegato.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        switch proposal.reason {
        case .preferredHour: return String(localized: "Vicino al tuo orario preferito. \(availability)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .historicalHour(let samples): return String(localized: "Basato sull’ora più frequente in \(samples) registrazioni. \(availability)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
}

struct PlanReviewView: View {
    let proposal: ScheduleProposal
    let habit: Habit
    let calendar: CalendarService
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Il tuo spazio", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                    Label { Text(habit.name) } icon: { HabitMark(symbol: habit.symbol) }
                    LabeledContent(String(localized: "Inizio", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: proposal.start.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.locale)))
                    LabeledContent(String(localized: "Fine evento", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: proposal.end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale)))
                    LabeledContent(String(localized: "Calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: calendar.calendars.first(where: { $0.calendarIdentifier == calendar.destinationID })?.title ?? String(localized: "Da selezionare", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                Section {
                    Text(String(localized: "Creeremo soltanto questo evento. I progressi dell’abitudine cambiano quando registri un’attività.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    Button(String(localized: "Conferma e crea evento", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        guard !isSaving else { return }
                        isSaving = true
                        do { try calendar.save(proposal, habit: habit); onSave() }
                        catch { self.error = error.localizedDescription; isSaving = false }
                    }.disabled(isSaving)
                }
            }.navigationTitle(String(localized: "Conferma il piano", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } } }
                .alert(String(localized: "Evento non creato", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
                } message: { Text(error ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }
}

struct ConnectionsView: View {
    @Environment(AccountManager.self) private var account
    let calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                AccountSettingsSection()
                LanguageSettingsSection()
                NotificationSettingsSection()
                Section {
                    LabeledContent(String(localized: "Calendari di sistema", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: calendar.authorized ? String(localized: "Collegati", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Non collegati", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    if !calendar.authorized {
                        Button(String(localized: "Consenti accesso al calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await calendar.connect() } }
                    }
                    if let message = calendar.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: { Text(String(localized: "Apple Calendar e calendari del dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } footer: {
                    Text(String(localized: "EventKit legge i calendari configurati sul dispositivo, inclusi quelli Google già aggiunti nelle impostazioni di sistema. La sincronizzazione di questi account è gestita dal sistema.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                if calendar.authorized {
                    Section(String(localized: "Considera gli impegni di", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                            Toggle(isOn: Binding(get: { calendar.selectedIDs.contains(item.calendarIdentifier) }, set: { _ in calendar.toggle(item) })) {
                                VStack(alignment: .leading) { Text(item.title); Text(item.source.title).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Section(String(localized: "Crea i blocchi in", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        Picker(String(localized: "Calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: Binding(get: { calendar.destinationID ?? "" }, set: { calendar.chooseDestination($0) })) {
                            Text(String(localized: "Scegli un calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag("")
                            ForEach(calendar.calendars.filter(\.allowsContentModifications), id: \.calendarIdentifier) { item in
                                Text(String(localized: "\(item.title) · \(item.source.title)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(item.calendarIdentifier)
                            }
                        }
                    }
                }
                Section {
                    LabeledContent(String(localized: "Dati su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: account.user == nil ? String(localized: "Archivio locale", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Archivio dell’account", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    LabeledContent(String(localized: "Google diretto", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: String(localized: "Da integrare", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    Text(String(localized: "La sincronizzazione Makeet usa il tuo account. I calendari del dispositivo restano gestiti dal sistema.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text(String(localized: "Sincronizzazione", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
            }.navigationTitle(String(localized: "Connessioni", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .task { await account.start() }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Fine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}
