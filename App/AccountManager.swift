import AuthenticationServices
import Foundation
import Observation
import SwiftData
import WidgetKit
import GoogleSignIn

@MainActor @Observable final class AccountManager {
    private(set) var container: ModelContainer?
    private(set) var user: AccountUser?
    private(set) var scope = StoreScope.local
    private(set) var providers: [String] = []
    private(set) var appleChallenge: AccountChallenge?
    private(set) var sync: AccountSyncService?
    private(set) var push: DevicePushService?
    private(set) var profile: AccountProfileService?
    private(set) var working = false
    private(set) var checkingService = false
    private(set) var startupError: String?
    var message: String?
    private var api: AccountAPI?
    private var requestedChallenge: AccountChallenge?
    private let testing: Bool
    var googleConfigured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !id.isEmpty,
              let serverID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String, !serverID.isEmpty else { return false }
        let expected = id.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains(expected) }
    }

    init() {
        testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        do {
            if testing {
                container = try ModelContainer(for: Habit.self, Activity.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--profile-fixture") {
                    let fixture = try ProfileUITestFixture()
                    user = fixture.user; scope = .account(fixture.user.id)
                    profile = fixture.service
                }
                #endif
                return
            }
            let storage = KeychainSessionStorage()
            var session = try storage.load()
            for raw in UserDefaults.standard.stringArray(forKey: "deletedAccountCaches") ?? [] {
                guard let id = UUID(uuidString: raw) else { continue }
                if session?.tokens.user.id == id { try storage.clear(); session = nil }
                if try WidgetAccountScope.current() == StoreScope.account(id).key { try WidgetAccountScope.activate(nil) }
                let directory = try AccountStoreLocation().directory(for: id)
                try FileManager.default.removeItem(at: directory)
            }
            UserDefaults.standard.removeObject(forKey: "deletedAccountCaches")
            api = try AccountAPI(storage: storage)
            if let user = session?.tokens.user { try activate(user) }
            else {
                if try WidgetAccountScope.current()?.hasPrefix("account-") == true { try WidgetAccountScope.activate(nil) }
                container = try SharedStore.makeContainer()
            }
        } catch { startupError = String(localized: "Archivio non disponibile", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
    }

    func start() async {
        guard !testing, !checkingService, let api else { return }
        checkingService = true
        defer { checkingService = false }
        do {
            message = nil
            providers = try await api.providers()
            await refreshAppleChallenge()
        } catch { message = String(localized: "Connessione al servizio non disponibile. Puoi continuare sul dispositivo.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        await sync?.synchronize()
        await profile?.refresh()
    }

    func refreshAppleChallenge() async {
        guard !testing, !working, user == nil, providers.contains("apple"), let api else { return }
        if let appleChallenge, appleChallenge.expiresAt > Int64(Date().timeIntervalSince1970) + 60 { return }
        appleChallenge = try? await api.challenge("apple")
    }

    func chooseLocalMode() throws {
        guard !testing, user == nil else { return }
        try WidgetAccountScope.activate(.local)
    }

    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        requestedChallenge = appleChallenge
        request.nonce = appleChallenge?.nonce
        request.requestedScopes = [.email, .fullName]
        appleChallenge = nil; working = true
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        defer { working = false; requestedChallenge = nil }
        guard let api else { return }
        do {
            let authorization = try result.get()
            guard let credentials = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let challenge = requestedChallenge,
                  let token = credentials.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                  let code = credentials.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) else {
                throw AccountAPIError.invalidResponse
            }
            let user = try await api.exchange(provider: "apple", challenge: challenge, token: token, code: code)
            try activate(user)
            let name = credentials.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            await profile?.importProvider(name: name)
            await sync?.synchronize()
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled {
                message = String(localized: "Accesso non riuscito. Riprova senza modificare il tuo archivio locale.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
            appleChallenge = try? await api.challenge("apple")
        }
    }

    func logout() async {
        guard !working, let api else { return }
        working = true; defer { working = false }
        do {
            let revoked = try await api.logout()
            try returnToLocal()
            await start()
            if !revoked { message = String(localized: "Uscita completata su questo dispositivo. La sessione sul servizio scadrà automaticamente.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        } catch { message = String(localized: "Disconnessione non completata. Verifica la connessione e riprova.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
    }

    func signInGoogle() async {
        guard !working, googleConfigured, let api,
              let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return }
        working = true; defer { working = false; GIDSignIn.sharedInstance.signOut() }
        do {
            let challenge = try await api.challenge("google")
            let serverID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverID)
            #if os(iOS)
            guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { throw AccountAPIError.invalidResponse }
            var presenting = root
            while let next = presenting.presentedViewController { presenting = next }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting, hint: nil,
                                                                  additionalScopes: nil, nonce: challenge.nonce)
            #else
            guard let window = NSApp.keyWindow else { throw AccountAPIError.invalidResponse }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window, hint: nil,
                                                                  additionalScopes: nil, nonce: challenge.nonce)
            #endif
            guard let token = result.user.idToken?.tokenString else { throw AccountAPIError.invalidResponse }
            let user = try await api.exchange(provider: "google", challenge: challenge, token: token)
            try activate(user)
            await profile?.importProvider(name: result.user.profile?.name,
                                          imageURL: result.user.profile?.hasImage == true ? result.user.profile?.imageURL(withDimension: 320) : nil)
            await sync?.synchronize()
        } catch {
            if (error as NSError).domain != kGIDSignInErrorDomain || (error as NSError).code != -5 {
                message = String(localized: "Accesso non riuscito. Riprova senza modificare il tuo archivio locale.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
        }
    }

    func deleteAccount() async {
        guard !working, let api, let user else { return }
        working = true; defer { working = false }
        let fallback: ModelContainer
        do {
            fallback = try SharedStore.makeContainer()
            try await api.deleteAccount()
        } catch {
            message = String(localized: "Eliminazione non completata. I dati restano disponibili: riprova quando il servizio è raggiungibile.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            return
        }
        var pendingDeletion = UserDefaults.standard.stringArray(forKey: "deletedAccountCaches") ?? []
        if !pendingDeletion.contains(user.id.uuidString) { pendingDeletion.append(user.id.uuidString) }
        UserDefaults.standard.set(pendingDeletion, forKey: "deletedAccountCaches")
        sync?.stop(); push?.stop(); profile?.stop()
        do {
            try await api.clearLocal()
            try WidgetAccountScope.activate(nil)
            if let context = container?.mainContext {
                try context.delete(model: Activity.self)
                try context.delete(model: Habit.self)
                try context.save()
            }
            let ledgerURL = try AccountStoreLocation().ledgerURL(for: user.id)
            try AccountCoding.encoder().encode(SyncLedger()).write(to: ledgerURL, options: .atomic)
            let photoURL = try AccountStoreLocation().directory(for: user.id).appendingPathComponent("profile.json")
            if FileManager.default.fileExists(atPath: photoURL.path) { try FileManager.default.removeItem(at: photoURL) }
            UserDefaults.standard.removeObject(forKey: scope.key + ".calendarSources")
            UserDefaults.standard.removeObject(forKey: scope.key + ".calendarDestination")
            for suffix in [".enabled", ".hour", ".minute"] {
                UserDefaults.standard.removeObject(forKey: "account-" + user.id.uuidString + ".push" + suffix)
            }
        } catch { message = String(localized: "Account eliminato dal servizio. La pulizia dell’archivio su questo dispositivo richiede un nuovo avvio.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        self.user = nil; sync = nil; push = nil; profile = nil; scope = .local; container = fallback
        await start()
    }

    func importLocalArchive() async {
        guard !working, user != nil, let context = container?.mainContext else { return }
        working = true; defer { working = false }
        do {
            let local = ModelContext(try SharedStore.makeContainer())
            let existing = Set(try AccountRecords.snapshot(in: context).map(\.key))
            let records = try AccountRecords.snapshot(in: local).filter { !existing.contains($0.key) }
            try AccountRecords.apply(records, in: context)
            await sync?.synchronize()
        } catch { message = String(localized: "Importazione non completata. L’archivio locale è conservato.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
    }

    private func activate(_ user: AccountUser) throws {
        guard let api else { throw AccountAPIError.signedOut }
        let next = try AccountStoreLocation().container(for: user.id)
        let service = try AccountSyncService(userID: user.id, context: next.mainContext, api: api)
        let devicePush = try DevicePushService(api: api, userID: user.id)
        let accountProfile = try AccountProfileService(userID: user.id, api: api)
        sync?.stop(); push?.stop(); profile?.stop(); try WidgetAccountScope.activate(nil)
        self.user = user; scope = .account(user.id); container = next; sync = service; push = devicePush; profile = accountProfile; message = nil
        try WidgetAccountScope.activate(scope)
    }

    private func returnToLocal() throws {
        let local = try SharedStore.makeContainer()
        sync?.stop(); push?.stop(); profile?.stop(); try WidgetAccountScope.activate(nil)
        user = nil; sync = nil; push = nil; profile = nil; scope = .local; container = local
    }
}
