import AuthenticationServices
import SwiftUI
import WidgetKit

struct OnboardingView: View {
    @Environment(AccountManager.self) private var account
    @State private var step = 0
    @State private var storage: StorageChoice?
    let finish: () -> Void

    private enum StorageChoice { case account, local }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text(verbatim: "makeet.").font(.title2.weight(.bold))
                        Spacer()
                        LanguageSettingsMenu()
                    }
                    if step == 0 { welcome }
                    else if step == 1 { storageChoice }
                    else { signIn }
                }
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(24).frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    if step == 0 {
                        Button { step = 1 } label: {
                            Text(String(localized: "Scegli come iniziare", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }.buttonStyle(.borderedProminent).foregroundStyle(.white).accessibilityIdentifier("onboardingContinue")
                    } else if step == 1 && storage == .local {
                        Button(action: finish) {
                            Text(String(localized: "Continua su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }.buttonStyle(.borderedProminent).foregroundStyle(.white).accessibilityIdentifier("onboardingLocal")
                    } else if step == 1 && storage == .account {
                        Button { step = 2; Task { await account.start() } } label: {
                            Text(String(localized: "Continua con un account", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }.buttonStyle(.borderedProminent).foregroundStyle(.white).accessibilityIdentifier("onboardingAccount")
                    }
                    HStack(spacing: 20) {
                        Link(String(localized: "Informativa privacy", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: policyURL("privacy"))
                            .frame(minHeight: 44)
                        Link(String(localized: "Condizioni d’uso", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: policyURL("terms"))
                            .frame(minHeight: 44)
                    }.font(.caption)
                }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 580)
                    .frame(maxWidth: .infinity).background(Palette.paper)
            }
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { step -= 1 } label: {
                            Label(String(localized: "Indietro", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "chevron.left")
                        }.disabled(account.working)
                    }
                }
            }
            .journalBackground().foregroundStyle(Palette.ink)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 680)
        #endif
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 7) {
                ForEach(0..<12) { index in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Palette.accent.opacity([0.16, 0.4, 0.75, 1.0][index % 4]))
                        .frame(width: 18, height: 38 + CGFloat(index % 3) * 11)
                }
            }.padding(.vertical, 20).accessibilityHidden(true)
            Text(String(localized: "Un passo, poi un altro.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Fai spazio alle abitudini che contano per te. Makeet ti aiuta a registrare quanto fai e a trovare il momento giusto.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.body).foregroundStyle(Palette.ink.opacity(0.78))
            feature("plusminus", title: String(localized: "Conta ogni piccolo passo", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                    body: String(localized: "Bicchieri, pagine, minuti: aggiungi le quantità e correggile quando serve.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            feature("chart.xyaxis.line", title: String(localized: "Capisci il tuo andamento", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                    body: String(localized: "Ritrova progressi, costanza e orari in cui le abitudini funzionano meglio.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
            feature("calendar", title: String(localized: "Un piano che lascia spazio", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                    body: String(localized: "Collega il calendario quando vuoi. Ogni nuovo evento richiede la tua conferma.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
    }

    private var storageChoice: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "Dove teniamo i tuoi progressi?", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Puoi scegliere adesso e accedere anche in seguito.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .foregroundStyle(Palette.ink.opacity(0.78))
            choice(.account, title: String(localized: "Con un account", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                   body: String(localized: "Salva i progressi nel tuo account Makeet e sincronizzali tra i tuoi dispositivi. L’accesso usa Apple o Google, senza una nuova password.", bundle: AppLanguage.bundle, locale: AppLanguage.locale), symbol: "person.crop.circle")
            choice(.local, title: String(localized: "Solo su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale),
                   body: String(localized: "Inizia senza registrarti. Le abitudini restano nell’archivio locale e non vengono caricate nel servizio Makeet. Non si sincronizzano con altri dispositivi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale), symbol: "iphone")
            if storage == .local {
                Text(String(localized: "Puoi passare a un account dalle impostazioni. Proteggi l’archivio locale: rimuovere l’app o perdere il dispositivo può causare la perdita dei progressi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.caption).foregroundStyle(Palette.ink.opacity(0.78))
            }
            if let message = account.message { Text(message).font(.callout).foregroundStyle(Palette.ink.opacity(0.78)) }
            Text(String(localized: "Calendario e notifiche restano facoltativi. Li attivi in seguito, con il tuo permesso.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.caption).foregroundStyle(Palette.ink.opacity(0.78))
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 48)).foregroundStyle(Palette.accent)
            Text(String(localized: "Accedi per sincronizzare", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.largeTitle.weight(.semibold))
            Text(String(localized: "Scegli Apple o Google. Usiamo l’identità e l’email fornite per creare il tuo account privato Makeet.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .foregroundStyle(Palette.ink.opacity(0.78))
            AccountSignInButtons()
            if account.providers.isEmpty {
                if account.checkingService { ProgressView() }
                else {
                    Button(String(localized: "Verifica disponibilità", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                        Task { await account.start() }
                    }
                }
            }
            if let message = account.message { Text(message).font(.callout).foregroundStyle(Palette.ink.opacity(0.78)) }
            Text(String(localized: "Se hai già progressi locali, sceglierai tu se importarli dopo l’accesso. Non carichiamo dati dimostrativi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.callout).foregroundStyle(Palette.ink.opacity(0.78))
            Button {
                storage = .local; step = 1
            } label: {
                Text(String(localized: "Preferisco continuare senza account", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .frame(minHeight: 44)
            }.disabled(account.working)
        }
    }

    private func choice(_ value: StorageChoice, title: String, body: String, symbol: String) -> some View {
        Button { storage = value } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.title2).frame(width: 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(body).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.78)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: storage == value ? "checkmark.circle.fill" : "circle")
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(storage == value ? Palette.soft : Palette.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(storage == value ? Palette.accent : Color.secondary.opacity(0.18), lineWidth: 1))
        }.buttonStyle(.plain).disabled(account.working)
            .accessibilityAddTraits(storage == value ? [.isSelected] : [])
            .accessibilityIdentifier(value == .account ? "onboardingAccountChoice" : "onboardingLocalChoice")
    }

    private func feature(_ symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title3).frame(width: 28).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.78))
            }
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
