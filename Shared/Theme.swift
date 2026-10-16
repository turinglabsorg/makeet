import SwiftUI

enum Palette {
    static let ink = Color("Ink")
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let muted = Color.secondary
    static let accent = Color(red: 0.22, green: 0.42, blue: 0.31)
    static let soft = Color.accentColor.opacity(0.09)
    static let habits: [Color] = [Color(red: 0.30, green: 0.50, blue: 0.38),
        Color(red: 0.40, green: 0.55, blue: 0.67), Color(red: 0.77, green: 0.58, blue: 0.26),
        Color(red: 0.72, green: 0.45, blue: 0.35)]
    static func habit(_ index: Int) -> Color { habits[abs(index % habits.count)] }
}

extension View {
    func journalCard() -> some View {
        padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
    }
    func journalBackground() -> some View { background(Palette.paper.ignoresSafeArea()) }
}

extension Double {
    var quantityText: String { formatted(.number.precision(.fractionLength(0...1))) }
}
