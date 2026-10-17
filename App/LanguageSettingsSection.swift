import SwiftUI
import WidgetKit

struct LanguageSettingsSection: View {
    @AppStorage(AppLanguage.preferenceKey, store: AppLanguage.defaults) private var language = "system"
    var body: some View {
        Section {
            Picker(String(localized: "Lingua dell’app", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $language) {
                ForEach(AppLanguage.allCases) { item in Text(verbatim: item.nativeName).tag(item.rawValue) }
            }
            .accessibilityIdentifier("appLanguage")
            .onChange(of: language) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        } header: { Text(String(localized: "Lingua", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
    }
}
