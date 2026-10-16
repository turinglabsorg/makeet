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
                    if sync.syncing { ProgressView(String(localized: "Sincronizzazione in corso")) }
                    else if let last = sync.lastSuccess {
                        LabeledContent(String(localized: "Ultima sincronizzazione")) { Text(last, style: .relative) }
                    }
                    if let message = sync.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Button(String(localized: "Sincronizza ora")) { Task { await sync.synchronize() } }.disabled(sync.syncing)
                    ForEach(sync.ledger.conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(conflict.local.habit?.name ?? String(localized: "Attività modificata su più dispositivi")).font(.headline)
                            Text(String(localized: "Scegli quale versione conservare. Nessuna modifica viene scartata automaticamente."))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(String(localized: "Conserva su questo dispositivo")) { resolve(conflict, keepLocal: true) }
                            Button(String(localized: "Usa la versione sincronizzata")) { resolve(conflict, keepLocal: false) }
                        }.disabled(sync.syncing)
                    }
                }
                Button(String(localized: "Importa l’archivio locale")) { importing = true }
                Button(String(localized: "Esci dall’account")) { Task { await account.logout() } }
                Button(String(localized: "Elimina account"), role: .destructive) { deleting = true }
            } else {
                Text(String(localized: "I progressi restano su questo dispositivo finché non accedi."))
                    .font(.subheadline).foregroundStyle(.secondary)
                if account.providers.contains("apple") {
                    SignInWithAppleButton(.continue, onRequest: account.prepareApple) { result in
                        Task { await account.completeApple(result) }
                    }.frame(height: 48).disabled(account.appleChallenge == nil || account.working)
                }
                if account.providers.contains("google"), account.googleConfigured {
                    GoogleSignInButton { Task { await account.signInGoogle() } }.frame(height: 48)
                }
                if account.providers.isEmpty {
                    Text(String(localized: "Gli accessi Apple e Google saranno attivati al completamento della configurazione del servizio."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(String(localized: "Verifica disponibilità")) { Task { await account.start() } }
            }
            if let message = account.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: { Text(String(localized: "Account Makeet")) }
        footer: { Text(String(localized: "Ogni account ha un archivio separato. Accedere non carica automaticamente i dati locali o dimostrativi.")) }
        .disabled(account.working)
        .confirmationDialog(String(localized: "Eliminare l’account Makeet?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(String(localized: "Elimina account e dati"), role: .destructive) { Task { await account.deleteAccount() } }
            Button(String(localized: "Annulla"), role: .cancel) {}
        } message: { Text(String(localized: "Elimineremo dal servizio abitudini e attività e revocheremo l’accesso Apple. Questa operazione è definitiva.")) }
        .confirmationDialog(String(localized: "Importare in questo account?"), isPresented: $importing, titleVisibility: .visible) {
            Button(String(localized: "Conferma importazione")) { Task { await account.importLocalArchive() } }
            Button(String(localized: "Annulla"), role: .cancel) {}
        } message: { Text(String(localized: "Copia soltanto i progressi locali non dimostrativi nell’account attuale. L’archivio originale resta sul dispositivo.")) }
    }

    private func resolve(_ conflict: SyncConflict, keepLocal: Bool) {
        do { try account.sync?.resolve(conflict, keepLocal: keepLocal); Task { await account.sync?.synchronize() } }
        catch { account.message = String(localized: "Operazione non riuscita") }
    }
}
