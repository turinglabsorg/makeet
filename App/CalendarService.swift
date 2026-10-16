import EventKit
import Foundation
import Observation

@MainActor @Observable final class CalendarService {
    private let store = EKEventStore()
    var calendars: [EKCalendar] = []
    var events: [EKEvent] = []
    var selectedIDs: Set<String> = []
    var destinationID: String?
    var authorized = false
    var message: String?
    var revision = 0
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        refresh()
    }

    func connect() async {
        do {
            authorized = try await store.requestFullAccessToEvents()
            message = authorized ? nil : "Accesso al calendario non concesso. Puoi abilitarlo nelle Impostazioni."
            refresh()
        } catch { message = error.localizedDescription }
    }

    func refresh() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard authorized else { calendars = []; events = []; revision += 1; return }
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
        let saved = UserDefaults.standard.stringArray(forKey: "calendarSources")
        selectedIDs = Set(saved ?? calendars.map(\.calendarIdentifier))
        destinationID = UserDefaults.standard.string(forKey: "calendarDestination")
            ?? store.defaultCalendarForNewEvents?.calendarIdentifier
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let selected = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        if selected.isEmpty { events = [] }
        else { events = store.events(matching: store.predicateForEvents(withStart: start, end: end,
                                                                       calendars: selected)).sorted { $0.startDate < $1.startDate } }
        revision += 1
    }

    func toggle(_ calendar: EKCalendar) {
        if selectedIDs.contains(calendar.calendarIdentifier) { selectedIDs.remove(calendar.calendarIdentifier) }
        else { selectedIDs.insert(calendar.calendarIdentifier) }
        UserDefaults.standard.set(Array(selectedIDs), forKey: "calendarSources")
        refresh()
    }

    func chooseDestination(_ id: String) {
        UserDefaults.standard.set(id, forKey: "calendarDestination")
        destinationID = id
    }

    var busy: [BusyInterval] {
        events.filter { $0.availability != .free && $0.status != .canceled }
            .map { BusyInterval(start: $0.startDate, end: $0.endDate) }
    }

    var plannedHabitIDs: Set<UUID> {
        Set(events.compactMap { event in
            guard let url = event.url, url.scheme == "avvi", url.host == "plan" else { return nil }
            return UUID(uuidString: String(url.lastPathComponent.prefix(36)))
        })
    }

    func save(_ proposal: ScheduleProposal, habit: Habit) throws {
        refresh()
        guard authorized, let destinationID,
              let calendar = calendars.first(where: { $0.calendarIdentifier == destinationID }),
              calendar.allowsContentModifications else { throw CalendarFailure.noDestination }
        guard proposal.start > Date() else { throw CalendarFailure.expired }
        let marker = URL(string: "avvi://plan/\(proposal.id)")!
        let predicate = store.predicateForEvents(withStart: proposal.start, end: proposal.end,
                                                 calendars: [calendar])
        if store.events(matching: predicate).contains(where: { $0.url == marker }) { return }
        guard !busy.contains(where: { proposal.start < $0.end && proposal.end > $0.start }) else {
            throw CalendarFailure.conflict
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = habit.name
        event.startDate = proposal.start; event.endDate = proposal.end
        event.url = marker
        event.notes = "Blocco pianificato dall’app. Il completamento dell’abitudine si registra separatamente."
        try store.save(event, span: .thisEvent)
        refresh()
    }
}

enum CalendarFailure: LocalizedError {
    case noDestination, conflict, expired
    var errorDescription: String? {
        switch self {
        case .noDestination: "Scegli un calendario scrivibile nelle connessioni."
        case .conflict: "Il calendario è cambiato: questo spazio è occupato. Aggiorna le proposte."
        case .expired: "Questo orario è già passato. Aggiorna le proposte."
        }
    }
}
