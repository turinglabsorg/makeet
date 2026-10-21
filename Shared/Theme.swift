import SwiftUI

enum Palette {
    static let ink = Color("Ink")
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let muted = Color.secondary
    static let accent = Color(red: 0.22, green: 0.42, blue: 0.31)
    static let soft = Color.accentColor.opacity(0.09)
    static let warning = Color(red: 0.72, green: 0.45, blue: 0.35)
    static let habits: [Color] = [Color(red: 0.30, green: 0.50, blue: 0.38),
        Color(red: 0.40, green: 0.55, blue: 0.67), Color(red: 0.77, green: 0.58, blue: 0.26),
        Color(red: 0.72, green: 0.45, blue: 0.35)]
    static func habit(_ index: Int) -> Color { habits[abs(index % habits.count)] }
}

enum HabitText {
    static func quantity(_ quantity: Double, target: Double, unit: String, goal: HabitGoal) -> String {
        if goal == .atMost {
            return String(localized: "\(quantity.quantityText) / limite \(target.quantityText) \(unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
        return String(localized: "\(quantity.quantityText) / \(target.quantityText) \(unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
}

struct HabitProgressStatus: View {
    let progress: DayProgress
    let unit: String
    var body: some View {
        if progress.malus > 0 {
            Label(String(localized: "Malus: \(progress.malus.quantityText) \(unit)", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.warning)
        } else if progress.goal == .atMost && progress.registrations == 0 {
            Text(String(localized: "Da confermare", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).foregroundStyle(.secondary)
        } else if progress.goal == .atMost && progress.completed {
            Label(String(localized: "Limite rispettato", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.accent)
        }
    }
}

extension View {
    func journalCard(padding inset: CGFloat = 12) -> some View {
        padding(inset).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
    func journalBackground() -> some View { background(Palette.paper.ignoresSafeArea()) }
}

extension Double {
    var quantityText: String { formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.locale)) }
}
