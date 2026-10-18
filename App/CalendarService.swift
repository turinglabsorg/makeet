import EventKit
import Foundation
import Observation

private final class CalendarObservation {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

extension EKEvent {
    var occurrenceID: String { calendarItemIdentifier + "-" + String(startDate.timeIntervalSince1970) }
    var makeetHabitID: UUID? {
        guard let url, url.scheme == "makeet", url.host == "plan" else { return nil }
        return UUID(uuidString: String(url.lastPathComponent.prefix(36)))
    }
}

@MainActor @Observable final class CalendarService {
    private let store = EKEventStore()
    var calendars: [EKCalendar] = []
    var events: [EKEvent] = []
    var selectedIDs: Set<String> = []
    var destinationID: String?
    var authorized = false
    var message: String?
    var revision = 0
    private var observer: CalendarObservation?
    private let preferencePrefix: String
    private var visibleRange: DateInterval?

    init(scope: String = "local") {
        preferencePrefix = scope == "local" ? "" : scope + "."
        observer = CalendarObservation(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        refresh()
    }

    func connect() async {
        do {
            authorized = try await store.requestFullAccessToEvents()
            message = authorized ? nil : String(localized: "Accesso al calendario non concesso. Puoi abilitarlo nelle Impostazioni.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            refresh()
        } catch { message = error.localizedDescription }
    }

    func show(_ range: DateInterval) {
        guard range != visibleRange else { return }
        visibleRange = range; refresh()
    }

    func refresh() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard authorized else { calendars = []; events = []; revision += 1; return }
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
        let saved = UserDefaults.standard.stringArray(forKey: preferencePrefix + "calendarSources")
        selectedIDs = Set(saved ?? (preferencePrefix.isEmpty ? calendars.map(\.calendarIdentifier) : []))
        destinationID = UserDefaults.standard.string(forKey: preferencePrefix + "calendarDestination")
            ?? (preferencePrefix.isEmpty ? store.defaultCalendarForNewEvents?.calendarIdentifier : nil)
        let start = Calendar.current.startOfDay(for: Date())
        let future = DateInterval(start: start, end: Calendar.current.date(byAdding: .day, value: 28, to: start)!)
        let ranges = visibleRange.map { [$0, future] } ?? [future]
        var unique: [String: EKEvent] = [:]
        for range in ranges {
            for event in loadEvents(in: range) { unique[event.occurrenceID] = event }
        }
        events = unique.values.sorted { $0.startDate == $1.startDate ? $0.occurrenceID < $1.occurrenceID : $0.startDate < $1.startDate }
        revision += 1
    }

    private func loadEvents(in range: DateInterval) -> [EKEvent] {
        let sources = calendars.filter { selectedIDs.contains($0.calendarIdentifier) || $0.calendarIdentifier == destinationID }
        guard !sources.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: range.start, end: range.end, calendars: sources))
            .filter { $0.status != .canceled }
    }

