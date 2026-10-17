import Foundation
import Observation
import Security

private struct PushInstallation: Codable {
    let id: UUID
    let secret: String

    static func load() throws -> PushInstallation {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.turinglabs.makeet.push-installation",
            kSecAttrAccount as String: "current", kSecAttrSynchronizable as String: false]
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try JSONDecoder().decode(PushInstallation.self, from: data)
        }
        guard status == errSecItemNotFound else { throw KeychainFailure(status: status) }
        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw KeychainFailure(status: randomStatus) }
        let value = PushInstallation(id: UUID(), secret: Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: ""))
        var item = query
        item[kSecValueData as String] = try JSONEncoder().encode(value)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainFailure(status: added) }
        return value
    }
}

@MainActor @Observable final class DevicePushService {
    private let api: AccountAPI
    private let userID: UUID
    private let installation: PushInstallation
    private let prefix: String
    private var active = true
    private var reconciling = false
    private var lastRegistration: Data?
    private var lastAttempt = Date.distantPast
    private var removed = false
    private var pendingTest: UUID?
    private(set) var registered = false
    private(set) var accepted = false
    private(set) var confirmed = false
    private(set) var testing = false
    private(set) var message: String?
    var remindersEnabled: Bool {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: prefix + ".enabled") }
    }
    var reminderTime: Date {
        didSet {
            let values = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            UserDefaults.standard.set(values.hour ?? 19, forKey: prefix + ".hour")
            UserDefaults.standard.set(values.minute ?? 0, forKey: prefix + ".minute")
        }
    }

    init(api: AccountAPI, userID: UUID) throws {
        self.api = api; self.userID = userID; installation = try PushInstallation.load()
        prefix = "account-" + userID.uuidString + ".push"
        remindersEnabled = UserDefaults.standard.bool(forKey: prefix + ".enabled")
        let hour = UserDefaults.standard.object(forKey: prefix + ".hour") as? Int ?? 19
        let minute = UserDefaults.standard.integer(forKey: prefix + ".minute")
        reminderTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    var deliveryLabel: String {
        if confirmed { return String(localized: "Ricezione confermata su questo dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if accepted { return String(localized: "Accettata da Apple · ricezione da confermare", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if registered { return String(localized: "Collegato al servizio Makeet", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        return String(localized: "Collegamento da verificare", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }

    func stop() { active = false }

    func reconcile(_ notifications: NotificationService, force: Bool = false) async {
        guard active, !reconciling else { return }
        reconciling = true
        defer { reconciling = false }
        do {
            if !notifications.authorized {
                if !removed {
                    do { try await api.removePush(id: installation.id, userID: userID, secret: installation.secret) }
                    catch AccountAPIError.response(404, _) {}
                    guard active else { return }
                    removed = true; registered = false; accepted = false; confirmed = false; lastRegistration = nil
                }
                return
            }
            guard let token = notifications.deviceToken, let topic = Bundle.main.bundleIdentifier else { return }
            #if DEBUG
            let environment = "development"
            #else
            let environment = "production"
            #endif
            let language = AppLanguage.code
            let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            let registration = PushRegistration(installationSecret: installation.secret,
                token: token.map { String(format: "%02x", $0) }.joined(), topic: topic, environment: environment,
                language: ["it", "en", "fr", "de", "es"].contains(language) ? language : "en", timeZone: TimeZone.current.identifier,
                remindersEnabled: remindersEnabled, reminderHour: time.hour ?? 19, reminderMinute: time.minute ?? 0)
            let data = try AccountCoding.encoder().encode(registration)
            if force || lastRegistration != data || Date().timeIntervalSince(lastAttempt) >= 60 {
                lastAttempt = Date()
                let status = try await api.registerPush(id: installation.id, userID: userID, registration: registration)
                guard active else { return }
                registered = status.registered; removed = false; lastRegistration = data; message = nil
                accepted = status.acceptedAt > 0; confirmed = status.confirmedAt > 0
            }
            for id in notifications.pendingReceipts {
                guard active else { return }
                do {
                    try await api.confirmPush(id: installation.id, userID: userID, secret: installation.secret, messageID: id)
                    guard active else { return }
                    notifications.acknowledged(id); confirmed = true
                } catch AccountAPIError.response(404, _) { notifications.acknowledged(id) }
            }
        } catch {
            guard active else { return }
            message = String(localized: "Collegamento notifiche non disponibile. Riprova con una connessione attiva.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }

    func sendTest(_ notifications: NotificationService) async {
        guard active, !testing else { return }
        testing = true; defer { testing = false }
        await reconcile(notifications, force: true)
        guard registered, active else { return }
        do {
            let id = pendingTest ?? UUID(); pendingTest = id
            let result = try await api.testPush(id: installation.id, userID: userID, secret: installation.secret, messageID: id)
            guard active else { return }
            if result.status == "accepted" { accepted = true; pendingTest = nil; message = nil }
            else if result.status == "failed" { pendingTest = nil; message = String(localized: "Invio non riuscito. Riprova il test.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            else { message = String(localized: "Invio in attesa. Il servizio riproverà automaticamente.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
            if result.confirmedAt > 0 { confirmed = true }
            await reconcile(notifications, force: true)
        } catch {
            guard active else { return }
            message = String(localized: "Test non completato. Attendi un minuto prima di riprovare.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }
}
