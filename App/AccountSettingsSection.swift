import AuthenticationServices
import SwiftUI

struct AccountSettingsSection: View {
    @Environment(AccountManager.self) private var account
    @Binding var deleting: Bool
    @Binding var importing: Bool
    @Binding var editingProfile: Bool

    var body: some View {
        Section {
            if let user = account.user {
                ProfileIdentityHeader(profile: account.profile?.value ?? AccountProfile(), email: user.email)
                Button {
                    editingProfile = true
                } label: {
                    Label(String(localized: "Modifica profilo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "person.crop.circle.badge.pencil")
                }.accessibilityIdentifier("editProfile")
                if let sync = account.sync {
                    if sync.syncing { ProgressView(String(localized: "Sincronizzazione in corso", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
                    else if let last = sync.lastSuccess {
                        LabeledContent(String(localized: "Ultima sincronizzazione", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Text(last, style: .relative) }
                            .accessibilityIdentifier("lastAccountSync")
                    }
                    if let message = sync.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Button(String(localized: "Sincronizza ora", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await sync.synchronize() } }.disabled(sync.syncing)
                        .accessibilityIdentifier("accountSyncNow")
                    ForEach(sync.ledger.conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(conflict.local.habit?.name ?? String(localized: "Attività modificata su più dispositivi", bundle: AppLanguage.bundle, locale: AppLanguage.locale)).font(.headline)
                            Text(conflict.remote.deleted ? String(localized: "Questi dati sono stati eliminati su un altro dispositivo. Conferma la rimozione anche qui.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Scegli quale versione conservare. Nessuna modifica viene scartata automaticamente.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .font(.caption).foregroundStyle(.secondary)
                            if !conflict.remote.deleted {
                                Button(String(localized: "Conserva su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { resolve(conflict, keepLocal: true) }
                            }
                            Button(conflict.remote.deleted ? String(localized: "Rimuovi anche qui", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Usa la versione sincronizzata", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { resolve(conflict, keepLocal: false) }
                        }.disabled(sync.syncing)
                    }
                }
                Button(String(localized: "Importa l’archivio locale", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { importing = true }
                Button(String(localized: "Esci dall’account", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await account.logout() } }
                Button(String(localized: "Elimina account", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .destructive) { deleting = true }
            } else {
                Label(String(localized: "Accedi per sincronizzare", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "checkmark.icloud")
                    .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 8)
                Text(String(localized: "I progressi restano su questo dispositivo finché non accedi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.72))
                AccountSignInButtons()
                if account.providers.isEmpty {
                    Text(String(localized: "Gli accessi Apple e Google saranno attivati al completamento della configurazione del servizio.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(String(localized: "Verifica disponibilità", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await account.start() } }
            }
            Link(String(localized: "Informativa privacy", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: policyURL("privacy"))
            Link(String(localized: "Condizioni d’uso", bundle: AppLanguage.bundle, locale: AppLanguage.locale), destination: policyURL("terms"))
            if let message = account.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: { Text(String(localized: "Account Makeet", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        footer: { Text(String(localized: "Ogni account ha un archivio separato. Accedere non carica automaticamente i dati locali o dimostrativi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        .disabled(account.working)
    }

    private func resolve(_ conflict: SyncConflict, keepLocal: Bool) {
        do { try account.sync?.resolve(conflict, keepLocal: keepLocal); Task { await account.sync?.synchronize() } }
        catch { account.message = String(localized: "Operazione non riuscita", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
    }

    private func policyURL(_ page: String) -> URL {
        let code = AppLanguage.code
        let language = ["it", "en", "fr", "de", "es"].contains(code) ? code : "en"
        return URL(string: "https://makeet.app/" + language + "/" + page)!
    }
}


struct AccountSignInButtons: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 12) {
            if account.providers.contains("apple") || account.user == nil {
                SignInWithAppleButton(.continue, onRequest: account.prepareApple) { result in
                    Task { await account.completeApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 15))
                .disabled(account.appleChallenge == nil || account.working)
                .accessibilityIdentifier("appleSignIn")
            }
            if account.googleConfigured {
                Button { Task { await account.signInGoogle() } } label: {
                    HStack(spacing: 12) {
                        Image("GoogleMark").resizable().interpolation(.high).frame(width: 20, height: 20)
                        Text(String(localized: "Continua con Google", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                            .font(.system(size: 17, weight: .medium)).foregroundStyle(colorScheme == .dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.12))
                    }.frame(maxWidth: .infinity, minHeight: 54)
                        .background(colorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.075) : .white, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.gray.opacity(0.55), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain)
                    .disabled(account.working || !account.providers.contains("google"))
                    .accessibilityIdentifier("googleSignIn")
            }
            if account.working { ProgressView() }
        }
    }
}
