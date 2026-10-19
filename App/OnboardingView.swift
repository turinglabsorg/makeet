import AuthenticationServices
import SwiftUI
import WidgetKit

struct OnboardingView: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var step: Int
    @State private var storage: StorageChoice?
    @State private var editingProfile = false
    let finish: () -> Void

    private enum StorageChoice { case account, local }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    Group {
                        switch step {
                        case 0: welcome
                        case 1: storageChoice
                        case 2: signIn
                        default: ready
                        }
                    }.transition(.opacity)
                }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .journalBackground().foregroundStyle(Palette.ink)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
            .toolbar(.hidden, for: .automatic)
            .onChange(of: account.user?.id, initial: true) { _, user in
                if user != nil && step == 2 { step = 3 }
            }
            .task { if account.user != nil { await account.start() } }
            .sheet(isPresented: $editingProfile) {
                if let profile = account.profile { ProfileEditorView(service: profile) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 720)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                if step > 0 {
                    Button { step = step == 3 ? 0 : step - 1 } label: {
                        Image(systemName: "arrow.left").font(.title3.weight(.medium)).frame(width: 44, height: 44)
                            .background(Palette.card, in: Circle())
                    }.buttonStyle(.plain).disabled(account.working)
                        .accessibilityLabel(String(localized: "Indietro", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                } else {
                    Text(verbatim: "makeet.").font(.title2.weight(.bold)).tracking(-0.7)
                }
                Spacer()
                LanguageSettingsMenu()
            }
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule().fill(index <= min(step, 2) ? Palette.accent : Palette.accent.opacity(0.13)).frame(height: 4)
                }
            }.accessibilityHidden(true)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Un passo, poi un altro.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.largeTitle.weight(.bold)).tracking(-0.8)
                Text(String(localized: "Le abitudini che vuoi, nel ritmo della tua giornata.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.title3).foregroundStyle(Palette.ink.opacity(0.72))
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(String(localized: "La tua giornata", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                    Spacer()
                    Image(systemName: "sun.max").foregroundStyle(Palette.habit(2))
                }
                previewHabit("drop.fill", title: String(localized: "Bere acqua", bundle: AppLanguage.bundle, locale: AppLanguage.locale), quantity: "2 / 6", color: Palette.habit(1), fraction: 0.33)
                previewHabit("book.closed.fill", title: String(localized: "Leggere", bundle: AppLanguage.bundle, locale: AppLanguage.locale), quantity: "10 / 20", color: Palette.habit(0), fraction: 0.5)
                HStack(spacing: 7) {
                    ForEach(0..<14) { index in
                        RoundedRectangle(cornerRadius: 4).fill(Palette.accent.opacity([0.14, 0.35, 0.6, 1][index % 4])).frame(height: 17)
                    }
                }.accessibilityHidden(true)
                Text(String(localized: "Un esempio della tua giornata", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.caption).foregroundStyle(Palette.ink.opacity(0.72))
            }.padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.accent.opacity(0.08)))
            Label(String(localized: "Conta i progressi. Trova il tuo momento.", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "sparkles")
                .font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var storageChoice: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "tray.2.fill").font(.system(size: 32)).foregroundStyle(Palette.accent)
                .frame(width: 64, height: 64).background(Palette.soft, in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Dove teniamo i tuoi progressi?", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.largeTitle.weight(.bold)).tracking(-0.7)
                Text(String(localized: "Con un account li ritrovi anche su un nuovo dispositivo. Oppure puoi iniziare solo qui.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .foregroundStyle(Palette.ink.opacity(0.72))
            }
            choice(.account, title: String(localized: "Con un account", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                   body: String(localized: "Il tuo archivio privato, sincronizzato con Makeet Plus. Accedi con Apple o Google.", bundle: AppLanguage.bundle, locale: AppLanguage.locale), symbol: "person.crop.circle.fill")
            choice(.local, title: String(localized: "Solo su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                   body: String(localized: "Nessuna registrazione. I progressi restano qui: potrai accedere quando vuoi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale), symbol: "iphone")
            Text(storage == .local
                 ? String(localized: "Senza account, rimuovere l’app o perdere il dispositivo può far perdere i progressi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                 : String(localized: "La scelta è tua. Calendario e notifiche si attivano solo quando vuoi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.footnote).foregroundStyle(Palette.ink.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: -12) {
                Image(systemName: "iphone").rotationEffect(.degrees(-9))
                Image(systemName: "checkmark.icloud.fill").foregroundStyle(Palette.accent)
                Image(systemName: "laptopcomputer").rotationEffect(.degrees(9))
            }.font(.system(size: 32)).frame(maxWidth: .infinity, minHeight: 108)
                .background(Palette.soft, in: RoundedRectangle(cornerRadius: 26)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Accedi per sincronizzare", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.largeTitle.weight(.bold)).tracking(-0.7)
                Text(String(localized: "È il tuo primo accesso? Creiamo il tuo account. Sei già dei nostri? Ritrovi i tuoi progressi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .foregroundStyle(Palette.ink.opacity(0.72))
            }
            AccountSignInButtons()
            if account.checkingService { ProgressView() }
            else if account.providers.isEmpty {
                Button(String(localized: "Verifica disponibilità", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await account.start() } }
            }
            if let message = account.message { Text(message).font(.callout).foregroundStyle(Palette.ink.opacity(0.72)) }
            Label(String(localized: "Nessuna nuova password. Nessun profilo pubblico.", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "lock")
                .font(.footnote).foregroundStyle(Palette.ink.opacity(0.72))
            Text(String(localized: "Hai già abitudini sul dispositivo? Dopo l’accesso decidi tu se importarle.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.footnote).foregroundStyle(Palette.ink.opacity(0.72))
            Button {
                storage = .local; step = 1
            } label: {
                Text(String(localized: "Preferisco continuare senza account", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.subheadline).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(Palette.accent).disabled(account.working)
        }.task { await account.start() }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let user = account.user {
                ProfileIdentityHeader(profile: account.profile?.value ?? AccountProfile(), email: user.email)
                Button { editingProfile = true } label: {
                    Label(String(localized: "Aggiungi il tuo tocco", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "camera")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("onboardingProfile")
            } else {
                Image(systemName: "checkmark").font(.system(size: 30, weight: .semibold)).foregroundStyle(Palette.accent)
                    .frame(width: 72, height: 72).background(Palette.soft, in: Circle())
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Partiamo da una cosa semplice.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.largeTitle.weight(.bold)).tracking(-0.7)
                Text(String(localized: "Scegli la prima abitudine e quanto vuoi fare. Puoi cambiare tutto, un passo alla volta.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .foregroundStyle(Palette.ink.opacity(0.72))
            }
            VStack(alignment: .leading, spacing: 18) {
                readyRow("plusminus", text: String(localized: "Aggiungi una quantità, correggila con meno.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                readyRow("chart.xyaxis.line", text: String(localized: "Guarda come cresci, giorno dopo giorno.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                readyRow("calendar", text: String(localized: "Collega il calendario quando sei pronto.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            if let message = account.message { Text(message).font(.footnote).foregroundStyle(Palette.ink.opacity(0.72)) }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if step != 2 {
                Button {
                    switch step {
                    case 0: step = account.user == nil ? 1 : 3
                    case 1: step = storage == .account ? 2 : 3
                    default: finish()
                    }
                } label: {
                    HStack {
                        Text(primaryTitle).font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right").font(.headline)
                    }.padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: 56)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 17)).foregroundStyle(.white)
                        .opacity(step == 1 && storage == nil ? 0.45 : 1)
                }.buttonStyle(.plain).disabled(account.working || (step == 1 && storage == nil))
                    .accessibilityIdentifier(primaryIdentifier)
            }
            HStack(spacing: 8) {
                Link(String(localized: "Informativa privacy", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: policyURL("privacy"))
                Text(verbatim: "·").accessibilityHidden(true)
                Link(String(localized: "Condizioni d’uso", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: policyURL("terms"))
            }.font(.caption).foregroundStyle(Palette.ink.opacity(0.72)).frame(minHeight: 36)
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: 520).frame(maxWidth: .infinity).background(Palette.paper)
    }

    private var primaryTitle: String {
        if step == 0 { return String(localized: "Scegli come iniziare", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if step == 3 { return String(localized: "Entra in Makeet", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if storage == .account { return String(localized: "Continua con un account", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if storage == .local { return String(localized: "Continua su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        return String(localized: "Continua", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
    private var primaryIdentifier: String {
        if step == 0 { return "onboardingContinue" }
        if step == 3 { return "onboardingFinish" }
        return storage == .local ? "onboardingLocal" : storage == .account ? "onboardingAccount" : "onboardingChoose"
    }
    private func readyRow(_ symbol: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 26)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func choice(_ value: StorageChoice, title: String, body: String, symbol: String) -> some View {
        Button { storage = value } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Palette.accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(body).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.72))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: storage == value ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(Palette.accent)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                .background(storage == value ? Palette.soft : Palette.card, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(storage == value ? Palette.accent : Palette.accent.opacity(0.10), lineWidth: storage == value ? 2 : 1))
        }.buttonStyle(.plain).disabled(account.working)
            .accessibilityAddTraits(storage == value ? [.isSelected] : [])
            .accessibilityIdentifier(value == .account ? "onboardingAccountChoice" : "onboardingLocalChoice")
    }
    private func previewHabit(_ symbol: String, title: String, quantity: String, color: Color, fraction: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 42, height: 42)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(verbatim: quantity).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color)
            }
            GeometryReader { proxy in
                Capsule().fill(color.opacity(0.12)).overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: proxy.size.width * fraction)
                }
            }.frame(height: 5).accessibilityHidden(true)
        }
    }
    private func policyURL(_ path: String) -> URL {
        let code = ["it", "en", "fr", "de", "es"].contains(AppLanguage.code) ? AppLanguage.code : "en"
        return URL(string: "https://makeet.app/" + code + "/" + path)!
    }
}

struct LanguageSettingsMenu: View {
    @Environment(AccountManager.self) private var account
    @AppStorage(AppLanguage.preferenceKey, store: AppLanguage.defaults) private var language = "system"
    var body: some View {
        Menu {
            Picker(String(localized: "Lingua", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $language) {
                ForEach(AppLanguage.allCases) { item in Text(verbatim: item.nativeName).tag(item.rawValue) }
            }
        } label: {
            let code = AppLanguage.selected == .system ? (Bundle.main.preferredLocalizations.first ?? "en") : language
            Label(code.uppercased(), systemImage: "globe").font(.subheadline.weight(.medium)).frame(minHeight: 44)
        }.disabled(account.working).accessibilityIdentifier("onboardingLanguage")
            .onChange(of: language) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
    }
}
