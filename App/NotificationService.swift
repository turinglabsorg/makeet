import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor protocol NotificationAuthorizationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

struct SystemNotificationAuthorization: NotificationAuthorizationClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

@MainActor @Observable final class NotificationService {
    static let shared = NotificationService()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var isRequesting = false
    private(set) var isRegistering = false
    private(set) var deviceToken: Data?
    private(set) var registrationFailed = false
    private(set) var permissionFailed = false
    private(set) var updateID = UUID()
    private(set) var pendingReceipts: [UUID] = (UserDefaults.standard.stringArray(forKey: "pushReceipts") ?? []).compactMap(UUID.init(uuidString:))
    var destination: String?

    private let client: any NotificationAuthorizationClient
    private let register: () -> Void

    convenience init() {
        self.init(client: SystemNotificationAuthorization(), register: NotificationService.registerWithAPNs)
    }

    init(client: any NotificationAuthorizationClient, register: @escaping () -> Void) {
        self.client = client
        self.register = register
    }

    var authorized: Bool {
        #if os(iOS)
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        #else
        authorization == .authorized || authorization == .provisional
        #endif
    }

    var permissionLabel: String {
        switch authorization {
        case .authorized: return String(localized: "Consentite", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .provisional: return String(localized: "Consentite con limitazioni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        #if os(iOS)
        case .ephemeral: return String(localized: "Consentite con limitazioni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        #endif
        case .denied: return String(localized: "Non consentite", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        case .notDetermined: return String(localized: "Da attivare", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        @unknown default: return String(localized: "Da verificare", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
        }
    }

    var deliveryLabel: String {
        if deviceToken != nil { return String(localized: "Dispositivo registrato · server da collegare", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if registrationFailed { return String(localized: "Registrazione non riuscita", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        if isRegistering { return String(localized: "Registrazione in corso", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        return String(localized: "Non collegato", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }

    func refresh() async {
        let previous = authorization
        authorization = await client.authorizationStatus()
        if !authorized {
            deviceToken = nil
            isRegistering = false
        } else if deviceToken == nil && !isRegistering && !registrationFailed {
            registerDevice()
        }
        if previous != authorization { updateID = UUID() }
    }

    func enable() async {
        guard !isRequesting else { return }
        isRequesting = true
        permissionFailed = false
        defer { isRequesting = false }
        authorization = await client.authorizationStatus()
        if authorization == .notDetermined {
            do { _ = try await client.requestAuthorization() }
            catch { permissionFailed = true }
            authorization = await client.authorizationStatus()
        }
        if authorized && deviceToken == nil { registerDevice() }
        updateID = UUID()
    }

    func registered(token: Data) {
        guard authorized else {
            deviceToken = nil
            isRegistering = false
            return
        }
        deviceToken = token
        registrationFailed = false
        isRegistering = false
        updateID = UUID()
    }

    func registrationDidFail() {
        deviceToken = nil
        registrationFailed = true
        isRegistering = false
        updateID = UUID()
    }

    func received(_ id: UUID) {
        guard !pendingReceipts.contains(id) else { return }
        pendingReceipts = Array((pendingReceipts + [id]).suffix(100))
        persistReceipts()
    }

    func acknowledged(_ id: UUID) {
        pendingReceipts.removeAll { $0 == id }
        persistReceipts()
    }

    private func persistReceipts() {
        UserDefaults.standard.set(pendingReceipts.map(\.uuidString), forKey: "pushReceipts")
        updateID = UUID()
    }

    private func registerDevice() {
        guard !isRegistering else { return }
        registrationFailed = false
        isRegistering = true
        register()
    }

    static func registerWithAPNs() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if let raw = notification.request.content.userInfo["notification_id"] as? String, let id = UUID(uuidString: raw) {
            Task { @MainActor in NotificationService.shared.received(id) }
        }
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        let id = (response.notification.request.content.userInfo["notification_id"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if let id { NotificationService.shared.received(id) }
            NotificationService.shared.destination = destination == "today" ? "today" : "plan"
            completionHandler()
        }
    }
}

#if os(iOS)
@MainActor final class PushAppDelegate: NSObject, UIApplicationDelegate {
    private let notifications = NotificationDelegate()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notifications
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.registered(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationService.shared.registrationDidFail()
    }
}
#else
@MainActor final class PushAppDelegate: NSObject, NSApplicationDelegate {
    private let notifications = NotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notifications
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.registered(token: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationService.shared.registrationDidFail()
    }
}
#endif

struct NotificationSettingsSection: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(AccountManager.self) private var account
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            LabeledContent(String(localized: "Permesso sul dispositivo", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: notifications.permissionLabel)
                .accessibilityIdentifier("notificationPermission")
            LabeledContent(String(localized: "Notifiche dal server", bundle: AppLanguage.bundle, locale: AppLanguage.locale), value: account.push?.deliveryLabel ?? notifications.deliveryLabel)
            if notifications.authorization == .denied {
                Button(String(localized: "Apri impostazioni notifiche", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { openSettings() }
            } else if !notifications.authorized || notifications.registrationFailed {
                Button(notifications.registrationFailed ? String(localized: "Riprova registrazione push", bundle: AppLanguage.bundle, locale: AppLanguage.locale) : String(localized: "Attiva notifiche", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
                    Task { await notifications.enable() }
                }
                .disabled(notifications.isRequesting || notifications.isRegistering)
                .accessibilityIdentifier("enableNotifications")
            } else {
                Button(String(localized: "Gestisci nelle impostazioni", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { openSettings() }
            }
            if notifications.permissionFailed {
                Text(String(localized: "Non è stato possibile richiedere il permesso. Riprova dalle impostazioni del dispositivo.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let push = account.push, notifications.authorized {
                PushPreferencesView(push: push, notifications: notifications)
            } else if account.user == nil {
                Text(String(localized: "Accedi per collegare le notifiche al tuo account.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text(String(localized: "Notifiche", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) } footer: {
            Text(String(localized: "I promemoria sono facoltativi e non contengono nomi o dati delle abitudini. La ricezione viene confermata quando l’app vede o apri la notifica.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(url) }
        #endif
    }
}

private struct PushPreferencesView: View {
    @Bindable var push: DevicePushService
    let notifications: NotificationService

    var body: some View {
        Toggle(String(localized: "Promemoria giornaliero", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isOn: $push.remindersEnabled)
            .onChange(of: push.remindersEnabled) { _, _ in Task { await push.reconcile(notifications, force: true) } }
        if push.remindersEnabled {
            DatePicker(String(localized: "Orario del promemoria", bundle: AppLanguage.bundle, locale: AppLanguage.locale), selection: $push.reminderTime, displayedComponents: .hourAndMinute)
                .onChange(of: push.reminderTime) { _, _ in Task { await push.reconcile(notifications, force: true) } }
            Text(String(localized: "All’orario scelto, un promemoria se sul servizio risulta almeno un’abitudine da completare. Usa il fuso orario di questo dispositivo.", bundle: AppLanguage.bundle, locale: AppLanguage.locale))
                .font(.caption).foregroundStyle(.secondary)
        }
        Button(String(localized: "Invia notifica di prova", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) {
            Task { await push.sendTest(notifications) }
        }
        .disabled(push.testing || notifications.deviceToken == nil)
        .accessibilityIdentifier("testPush")
        if let message = push.message {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}
