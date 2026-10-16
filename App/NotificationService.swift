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
        case .authorized: return String(localized: "Consentite")
        case .provisional: return String(localized: "Consentite con limitazioni")
        #if os(iOS)
        case .ephemeral: return String(localized: "Consentite con limitazioni")
        #endif
        case .denied: return String(localized: "Non consentite")
        case .notDetermined: return String(localized: "Da attivare")
        @unknown default: return String(localized: "Da verificare")
        }
    }

    var deliveryLabel: String {
        if deviceToken != nil { return String(localized: "Dispositivo registrato · server da collegare") }
        if registrationFailed { return String(localized: "Registrazione non riuscita") }
        if isRegistering { return String(localized: "Registrazione in corso") }
        return String(localized: "Non collegato")
    }

    func refresh() async {
        authorization = await client.authorizationStatus()
        if !authorized {
            deviceToken = nil
            isRegistering = false
        } else if deviceToken == nil && !isRegistering && !registrationFailed {
            registerDevice()
        }
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
    }

    func registrationDidFail() {
        deviceToken = nil
        registrationFailed = true
        isRegistering = false
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
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        Task { @MainActor in
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            LabeledContent(String(localized: "Permesso sul dispositivo"), value: notifications.permissionLabel)
                .accessibilityIdentifier("notificationPermission")
            LabeledContent(String(localized: "Notifiche dal server"), value: notifications.deliveryLabel)
            if notifications.authorization == .denied {
                Button(String(localized: "Apri impostazioni notifiche")) { openSettings() }
            } else if !notifications.authorized || notifications.registrationFailed {
                Button(notifications.registrationFailed ? String(localized: "Riprova registrazione push") : String(localized: "Attiva notifiche")) {
                    Task { await notifications.enable() }
                }
                .disabled(notifications.isRequesting || notifications.isRegistering)
                .accessibilityIdentifier("enableNotifications")
            } else {
                Button(String(localized: "Gestisci nelle impostazioni")) { openSettings() }
            }
            if notifications.permissionFailed {
                Text(String(localized: "Non è stato possibile richiedere il permesso. Riprova dalle impostazioni del dispositivo."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text(String(localized: "Notifiche")) } footer: {
            Text(String(localized: "Scegli tu quando consentire le notifiche. L’invio dei promemoria richiede anche il collegamento al servizio Makeet, ancora in configurazione."))
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
