import SwiftUI

struct HabitDeletionReview: View {
    let name: String
    let calendar: CalendarService
    let confirm: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var removeBlocks = true
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(name).font(.headline)
                    Text(String(localized: "Elimineremo definitivamente l’abitudine e tutte le sue registrazioni. Questa operazione non si può annullare.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                Section {
                    if calendar.authorized {
                        Toggle(String(localized: "Rimuovi anche i blocchi futuri di Makeet", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isOn: $removeBlocks)
                            .accessibilityIdentifier("deleteHabitCalendarBlocks")
                        Text(String(localized: "Rimuove solo gli eventi futuri collegati a questa abitudine nei calendari modificabili. Gli altri eventi restano al loro posto.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "Il calendario non è collegato: gli eventuali eventi già creati restano nel calendario.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(String(localized: "Elimina abitudine e progressi", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .destructive) { confirm(calendar.authorized && removeBlocks) }
                        .accessibilityIdentifier("confirmDeleteHabit")
                }
            }.navigationTitle(String(localized: "Elimina definitivamente", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
        #endif
    }
}
