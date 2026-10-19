import Foundation
import Observation
import StoreKit

@MainActor @Observable final class SubscriptionStore {
    static let monthly = "org.turinglabs.makeet.plus.monthly"
    static let yearly = "org.turinglabs.makeet.plus.yearly"
    static let identifiers = Set([monthly, yearly])
    let userID: UUID
    private(set) var products: [Product] = []
    private(set) var entitlement: AccountEntitlement?
    private(set) var working = false
    private(set) var message: String?
    private var active = true
    private let purchasesAllowed: Bool
    private var listener: Task<Void, Never>?
    private let submit: (String) async throws -> AccountEntitlement
    private let fetch: () async throws -> AccountEntitlement
    var hasPlus: Bool { entitlement?.active == true && (entitlement?.expiresAt ?? 0) > Int64(Date().timeIntervalSince1970) }

    init(userID: UUID, api: AccountAPI) {
        self.userID = userID
        purchasesAllowed = ProductFeatures.subscriptionsAvailable
        submit = { try await api.submitTransaction($0, userID: userID) }
        fetch = { try await api.entitlement(userID: userID) }
        observe()
    }
    init(userID: UUID, submit: @escaping (String) async throws -> AccountEntitlement,
         fetch: @escaping () async throws -> AccountEntitlement) {
        self.userID = userID; self.submit = submit; self.fetch = fetch; purchasesAllowed = true
        observe()
    }
    private func observe() {
        guard purchasesAllowed else { return }
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, self.active, !Task.isCancelled else { break }
                do { try await self.receive(result) } catch { self.failure() }
            }
        }
    }
    func stop() { active = false; listener?.cancel(); listener = nil; entitlement = nil }
    func load() async {
        guard active, !working else { return }
        guard purchasesAllowed else {
            entitlement = AccountEntitlement(billingEnabled: false, active: false); products = []; return
        }
        working = true; defer { working = false }
        message = nil
        do {
            let next = try await fetch()
            guard active else { return }; entitlement = next
            guard next.billingEnabled else { products = []; return }
            products = try await Product.products(for: Self.identifiers).sorted { $0.price < $1.price }
            if next.billingEnabled {
                for await result in Transaction.currentEntitlements {
                    guard active else { return }
                    if case .verified(let transaction) = result, transaction.appAccountToken == userID,
                       Self.identifiers.contains(transaction.productID) { try await receive(result) }
                }
            }
            if products.isEmpty && next.billingEnabled {
                message = String(localized: "Le opzioni di acquisto non sono disponibili. Riprova dall’App Store più tardi.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            }
        } catch { failure() }
    }
    func purchase(_ product: Product) async {
        guard purchasesAllowed, active, !working, entitlement?.billingEnabled == true, Self.identifiers.contains(product.id) else { return }
        working = true; message = nil; defer { working = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(userID)]) {
            case .success(let result): try await receive(result)
            case .pending:
                message = String(localized: "Acquisto in attesa di approvazione. Nessuna funzione locale viene bloccata.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            case .userCancelled: break
            @unknown default: failure()
            }
        } catch StoreKitError.userCancelled { } catch { failure() }
    }
    func restore() async {
        guard purchasesAllowed, active, !working else { return }
        working = true; message = nil
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements { try await receive(result) }
            let next = try await fetch(); if active { entitlement = next }
            if !hasPlus { message = String(localized: "Nessun abbonamento attivo per questo account Makeet. Verifica di usare l’account con cui hai acquistato.", bundle: AppLanguage.bundle, locale: AppLanguage.locale) }
        } catch { failure() }
        working = false
    }
    private func receive(_ result: VerificationResult<Transaction>) async throws {
        guard active else { return }
        guard case .verified(let transaction) = result, Self.identifiers.contains(transaction.productID) else { return }
        guard transaction.appAccountToken == userID else {
            message = String(localized: "Questo acquisto è collegato a un altro account Makeet.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
            return
        }
        let next = try await submit(result.jwsRepresentation)
        guard active else { return }
        entitlement = next
        await transaction.finish()
    }
    private func failure() {
        guard active else { return }
        message = String(localized: "Acquisto o verifica non completati. I progressi restano disponibili; puoi riprovare o ripristinare gli acquisti.", bundle: AppLanguage.bundle, locale: AppLanguage.locale)
    }
}
