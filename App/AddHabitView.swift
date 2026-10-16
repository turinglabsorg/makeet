import SwiftUI
import SwiftData
import WidgetKit

struct AddHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var unit = "volte"
    @State private var target = 3.0
    @State private var step = 1.0
    @State private var colorIndex = 0
    @State private var symbol = "leaf"
    @State private var hour = 18
    @State private var duration = 20
    @State private var error: String?
    private let symbols = ["leaf", "drop", "book.closed", "figure.walk", "brain.head.profile", "sun.max", "pencil", "cup.and.saucer"]
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && target.isFinite && target > 0 && step.isFinite && step > 0 && !unit.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("La tua abitudine") {
                    TextField("Ad esempio: bere acqua", text: $name).accessibilityIdentifier("habitName")
                    Picker("Icona", selection: $symbol) {
                        ForEach(symbols, id: \.self) { Image(systemName: $0).tag($0) }
                    }
                    HStack {
                        Text("Colore")
                        Spacer()
                        ForEach(0..<4) { index in
                            Button { colorIndex = index } label: {
                                Circle().fill(Palette.habit(index)).frame(width: 32, height: 32)
                                    .overlay { if colorIndex == index { Image(systemName: "checkmark").foregroundStyle(.white) } }
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Colore \(index + 1)")
                                .accessibilityAddTraits(index == colorIndex ? .isSelected : [])
                        }
                    }
                }
                Section {
                    TextField("Unità, es. bicchieri, pagine, minuti", text: $unit)
                    HStack { Text("Obiettivo al giorno"); Spacer(); TextField("Obiettivo", value: $target, format: .number).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text("Quantità per tocco"); Spacer(); TextField("Incremento", value: $step, format: .number).multilineTextAlignment(.trailing).frame(width: 90) }
                } header: { Text("Misura i tuoi passi") } footer: {
                    Text("Puoi registrare più volte al giorno, anche oltre l’obiettivo. Ogni tocco conserva quantità e orario.")
                }
                Section {
                    Picker("Orario preferito", selection: $hour) {
                        ForEach(7..<22) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Stepper("Sessione da \(duration) minuti", value: $duration, in: 5...120, step: 5)
                } header: { Text("Trova il tuo momento") } footer: {
                    Text("L’assistente userà queste preferenze per proporti uno spazio libero. Nessun evento viene creato automaticamente.")
                }
            }
            .navigationTitle("Nuova abitudine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea", action: save).disabled(!valid).accessibilityIdentifier("saveHabit")
                }
            }
            .alert("Salvataggio non riuscito", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 550)
        #endif
    }

    private func save() {
        guard valid else { return }
        context.insert(Habit(name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol,
            colorIndex: colorIndex, target: target, step: step, unit: unit.trimmingCharacters(in: .whitespaces),
            preferredHour: hour, durationMinutes: duration))
        do { try context.save(); WidgetCenter.shared.reloadAllTimelines(); dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
