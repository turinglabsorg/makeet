import SwiftUI

enum HabitAppearance {
    static func validEmoji(_ value: String) -> Bool {
        guard value.count == 1, value.utf8.count <= 64 else { return false }
        let scalars = value.unicodeScalars
        if scalars.contains(where: { $0.value == 0x20E3 }) { return true }
        let explicitPresentation = scalars.contains { $0.value == 0xFE0F }
        return scalars.contains {
            $0.properties.isEmojiPresentation || ($0.properties.isEmoji && ($0.value > 0x238C || ($0.value > 0x7F && explicitPresentation)))
        }
    }

    static func emoji(in symbol: String) -> String? {
        guard symbol.hasPrefix("emoji:") else { return nil }
        let value = String(symbol.dropFirst(6))
        return validEmoji(value) ? value : nil
    }
}

struct HabitMark: View {
    let symbol: String
    var body: some View {
        if let emoji = HabitAppearance.emoji(in: symbol) { Text(verbatim: emoji) }
        else { Image(systemName: symbol.hasPrefix("emoji:") ? "leaf" : symbol) }
    }
}
