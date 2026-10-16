import SwiftUI
import SwiftData
import WidgetKit

struct AddHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var unit = String(localized: "volte")
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
                Section(String(localized: "La tua abitudine")) {
                    TextField(String(localized: "Ad esempio: bere acqua"), text: $name).accessibilityIdentifier("habitName")
                    Picker(String(localized: "Aspetto"), selection: $usesEmoji) {
                        Text(String(localized: "Icona")).tag(false)
                        Text(String(localized: "Emoji")).tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("appearanceKind")
                    if usesEmoji {
                        HStack {
                            Text(String(localized: "La tua emoji"))
                            Spacer()
                            TextField(String(localized: "Una sola emoji"), text: $emoji)
                                .font(.largeTitle).multilineTextAlignment(.center).frame(width: 80)
                                .accessibilityIdentifier("habitEmoji")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                            ForEach(emojis, id: \.self) { value in
                                Button { emoji = value } label: {
                                    Text(verbatim: value).font(.title2).frame(minWidth: 44, minHeight: 44)
                                        .background(emoji == value ? Palette.soft : .clear, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel(String(localized: "Scegli \(value)"))
                                    .accessibilityIdentifier("emoji-preset-\(value)")
                                    .accessibilityAddTraits(emoji == value ? .isSelected : [])
                            }
                        }
                        if !HabitAppearance.validEmoji(emoji) {
                            Text(String(localized: "Scegli o inserisci una sola emoji.")).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Picker(String(localized: "Icona"), selection: $symbol) {
                            ForEach(symbols, id: \.self) { Image(systemName: $0).tag($0) }
                        }
                    }
                    HStack {
                        Text(String(localized: "Colore"))
                        Spacer()
                        ForEach(0..<4) { index in
                            Button { colorIndex = index } label: {
                                Circle().fill(Palette.habit(index)).frame(width: 32, height: 32)
                                    .overlay { if colorIndex == index { Image(systemName: "checkmark").foregroundStyle(.white) } }
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(String(localized: "Colore \(index + 1)"))
                                .accessibilityAddTraits(index == colorIndex ? .isSelected : [])
                        }
                    }
                }
                Section {
                    TextField(String(localized: "Unità, es. bicchieri, pagine, minuti"), text: $unit)
                    HStack { Text(String(localized: "Obiettivo al giorno")); Spacer(); TextField(String(localized: "Obiettivo"), value: $target, format: .number).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text(String(localized: "Quantità per tocco")); Spacer(); TextField(String(localized: "Incremento"), value: $step, format: .number).multilineTextAlignment(.trailing).frame(width: 90) }
                } header: { Text(String(localized: "Misura i tuoi passi")) } footer: {
                    Text(String(localized: "Puoi registrare più volte al giorno, anche oltre l’obiettivo. Ogni tocco conserva quantità e orario."))
                }
                Section {
                    Picker(String(localized: "Orario preferito"), selection: $hour) {
                        ForEach(7..<22) { hour in
                            Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!, style: .time).tag(hour)
                        }
                    }
                    Stepper(String(localized: "Sessione da \(duration) minuti"), value: $duration, in: 5...120, step: 5)
                } header: { Text(String(localized: "Trova il tuo momento")) } footer: {
                    Text(String(localized: "L’assistente userà queste preferenze per proporti uno spazio libero. Nessun evento viene creato automaticamente."))
                }
            }
            .navigationTitle(String(localized: "Nuova abitudine"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Crea"), action: save).disabled(!valid).accessibilityIdentifier("saveHabit")
                }
            }
            .alert(String(localized: "Salvataggio non riuscito"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(String(localized: "OK")) { error = nil }
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
