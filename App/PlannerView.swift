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
    @State private var horizon = 14
    @State private var batch: PlanBatch?

    private var proposals: [ScheduleProposal] {
        ScheduleEngine.propose(habits: habits.map(\.snapshot), activities: activities.map(\.snapshot),
                               busy: calendar.busy, now: now, days: horizon, planned: calendar.plannedOccurrences)
    }

    var body: some View {
        let proposed = proposals
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(String(localized: "IL TUO ASSISTENTE", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "sparkles").font(.caption.weight(.semibold)).tracking(1.5)
                Text(String(localized: "Una giornata che\nfa spazio a te.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.system(.largeTitle, design: .default, weight: .semibold))
                Text(String(localized: "Un piano che parte dai tuoi progressi, dai giorni scelti e dagli impegni in calendario.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).foregroundStyle(.secondary)
                if !calendar.authorized {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "calendar.badge.plus").font(.title2)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Facciamo spazio nella tua agenda", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                            Text(String(localized: "Collega il calendario per trovare spazi liberi. Senza accesso, gli orari sono indicativi e potrebbero sovrapporsi ai tuoi impegni.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button(String(localized: "Collega calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { connections = true }
                                .font(.subheadline.weight(.semibold))
                        }
                    }.journalCard()
                } else if !calendar.hasAvailability || !calendar.canWrite {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Scegli i calendari da considerare e un calendario modificabile in cui aggiungere i blocchi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline)
                        Button(String(localized: "Scegli un calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { connections = true }
                            .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("choosePlanningCalendars")
                    }.journalCard()
                }
                Picker(String(localized: "Periodo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $horizon) {
                    Text(String(localized: "Oggi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(1)
                    Text(String(localized: "7 giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(7)
                    Text(String(localized: "2 settimane", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(14)
                    Text(String(localized: "4 settimane", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(28)
                }.pickerStyle(.segmented).accessibilityIdentifier("planningHorizon")
                if !proposed.isEmpty {
                    Button(String(localized: "Rivedi e aggiungi tutto", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { batch = PlanBatch(proposals: proposed) }
                        .buttonStyle(.borderedProminent).disabled(!calendar.authorized).accessibilityIdentifier("reviewFuturePlan")
                }
                HStack {
                    Text(horizon == 1 ? String(localized: "Cosa hai da fare oggi", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Cosa hai da fare nei prossimi giorni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption.weight(.semibold)).tracking(1.5)
                    Spacer()
                    Button { calendar.refresh(); now = Date() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel(String(localized: "Aggiorna proposte", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                if !calendar.plannedHabitIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Già nel tuo calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                        ForEach(calendar.events.filter { $0.url?.scheme == "makeet" && $0.url?.host == "plan" }, id: \.occurrenceID) { event in
                            HStack {
                                Text(event.startDate.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(AppLanguage.locale))).monospacedDigit()
                                Text(event.title ?? String(localized: "Abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                Spacer()
                                Image(systemName: "calendar.badge.checkmark")
                            }.font(.subheadline)
                        }
                        Text(String(localized: "Ogni abitudine riceve al massimo un blocco per giorno programmato. Gli eventi futuri già presenti vengono mantenuti.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            .font(.caption).foregroundStyle(.secondary)
                    }.journalCard()
                }
                if habits.isEmpty {
                    Text(String(localized: "Aggiungi la tua prima abitudine in Oggi. Poi le cerchiamo un posto nella giornata.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .foregroundStyle(.secondary).journalCard()
                } else if proposed.isEmpty {
                    ContentUnavailableView(String(localized: "Il piano è completo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "moon.stars",
                        description: Text(String(localized: "Tutti i giorni scelti sono già pianificati, completati o senza spazi liberi tra le 7 e le 22. Puoi cambiare periodo o preferenze.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
                }
                ForEach(proposed) { proposal in
                    if let habit = habits.first(where: { $0.id == proposal.habitID }) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(proposal.start.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.locale))).font(.caption).foregroundStyle(.secondary)
                                    Text(proposal.start, style: .time).font(.system(.title2, design: .default, weight: .semibold)).monospacedDigit()
                                    Text(String(localized: "\(habit.durationMinutes) min", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                                }.frame(minWidth: 65, alignment: .leading)
                                Rectangle().fill(Palette.habit(habit.colorIndex)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label { Text(habit.name) } icon: { HabitMark(symbol: habit.symbol) }.font(.headline)
                                    Text(reason(proposal)).font(.caption).foregroundStyle(.secondary)
                                    let progress = HabitEngine.progress(for: habit.snapshot, on: proposal.start, activities: activities.map(\.snapshot))
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
        .sheet(item: $batch) { value in
            PlanBatchReview(batch: value, habits: habits, calendar: calendar) { batch = nil; saved = true; now = Date() }
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
        let availability = calendar.hasAvailability ? String(localized: "Spazio libero nei calendari selezionati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : (calendar.authorized ? String(localized: "Orario indicativo: scegli i calendari da considerare.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Orario indicativo: calendario non collegato.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        switch proposal.reason {
        case .preferredHour: return String(localized: "Vicino al tuo orario preferito. \(availability)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .historicalHour(let samples): return String(localized: "Basato sull’ora più frequente in \(samples) registrazioni. \(availability)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
}

struct PlanReviewView: View {
    @Environment(AccountManager.self) private var account
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
                        guard !isSaving, account.canPlan else { return }
                        isSaving = true
                        do { try calendar.save(proposal, habit: habit); onSave() }
                        catch { self.error = error.localizedDescription; isSaving = false }
                    }.disabled(isSaving || !account.canPlan || !calendar.canWrite)
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
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var exportDocument: ArchiveExport?
    @State private var exporting = false
    @State private var exportName = "Makeet-export"
    @State private var exportError: String?
    @Environment(AccountManager.self) private var account
    let calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile = false
    @State private var showingPlus = false
    @State private var deletingAccount = false
    @State private var importingArchive = false
    var body: some View {
        NavigationStack {
            Form {
                AccountSettingsSection(deleting: $deletingAccount, importing: $importingArchive, editingProfile: $editingProfile)
                LanguageSettingsSection()
                Section {
                    Button { showingPlus = true } label: { Label("Makeet Plus", systemImage: "sparkles") }.accessibilityIdentifier("showMakeetPlus")
                }
                Section {
                    Button(String(localized: "Esporta i tuoi dati", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        Task {
                            do {
                                exportDocument = ArchiveExport(data: try await account.exportData(in: context))
                                exportName = "Makeet-export-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                                exporting = true
                            }
                            catch { exportError = String(localized: "Esportazione non riuscita. Riprova quando il servizio è raggiungibile.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
                        }
                    }.accessibilityIdentifier("exportData")
                }
                NotificationSettingsSection()
                Section {
                    NavigationLink { ArchivedHabitsView() } label: {
                        Label(String(localized: "Abitudini archiviate", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "archivebox")
                    }.accessibilityIdentifier("archivedHabits")
                }
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
                        Button(String(localized: "Seleziona tutti i calendari", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { calendar.selectAll() }
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
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: exportName) { result in
            if case .failure = result { exportError = String(localized: "Esportazione non riuscita. Riprova quando il servizio è raggiungibile.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        }
        .alert(String(localized: "Operazione non riuscita", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { exportError = nil }
        } message: { Text(exportError ?? "") }
        .sheet(isPresented: $showingPlus) { PlusView() }
        .sheet(isPresented: $editingProfile) {
            if let profile = account.profile { ProfileEditorView(service: profile) }
        }
        .confirmationDialog(String(localized: "Eliminare l’account Makeet?", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: $deletingAccount, titleVisibility: .visible) {
            Button(String(localized: "Gestisci abbonamento", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                openURL(URL(string: "https://apps.apple.com/account/subscriptions/")!)
            }
            Button(String(localized: "Elimina account e dati", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .destructive) { Task { await account.deleteAccount() } }
            Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .cancel) {}
        } message: { Text(String(localized: "Elimineremo definitivamente l’account e i dati dal servizio. L’eliminazione non annulla l’abbonamento: Apple continuerà gli addebiti. Se hai Makeet Plus, annullalo prima di procedere. Puoi comunque eliminare subito l’account.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        .confirmationDialog(String(localized: "Importare in questo account?", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: $importingArchive, titleVisibility: .visible) {
            Button(String(localized: "Conferma importazione", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await account.importLocalArchive() } }
            Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .cancel) {}
        } message: { Text(String(localized: "Copia soltanto i progressi locali non dimostrativi nell’account attuale. L’archivio originale resta sul dispositivo.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}

struct PlanBatch: Identifiable {
    let id = UUID()
    let proposals: [ScheduleProposal]
}

struct PlanBatchReview: View {
    @Environment(AccountManager.self) private var account
    let batch: PlanBatch
    let habits: [Habit]
    let calendar: CalendarService
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String(localized: "\(batch.proposals.count) eventi nel calendario selezionato. Controlla il piano: i progressi delle abitudini restano separati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    LabeledContent(String(localized: "Calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: calendar.calendars.first { $0.calendarIdentifier == calendar.destinationID }?.title ?? String(localized: "Da selezionare", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                Section {
                    ForEach(batch.proposals) { proposal in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(habits.first { $0.id == proposal.habitID }?.name ?? "").font(.headline)
                            Text(proposal.start.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(AppLanguage.locale))).font(.subheadline)
                        }.padding(.vertical, 4)
                    }
                }
            }.navigationTitle(String(localized: "Conferma il piano", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .safeAreaInset(edge: .bottom) {
                    Button(String(localized: "Conferma e crea eventi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        guard !saving, account.canPlan else { return }
                        saving = true
                        do { try calendar.save(batch.proposals, habits: habits); onSave() }
                        catch { self.error = error.localizedDescription; saving = false }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(saving || !account.canPlan || !calendar.canWrite)
                        .padding().frame(maxWidth: .infinity).background(Palette.paper).accessibilityIdentifier("confirmFuturePlan")
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } } }
                .alert(String(localized: "Evento non creato", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
                } message: { Text(error ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}
