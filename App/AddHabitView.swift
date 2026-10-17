import SwiftUI
import SwiftData
import WidgetKit

struct AddHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var unit = String(localized: "volte", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    @State private var target = 3.0
    @State private var step = 1.0
    @State private var colorIndex = 0
    @State private var symbol = "leaf"
    @State private var usesEmoji = false
    @State private var emoji = "🌱"
    @State private var hour = 18
    @State private var duration = 20
    @State private var error: String?
    private let symbols = ["leaf", "drop", "book.closed", "figure.walk", "brain.head.profile", "sun.max", "pencil", "cup.and.saucer"]
    private let emojis = ["🌱", "💧", "📚", "🚶", "🧠", "☀️", "✍️", "☕️", "🏃", "🎯", "🧘", "💤"]
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && target.isFinite && target > 0 && step.isFinite && step > 0 && !unit.trimmingCharacters(in: .whitespaces).isEmpty && (!usesEmoji || HabitAppearance.validEmoji(emoji)) }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "La tua abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                    TextField(String(localized: "Ad esempio: bere acqua", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $name).accessibilityIdentifier("habitName")
                    Picker(String(localized: "Aspetto", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $usesEmoji) {
                        Text(String(localized: "Icona", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(false)
                        Text(String(localized: "Emoji", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("appearanceKind")
                    if usesEmoji {
                        HStack {
                            Text(String(localized: "La tua emoji", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            Spacer()
                            TextField(String(localized: "Una sola emoji", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $emoji)
                                .font(.largeTitle).multilineTextAlignment(.center).frame(width: 80)
                                .accessibilityIdentifier("habitEmoji")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                            ForEach(emojis, id: \.self) { value in
                                Button { emoji = value } label: {
                                    Text(verbatim: value).font(.title2).frame(minWidth: 44, minHeight: 44)
                                        .background(emoji == value ? Palette.soft : .clear, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel(String(localized: "Scegli \(value)", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                    .accessibilityIdentifier("emoji-preset-\(value)")
                                    .accessibilityAddTraits(emoji == value ? .isSelected : [])
                            }
                        }
                        if !HabitAppearance.validEmoji(emoji) {
                            Text(String(localized: "Scegli o inserisci una sola emoji.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Picker(String(localized: "Icona", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $symbol) {
                            ForEach(symbols, id: \.self) { Image(systemName: $0).tag($0) }
                        }
                    }
                    HStack {
                        Text(String(localized: "Colore", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        Spacer()
                        ForEach(0..<4) { index in
                            Button { colorIndex = index } label: {
                                Circle().fill(Palette.habit(index)).frame(width: 32, height: 32)
                                    .overlay { if colorIndex == index { Image(systemName: "checkmark").foregroundStyle(.white) } }
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(String(localized: "Colore \(index + 1)", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .accessibilityAddTraits(index == colorIndex ? .isSelected : [])
                        }
                    }
                }
                Section {
                    TextField(String(localized: "Unità, es. bicchieri, pagine, minuti", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $unit)
                    HStack { Text(String(localized: "Obiettivo al giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale)); Spacer(); TextField(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: $target, format: .number).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text(String(localized: "Quantità per tocco", bundle: AppLanguage.bundle, locale: AppLanguage.locale)); Spacer(); TextField(String(localized: "Incremento", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: $step, format: .number).multilineTextAlignment(.trailing).frame(width: 90) }
                } header: { Text(String(localized: "Misura i tuoi passi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } footer: {
                    Text(String(localized: "Puoi registrare più volte al giorno, anche oltre l’obiettivo. Ogni tocco conserva quantità e orario.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
                Section {
                    Picker(String(localized: "Orario preferito", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $hour) {
                        ForEach(7..<22) { hour in
                            Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!, style: .time).tag(hour)
                        }
                    }
                    Stepper(String(localized: "Sessione da \(duration) minuti", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: $duration, in: 5...120, step: 5)
                } header: { Text(String(localized: "Trova il tuo momento", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } footer: {
                    Text(String(localized: "L’assistente userà queste preferenze per proporti uno spazio libero. Nessun evento viene creato automaticamente.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                }
            }
            .navigationTitle(String(localized: "Nuova abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Crea", bundle: AppLanguage.bundle, locale: AppLanguage.locale), action: save).disabled(!valid).accessibilityIdentifier("saveHabit")
                }
            }
            .alert(String(localized: "Salvataggio non riuscito", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
            } message: { Text(error ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 550)
        #endif
    }

    private func save() {
        guard valid else { return }
        context.insert(Habit(name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: usesEmoji ? "emoji:\(emoji)" : symbol,
            colorIndex: colorIndex, target: target, step: step, unit: unit.trimmingCharacters(in: .whitespaces),
            preferredHour: hour, durationMinutes: duration))
        do { try context.save(); WidgetCenter.shared.reloadAllTimelines(); dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
