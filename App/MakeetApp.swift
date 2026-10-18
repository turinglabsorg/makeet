import SwiftUI
import SwiftData
import GoogleSignIn
import StoreKit

@main struct MakeetApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #else
    @NSApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #endif
    @State private var account = AccountManager()
    @AppStorage(AppLanguage.preferenceKey, store: AppLanguage.defaults) private var language = "system"
    @AppStorage("onboardingVersion") private var onboardingVersion = 0
    @State private var onboardingStep = 0

    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           !ProcessInfo.processInfo.arguments.contains("--preserve-language") {
            AppLanguage.defaults.set("system", forKey: AppLanguage.preferenceKey)
        }
        if ProcessInfo.processInfo.arguments.contains("--onboarding"),
           !ProcessInfo.processInfo.arguments.contains("--preserve-onboarding") {
            UserDefaults.standard.set(0, forKey: "onboardingVersion")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = account.container {
                ArchiveHost(container: container) {
                    if onboardingRequired {
                        OnboardingView(step: $onboardingStep) {
                            do { try account.chooseLocalMode(); onboardingVersion = 2 }
                            catch { account.message = String(localized: "Archivio non disponibile", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
                        }
                    } else {
                        RootView()
                    }
                }.id(language).tint(Palette.accent)
                    .environment(\.locale, AppLanguage.locale)
                    .environment(NotificationService.shared)
                    .environment(account)
                    .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
                    .task {
                        #if DEBUG && targetEnvironment(simulator)
                        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                           ProcessInfo.processInfo.arguments.contains("--external-purchase-intent") {
                            account.requestPurchase(SubscriptionStore.monthly)
                            return
                        }
                        #endif
                        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
                        if #available(macOS 14.4, *) {
                            for await intent in PurchaseIntent.intents {
                                guard !Task.isCancelled else { break }
                                account.requestPurchase(intent.product.id)
                            }
                        }
                    }
            } else {
                ContentUnavailableView(String(localized: "Archivio non disponibile", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(account.startupError ?? String(localized: "Riapri l’app per riprovare.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)))
            }
        }
        #if os(macOS)
        .defaultSize(width: 540, height: 820)
        #endif
    }
    private var onboardingRequired: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") && !args.contains("--onboarding") { return false }
        return onboardingVersion < 2
    }
}

struct RootView: View {
    @Environment(AccountManager.self) private var account
    @Environment(NotificationService.self) private var notifications
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var calendar: CalendarService?
    @State private var selection = 0
    @State private var error: String?
    @State private var demoMode = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView(demoMode: $demoMode) }
                .tabItem { Label(String(localized: "Oggi", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { TrendsView() }
                .tabItem { Label(String(localized: "Andamento", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "chart.xyaxis.line") }.tag(1)
            NavigationStack { if account.canPlan { if let calendar { PlannerView(calendar: calendar) } } else { PlusView() } }
                .tabItem { Label(String(localized: "Il tuo piano", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "sparkles") }.tag(2)
            NavigationStack { if let calendar { CalendarOverview(calendar: calendar) } }
                .tabItem { Label(String(localized: "Calendario", bundle: AppLanguage.bundle, locale: AppLanguage.locale), systemImage: "calendar") }.tag(3)
        }
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: Binding(get: { account.requestedPurchaseID != nil }, set: { if !$0 { account.dismissPurchaseRequest() } })) {
            PlusView()
        }
        .task {
            calendar = CalendarService(scope: account.scope.key)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                demoMode = ProcessInfo.processInfo.arguments.contains("--demo")
            } else {
                demoMode = ((try? context.fetchCount(FetchDescriptor<Habit>(predicate: #Predicate { $0.isDemo }))) ?? 0) > 0
            }
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { await notifications.refresh() }
            if ProcessInfo.processInfo.arguments.contains("--demo"),
               !demoMode || ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                do { try DemoData.insert(in: context); demoMode = true }
                catch { self.error = error.localizedDescription }
            }
            await account.start()
            await account.push?.reconcile(notifications)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                if phase == .active {
                    await account.refreshAppleChallenge()
                    await account.sync?.synchronize()
                    await account.push?.reconcile(notifications)
                }
            }
        }
        .onChange(of: phase) { _, value in
            if value == .active {
                calendar?.refresh()
                Task { await account.sync?.synchronize() }
                Task { await account.profile?.refresh() }
                Task { await account.subscription?.load() }
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { Task { await notifications.refresh() } }
            }
        }
        .onChange(of: notifications.destination, initial: true) { _, value in
            if let value {
                selection = value == "today" ? 0 : 2
                notifications.destination = nil
            }
        }
        .task(id: notifications.updateID) {
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                await account.push?.reconcile(notifications)
            }
        }
        .onOpenURL { url in
            if url.host == "habit" { selection = 0 }
            if url.host == "plan" { selection = 2 }
        }
        .alert(String(localized: "Operazione non riuscita", bundle: AppLanguage.bundle, locale: AppLanguage.locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(String(localized: "OK", bundle: AppLanguage.bundle, locale: AppLanguage.locale)) { error = nil }
        } message: { Text(error ?? "") }
    }
}

enum DemoData {
    @MainActor static func insert(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Habit>()) == 0 else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -83, to: today)!
        let habits = [
            Habit(name: String(localized: "Bere acqua", bundle: AppLanguage.bundle, locale: AppLanguage.locale), symbol: "drop", colorIndex: 1, target: 8, step: 1, unit: String(localized: "bicchieri", bundle: AppLanguage.bundle, locale: AppLanguage.locale), preferredHour: 10, durationMinutes: 5, createdAt: start),
            Habit(name: String(localized: "Leggere", bundle: AppLanguage.bundle, locale: AppLanguage.locale), symbol: "book.closed", colorIndex: 0, target: 20, step: 5, unit: String(localized: "pagine", bundle: AppLanguage.bundle, locale: AppLanguage.locale), preferredHour: 19, durationMinutes: 20, createdAt: start),
            Habit(name: String(localized: "Muovermi", bundle: AppLanguage.bundle, locale: AppLanguage.locale), symbol: "figure.walk", colorIndex: 2, target: 30, step: 10, unit: String(localized: "minuti", bundle: AppLanguage.bundle, locale: AppLanguage.locale), preferredHour: 18, durationMinutes: 30, createdAt: start)
        ]
        for (index, habit) in habits.enumerated() {
            habit.isDemo = true
            context.insert(habit)
            for offset in 0..<84 {
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                let steps = offset == 0 ? [4, 2, 0][index] : ((offset * 7 + index * 3) % 11 < 8 ? Int(habit.target / habit.step) : index + 1)
                for step in 0..<steps {
                    let hour = (habit.preferredHour + step) % 22
                    let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                    context.insert(Activity(habitID: habit.id, amount: habit.step,
                        timestamp: offset == 0 ? min(time, Date()) : time, source: "demo"))
                }
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