    func events(on day: Date) -> [EKEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.startDate < end && $0.endDate > start }
    }

    func toggle(_ calendar: EKCalendar) {
        if selectedIDs.contains(calendar.calendarIdentifier) { selectedIDs.remove(calendar.calendarIdentifier) }
        else { selectedIDs.insert(calendar.calendarIdentifier) }
        UserDefaults.standard.set(Array(selectedIDs), forKey: preferencePrefix + "calendarSources")
        refresh()
    }

    func selectAll() {
        UserDefaults.standard.set(calendars.map(\.calendarIdentifier), forKey: preferencePrefix + "calendarSources")
        refresh()
    }

    func chooseDestination(_ id: String) {
        UserDefaults.standard.set(id, forKey: preferencePrefix + "calendarDestination")
        destinationID = id; refresh()
    }

    var hasAvailability: Bool { authorized && calendars.contains { selectedIDs.contains($0.calendarIdentifier) || $0.calendarIdentifier == destinationID } }
    var canWrite: Bool { authorized && calendars.contains { $0.calendarIdentifier == destinationID && $0.allowsContentModifications } }

    var busy: [BusyInterval] {
        events.filter { $0.availability != .free && $0.status != .canceled }
            .map { BusyInterval(start: $0.startDate, end: $0.endDate) }
    }

    var plannedHabitIDs: Set<UUID> { Set(events.compactMap(\.makeetHabitID)) }
    var plannedOccurrences: [PlannedOccurrence] {
        events.compactMap { event in event.makeetHabitID.map { PlannedOccurrence(habitID: $0, start: event.startDate) } }
    }

    func removeFutureBlocks(for habitID: UUID) throws {
        refresh()
        guard authorized else { throw CalendarFailure.noDestination }
        let start = Date()
        let end = Calendar.current.date(byAdding: .year, value: 4, to: start)!
        let matches = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.makeetHabitID == habitID && $0.startDate > start && $0.calendar.allowsContentModifications }
        do {
            for event in matches { try store.remove(event, span: .thisEvent, commit: false) }
            if !matches.isEmpty { try store.commit() }
        } catch { store.reset(); refresh(); throw error }
        refresh()
    }

    func save(_ proposal: ScheduleProposal, habit: Habit) throws {
        try save([proposal], habits: [habit])
    }

    func save(_ proposals: [ScheduleProposal], habits: [Habit]) throws {
        guard !proposals.isEmpty else { return }
        refresh()
        guard authorized, let destinationID,
              let destination = calendars.first(where: { $0.calendarIdentifier == destinationID }),
              destination.allowsContentModifications else { throw CalendarFailure.noDestination }
        let starts = proposals.compactMap { proposal in habits.first(where: { $0.id == proposal.habitID })?.snapshot.calendar.startOfDay(for: proposal.start) }
        let ends = proposals.compactMap { proposal -> Date? in
            guard let habit = habits.first(where: { $0.id == proposal.habitID }) else { return nil }
            return habit.snapshot.calendar.date(byAdding: .day, value: 1, to: habit.snapshot.calendar.startOfDay(for: proposal.start))
        }
        guard let first = starts.min(), let last = ends.max() else { throw CalendarFailure.changed }
        let range = DateInterval(start: first, end: last)
        let current = loadEvents(in: range)
        var occupied = current.filter { $0.availability != .free }.map { BusyInterval(start: $0.startDate, end: $0.endDate) }
        var staged: [EKEvent] = []
        var planned = current.compactMap { event in event.makeetHabitID.map { PlannedOccurrence(habitID: $0, start: event.startDate) } }
        for proposal in proposals {
            guard let habit = habits.first(where: { $0.id == proposal.habitID }), !habit.archived,
                  habit.snapshot.isScheduled(on: proposal.start), proposal.end > proposal.start else { throw CalendarFailure.changed }
            guard proposal.start > Date() else { throw CalendarFailure.expired }
            if planned.contains(where: { $0.habitID == habit.id && habit.snapshot.calendar.isDate($0.start, inSameDayAs: proposal.start) }) { continue }
            guard !occupied.contains(where: { proposal.start < $0.end && proposal.end > $0.start }) else { throw CalendarFailure.conflict }
            let event = EKEvent(eventStore: store)
            event.calendar = destination; event.title = habit.name
            event.startDate = proposal.start; event.endDate = proposal.end
            event.url = URL(string: "makeet://plan/\(proposal.id)")!
            event.notes = String(localized: "Blocco pianificato dall’app. Il completamento dell’abitudine si registra separatamente.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            staged.append(event); occupied.append(BusyInterval(start: proposal.start, end: proposal.end))
            planned.append(PlannedOccurrence(habitID: habit.id, start: proposal.start))
        }
        guard !staged.isEmpty else { return }
        do {
            for event in staged { try store.save(event, span: .thisEvent, commit: false) }
            try store.commit()
        } catch { store.reset(); refresh(); throw error }
        refresh()
    }
}

enum CalendarFailure: LocalizedError {
    case noDestination, conflict, expired, changed
    var errorDescription: String? {
        switch self {
        case .noDestination: String(localized: "Scegli un calendario scrivibile nelle connessioni.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .conflict: String(localized: "Il calendario è cambiato: questo spazio è occupato. Aggiorna le proposte.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .expired: String(localized: "Questo orario è già passato. Aggiorna le proposte.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .changed: String(localized: "L’abitudine è cambiata. Aggiorna il piano prima di confermare.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
}
