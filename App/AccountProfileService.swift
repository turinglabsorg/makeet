import Foundation
import Observation

@MainActor @Observable final class AccountProfileService {
    private(set) var value = AccountProfile()
    private(set) var saving = false
    var message: String?
    private let api: AccountAPI
    private let userID: UUID
    private let cacheURL: URL
    private var stopped = false
    private var refreshing = false
    private var generation = UUID()

    init(userID: UUID, api: AccountAPI) throws {
        self.userID = userID; self.api = api
        cacheURL = try AccountStoreLocation().directory(for: userID).appendingPathComponent("profile.json")
        if let data = try? Data(contentsOf: cacheURL), let cached = try? AccountCoding.decoder().decode(AccountProfile.self, from: data) {
            value = cached
        }
    }
    func stop() { stopped = true; generation = UUID() }
    func refresh() async {
        guard !stopped, !saving, !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        let epoch = generation
        guard let next = try? await api.profile(userID: userID), !stopped, epoch == generation else { return }
        apply(next)
    }
    func save(name: String, image: Data?, revision: Int64? = nil) async -> Bool {
        guard !stopped, !saving else { return false }
        generation = UUID(); let epoch = generation
        saving = true; message = nil
        defer { saving = false }
        do {
            let next = try await api.updateProfile(AccountProfile(name: name, image: image, revision: revision ?? value.revision), userID: userID)
            guard !stopped, epoch == generation else { return false }
            apply(next)
            return true
        } catch {
            guard !stopped, epoch == generation else { return false }
            if case AccountAPIError.response(409, _) = error {
                message = String(localized: "Il profilo è cambiato su un altro dispositivo. Riapri la modifica per caricare la versione aggiornata.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
                if let next = try? await api.profile(userID: userID), !stopped, epoch == generation { apply(next) }
            } else {
                message = String(localized: "Profilo non salvato. Controlla la connessione e riprova.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
            return false
        }
    }
    func importProvider(name: String?, imageURL: URL? = nil) async {
        await refresh()
        guard !stopped, value.revision == 0 else { return }
        let image = await ProfileImage.providerImage(at: imageURL)
        guard !stopped, value.revision == 0, !(name ?? "").isEmpty || image != nil else { return }
        _ = await save(name: name ?? "", image: image)
    }
    private func apply(_ profile: AccountProfile) {
        value = profile
        guard let data = try? AccountCoding.encoder().encode(profile) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }
}
