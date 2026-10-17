import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, it, en, fr, de, es
    static let preferenceKey = "MakeetLanguage"
    static var defaults: UserDefaults {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return .standard }
        return UserDefaults(suiteName: "group.org.turinglabs.makeet") ?? .standard
    }
    static var selected: AppLanguage { AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "system") ?? .system }
    static var locale: Locale { selected == .system ? .autoupdatingCurrent : Locale(identifier: selected.rawValue) }
    static var code: String {
        selected == .system ? (Locale.current.language.languageCode?.identifier ?? "en") : selected.rawValue
    }
    static var bundle: Bundle {
        guard selected != .system, let path = Bundle.main.path(forResource: selected.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: return String(localized: "Lingua del dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .it: return "Italiano"
        case .en: return "English"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }
}
