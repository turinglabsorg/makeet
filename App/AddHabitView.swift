import SwiftUI
import SwiftData
import WidgetKit

struct AddHabitView: View {
    let habit: Habit?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, unit, target, step, emoji }
    @State private var name = ""
    @State private var unit = String(localized: "volte", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    @State private var target = 3.0
    @State private var step = 1.0
    @State private var goal: HabitGoal = .atLeast
    @State private var allowsNegative = false
    @State private var colorIndex = 0
    @State private var symbol = "leaf"
    @State private var usesEmoji = false
    @State private var emoji = "🌱"
    @State private var hour = 18
    @State private var duration = 20
    @State private var weekdayMask = 127
    @State private var startDate = Date()
    @State private var original: SyncRecord?
    @State private var error: String?
    private let symbols = ["leaf", "drop", "book.closed", "figure.walk", "brain.head.profile", "sun.max", "pencil", "cup.and.saucer"]
    private let emojis = ["🌱", "💧", "📚", "🚶", "🧠", "☀️", "✍️", "☕️", "🏃", "🎯", "🧘", "💤"]
    private var valid: Bool { weekdayMask > 0 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && target.isFinite && (target > 0 || (goal == .atMost && target == 0)) && step.isFinite && step > 0 && !unit.trimmingCharacters(in: .whitespaces).isEmpty && (!usesEmoji || HabitAppearance.validEmoji(emoji)) }

    init(habit: Habit? = nil) {
        self.habit = habit
        if let habit {
            _original = State(initialValue: habit.syncRecord)
            _name = State(initialValue: habit.name); _unit = State(initialValue: habit.unit)
            _target = State(initialValue: habit.target); _step = State(initialValue: habit.step)
            _goal = State(initialValue: habit.goal); _allowsNegative = State(initialValue: habit.allowsNegative)
            _colorIndex = State(initialValue: habit.colorIndex); _symbol = State(initialValue: habit.symbol)
            _usesEmoji = State(initialValue: HabitAppearance.emoji(in: habit.symbol) != nil)
            _emoji = State(initialValue: HabitAppearance.emoji(in: habit.symbol) ?? "🌱")
            _hour = State(initialValue: habit.preferredHour); _duration = State(initialValue: habit.durationMinutes)
            _weekdayMask = State(initialValue: habit.weekdayMask)
            _startDate = State(initialValue: habit.createdAt)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "La tua abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                    TextField(String(localized: "Ad esempio: bere acqua", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $name)
                        .focused($focusedField, equals: .name).submitLabel(.done).onSubmit { focusedField = nil }.accessibilityIdentifier("habitName")
                    Picker(String(localized: "Aspetto", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $usesEmoji) {
                        Text(String(localized: "Icona", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(false)
                        Text(String(localized: "Emoji", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("appearanceKind")
                    if usesEmoji {
                        HStack {
                            Text(String(localized: "La tua emoji", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            Spacer()
                            TextField(String(localized: "Una sola emoji", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $emoji)
                                .focused($focusedField, equals: .emoji)
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
                    if habit != nil {
                        Text(String(localized: "Le modifiche a obiettivo e giorni si applicano anche alle statistiche passate. Le quantità registrate restano invariate.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                    }
                    DatePicker(String(localized: "Data di inizio", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $startDate, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("habitStartDate")
                    WeekdayPicker(mask: $weekdayMask)
                    if weekdayMask == 0 {
                        Text(String(localized: "Scegli almeno un giorno.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text(String(localized: "In quali giorni?", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                Section {
                    Picker(String(localized: "Tipo di obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $goal) {
                        Text(String(localized: "Raggiungere", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(HabitGoal.atLeast)
                        Text(String(localized: "Non superare", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).tag(HabitGoal.atMost)
                    }.pickerStyle(.segmented).accessibilityIdentifier("habitGoal")
                    TextField(String(localized: "Unità, es. bicchieri, pagine, minuti", bundle: AppLanguage.bundle, locale: AppLanguage.locale), text: $unit).focused($focusedField, equals: .unit).accessibilityIdentifier("habitUnit")
                    HStack { Text(String(localized: "Obiettivo al giorno", bundle: AppLanguage.bundle, locale: AppLanguage.locale)); Spacer(); TextField(String(localized: "Obiettivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: $target, format: .number).focused($focusedField, equals: .target).multilineTextAlignment(.trailing).frame(width: 90).accessibilityIdentifier("habitTarget") }
                    HStack { Text(String(localized: "Quantità per tocco", bundle: AppLanguage.bundle, locale: AppLanguage.locale)); Spacer(); TextField(String(localized: "Incremento", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: $step, format: .number).focused($focusedField, equals: .step).multilineTextAlignment(.trailing).frame(width: 90).accessibilityIdentifier("habitStep") }
                    Toggle(String(localized: "Consenti valori negativi", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isOn: $allowsNegative).accessibilityIdentifier("allowNegative")
                } header: { Text(String(localized: "Misura i tuoi passi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(goal == .atMost ? String(localized: "Scegli un limite, anche zero. Le quantità oltre il limite contano come malus. Conferma zero per registrare un giorno senza occorrenze.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Puoi registrare più volte al giorno, anche oltre l’obiettivo. Ogni tocco conserva quantità e orario.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        Text(String(localized: "Con i valori negativi attivi, il pulsante meno può portare il saldo sotto zero. Lo storico mantiene il segno delle quantità.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    }
                }
                if goal == .atLeast { Section {
                    Picker(String(localized: "Orario preferito", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $hour) {
                        ForEach(7..<22) { hour in
                            Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!, style: .time).tag(hour)
                        }
                    }
                    Stepper(String(localized: "Sessione da \(duration) minuti", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: $duration, in: 5...120, step: 5)
                } header: { Text(String(localized: "Trova il tuo momento", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } footer: {
                    Text(String(localized: "L’assistente userà queste preferenze per proporti uno spazio libero. Nessun evento viene creato automaticamente.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                } } else {
                    Section { Text(String(localized: "Le abitudini da limitare non generano proposte di eventi nel calendario.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: usesEmoji) { _, value in if !value && !symbols.contains(symbol) { symbol = "leaf" } }
            .onChange(of: goal) { _, value in
                focusedField = nil
                if value == .atMost { target = 0 }
                else if target <= 0 { target = 1 }
            }
            .navigationTitle(habit == nil ? String(localized: "Nuova abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Modifica abitudine", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "Fine", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { focusedField = nil }.accessibilityIdentifier("habitKeyboardDone")
                }
                #endif
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(habit == nil ? String(localized: "Crea", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Salva", bundle: AppLanguage.bundle, locale: AppLanguage.locale), action: save).disabled(!valid).accessibilityIdentifier("saveHabit")
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
        if let habit, habit.modelContext == nil || habit.syncRecord != original {
            error = String(localized: "L’abitudine è cambiata. Chiudi e riapri la modifica prima di salvare.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            return
        }
        let zone = habit?.snapshot.calendar ?? Calendar.current
        let beginning = zone.startOfDay(for: startDate)
        if let habit {
            let id = habit.id
            let entries = (try? context.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.habitID == id }))) ?? []
            if entries.contains(where: { $0.timestamp < beginning }) {
                error = String(localized: "La data di inizio non può escludere progressi già registrati.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                return
            }
        }
        let value = habit ?? Habit(name: name, symbol: symbol, colorIndex: colorIndex, target: target, step: step,
            unit: unit, goal: goal, allowsNegative: allowsNegative)
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.symbol = usesEmoji ? "emoji:\(emoji)" : (HabitAppearance.emoji(in: symbol) == nil ? symbol : "leaf")
        value.colorIndex = colorIndex; value.target = target; value.step = step
        value.goal = goal; value.allowsNegative = allowsNegative
        value.unit = unit.trimmingCharacters(in: .whitespaces); value.preferredHour = hour
        value.durationMinutes = duration; value.weekdayMask = weekdayMask
        value.createdAt = beginning
        if habit == nil { context.insert(value) }
        do { try context.save(); WidgetCenter.shared.reloadAllTimelines(); dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct WeekdayPicker: View {
    @Binding var mask: Int
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.locale = AppLanguage.locale; return value }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<7) { day in
                let index = (day + 1) % 7
                let selected = mask & (1 << day) != 0
                Button { mask ^= 1 << day } label: {
                    Text(calendar.shortStandaloneWeekdaySymbols[index]).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? Palette.accent : Palette.soft, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(selected ? .white : Palette.ink)
                }.buttonStyle(.plain).accessibilityLabel(calendar.standaloneWeekdaySymbols[index])
                    .accessibilityIdentifier("weekday-\(day)").accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(.vertical, 4)
    }
}
