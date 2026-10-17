import AuthenticationServices
import SwiftUI
import GoogleSignInSwift

struct AccountSettingsSection: View {
    @Environment(AccountManager.self) private var account
    @State private var deleting = false
    @State private var importing = false

    var body: some View {
        Section {
            if let user = account.user {
                if !user.email.isEmpty { Text(user.email).textSelection(.enabled) }
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
                            Text(String(localized: "Scegli quale versione conservare. Nessuna modifica viene scartata automaticamente.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(String(localized: "Conserva su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { resolve(conflict, keepLocal: true) }
                            Button(String(localized: "Usa la versione sincronizzata", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { resolve(conflict, keepLocal: false) }
                        }.disabled(sync.syncing)
                    }
                }
                Button(String(localized: "Importa l’archivio locale", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { importing = true }
                Button(String(localized: "Esci dall’account", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await account.logout() } }
                Button(String(localized: "Elimina account", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .destructive) { deleting = true }
            } else {
                Text(String(localized: "I progressi restano su questo dispositivo finché non accedi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.subheadline).foregroundStyle(.secondary)
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
        .confirmationDialog(String(localized: "Eliminare l’account Makeet?", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: $deleting, titleVisibility: .visible) {
            Button(String(localized: "Elimina account e dati", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .destructive) { Task { await account.deleteAccount() } }
            Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .cancel) {}
        } message: { Text(String(localized: "Elimineremo dal servizio abitudini e attività e revocheremo l’accesso Apple. Questa operazione è definitiva.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
        .confirmationDialog(String(localized: "Importare in questo account?", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: $importing, titleVisibility: .visible) {
            Button(String(localized: "Conferma importazione", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { Task { await account.importLocalArchive() } }
            Button(String(localized: "Annulla", bundle: AppLanguage.bundle, locale: AppLanguage.locale), role: .cancel) {}
        } message: { Text(String(localized: "Copia soltanto i progressi locali non dimostrativi nell’account attuale. L’archivio originale resta sul dispositivo.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) }
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
            if account.providers.contains("apple") {
                SignInWithAppleButton(.continue, onRequest: account.prepareApple) { result in
                    Task { await account.completeApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50).disabled(account.appleChallenge == nil || account.working)
                .accessibilityIdentifier("appleSignIn")
            }
            if account.providers.contains("google"), account.googleConfigured {
                GoogleSignInButton { Task { await account.signInGoogle() } }
                    .frame(height: 50).disabled(account.working).accessibilityIdentifier("googleSignIn")
            }
            if account.working { ProgressView() }
        }
    }
}
