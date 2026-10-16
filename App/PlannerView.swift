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
                Label("IL TUO ASSISTENTE", systemImage: "sparkles").font(.caption.weight(.semibold)).tracking(1.5)
                Text("Una giornata che\nfa spazio a te.").font(.system(.largeTitle, design: .default, weight: .semibold))
                Text("Un piano che parte dai tuoi progressi, dai tuoi orari e dagli impegni di oggi.").foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: calendar.authorized ? "calendar.badge.checkmark" : "calendar.badge.plus").font(.title2)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(calendar.authorized ? "Calendari del dispositivo collegati" : "Facciamo spazio nella tua agenda").font(.headline)
                        Text(calendar.authorized ? "\(calendar.selectedIDs.count) calendari selezionati. Le proposte evitano gli impegni occupati." : "Collega il calendario per trovare spazi liberi. Senza accesso, gli orari sono indicativi e potrebbero sovrapporsi ai tuoi impegni.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(calendar.authorized ? "Gestisci calendari" : "Collega calendario") { connections = true }
                            .font(.subheadline.weight(.semibold))
                    }
                }.journalCard()
                HStack {
                    Text("PROPOSTE PER OGGI").font(.caption.weight(.semibold)).tracking(1.5)
                    Spacer()
                    Button { calendar.refresh(); now = Date() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel("Aggiorna proposte")
                }
                if !calendar.plannedHabitIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Già nel tuo calendario").font(.headline)
                        ForEach(calendar.events.filter { $0.url?.scheme == "makeet" && $0.url?.host == "plan" }, id: \.calendarItemIdentifier) { event in
                            HStack {
                                Text(event.startDate, style: .time).monospacedDigit()
                                Text(event.title ?? "Abitudine")
                                Spacer()
                                Image(systemName: "calendar.badge.checkmark")
                            }.font(.subheadline)
                        }
                        Text("Le abitudini già pianificate oggi non ricevono un secondo blocco. Registra i progressi in Oggi.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.journalCard()
                }
                if habits.isEmpty {
                    Text("Aggiungi la tua prima abitudine in Oggi. Poi le cerchiamo un posto nella giornata.")
                        .foregroundStyle(.secondary).journalCard()
                } else if proposals.isEmpty {
                    ContentUnavailableView("Per oggi ci siamo", systemImage: "moon.stars",
                        description: Text("Hai raggiunto gli obiettivi oppure non resta uno spazio sufficiente tra le 7 e le 22. Puoi comunque registrare attività in Oggi."))
                }
                ForEach(proposals) { proposal in
                    if let habit = habits.first(where: { $0.id == proposal.habitID }) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(proposal.start, style: .time).font(.system(.title2, design: .default, weight: .semibold)).monospacedDigit()
                                    Text("\(habit.durationMinutes) min").font(.caption).foregroundStyle(.secondary)
                                }.frame(minWidth: 65, alignment: .leading)
                                Rectangle().fill(Palette.habit(habit.colorIndex)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(habit.name, systemImage: habit.symbol).font(.headline)
                                    Text(reason(proposal)).font(.caption).foregroundStyle(.secondary)
                                    let progress = HabitEngine.progress(for: habit.snapshot, on: now, activities: activities.map(\.snapshot))
                                    Text("Ti mancano \(max(0, habit.target - progress.quantity).quantityText) \(habit.unit)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.fixedSize(horizontal: false, vertical: true)
                            Button("Rivedi e aggiungi al calendario") { reviewing = proposal }
                                .buttonStyle(.bordered).disabled(!calendar.authorized)
                        }.journalCard()
                    }
                }
                Text("Le proposte sono calcolate sul dispositivo. Dopo almeno 5 registrazioni precedenti a oggi, l’assistente considera l’ora in cui registri più spesso negli ultimi 28 giorni. Un blocco in agenda non completa un’abitudine.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 650)
        }.journalBackground().navigationTitle("Il tuo piano")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { Button { connections = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Connessioni") }
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
        .alert("Aggiunto al calendario", isPresented: $saved) { Button("OK", role: .cancel) {} }
    }

    private func reason(_ proposal: ScheduleProposal) -> String {
        let availability = calendar.authorized ? "Spazio libero nei calendari selezionati." : "Orario indicativo: calendario non collegato."
        switch proposal.reason {
        case .preferredHour: return "Vicino al tuo orario preferito. \(availability)"
        case .historicalHour(let samples): return "Basato sull’ora più frequente in \(samples) registrazioni. \(availability)"
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
                Section("Il tuo spazio") {
                    Label(habit.name, systemImage: habit.symbol)
                    LabeledContent("Inizio", value: proposal.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Fine", value: proposal.end.formatted(date: .omitted, time: .shortened))
                    LabeledContent("Calendario", value: calendar.calendars.first(where: { $0.calendarIdentifier == calendar.destinationID })?.title ?? "Da selezionare")
                }
                Section {
                    Text("Creeremo soltanto questo evento. I progressi dell’abitudine cambiano quando registri un’attività.")
                    Button("Conferma e crea evento") {
                        guard !isSaving else { return }
                        isSaving = true
                        do { try calendar.save(proposal, habit: habit); onSave() }
                        catch { self.error = error.localizedDescription; isSaving = false }
                    }.disabled(isSaving)
                }
            }.navigationTitle("Conferma il piano")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
                .alert("Evento non creato", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }
}

struct ConnectionsView: View {
    let calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                NotificationSettingsSection()
                Section {
                    LabeledContent("Calendari di sistema", value: calendar.authorized ? "Collegati" : "Non collegati")
                    if !calendar.authorized {
                        Button("Consenti accesso al calendario") { Task { await calendar.connect() } }
                    }
                    if let message = calendar.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Apple Calendar e calendari del dispositivo") } footer: {
                    Text("EventKit legge i calendari configurati sul dispositivo, inclusi quelli Google già aggiunti nelle impostazioni di sistema. La sincronizzazione di questi account è gestita dal sistema.")
                }
                if calendar.authorized {
                    Section("Considera gli impegni di") {
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                            Toggle(isOn: Binding(get: { calendar.selectedIDs.contains(item.calendarIdentifier) }, set: { _ in calendar.toggle(item) })) {
                                VStack(alignment: .leading) { Text(item.title); Text(item.source.title).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Section("Crea i blocchi in") {
                        Picker("Calendario", selection: Binding(get: { calendar.destinationID ?? "" }, set: { calendar.chooseDestination($0) })) {
                            Text("Scegli un calendario").tag("")
                            ForEach(calendar.calendars.filter(\.allowsContentModifications), id: \.calendarIdentifier) { item in
                                Text("\(item.title) · \(item.source.title)").tag(item.calendarIdentifier)
                            }
                        }
                    }
                }
                Section {
                    LabeledContent("Dati su questo dispositivo", value: "Archivio locale")
                    LabeledContent("iCloud tra dispositivi", value: SharedStore.cloudEnabled ? "Configurato · da verificare" : "Da attivare")
                    LabeledContent("Google diretto", value: "Da integrare")
                    Text("I tuoi progressi sono salvati su questo dispositivo. Il collegamento iCloud e l’accesso diretto a Google saranno disponibili in una prossima versione.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Sincronizzazione") }
            }.navigationTitle("Connessioni")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}
