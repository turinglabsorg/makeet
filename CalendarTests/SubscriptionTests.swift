import XCTest
import StoreKit
import StoreKitTest
@testable import Makeet

final class SubscriptionTests: XCTestCase {
    @MainActor func testStoreKitPurchaseRestoreRefundExpiryAndAccountIsolation() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Isolated StoreKit test catalog is Simulator-only")
        #else
        executionTimeAllowance = 90
        NSLog("Makeet StoreKit test: initialize catalog")
        let session = try await isolatedSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let user = UUID()
        var accepted = 0
        var serverActive = false
        var serverTime = Date()
        let store = SubscriptionStore(userID: user, submit: { raw in
            XCTAssertFalse(raw.isEmpty); accepted += 1
            var active = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let value) = result, value.appAccountToken == user,
                   value.revocationDate == nil, (value.expirationDate ?? .distantPast) > serverTime { active = true }
            }
            serverActive = active
            return AccountEntitlement(billingEnabled: true, active: active, expiresAt: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970))
        }, fetch: { AccountEntitlement(billingEnabled: true, active: serverActive, expiresAt: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)) })
        defer { store.stop() }
        NSLog("Makeet StoreKit test: load products")
        await store.load()
        NSLog("Makeet StoreKit test: products loaded %ld", store.products.count)
        XCTAssertEqual(Set(store.products.map(\.id)), SubscriptionStore.identifiers)
        let monthly = try XCTUnwrap(store.products.first { $0.id == SubscriptionStore.monthly })
        XCTAssertFalse(store.hasPlus)
        NSLog("Makeet StoreKit test: purchase")
        await store.purchase(monthly)
        XCTAssertTrue(store.hasPlus); XCTAssertGreaterThan(accepted, 0)
        let other = SubscriptionStore(userID: UUID(), submit: { _ in XCTFail("Cross-account purchase submitted"); return AccountEntitlement(billingEnabled: true, active: true) }, fetch: { AccountEntitlement(billingEnabled: true, active: false) })
        await other.load(); XCTAssertFalse(other.hasPlus); other.stop()
        NSLog("Makeet StoreKit test: restore")
        await store.restore(); XCTAssertTrue(store.hasPlus)
        let beforeRenewal = accepted
        try session.forceRenewalOfSubscription(productIdentifier: SubscriptionStore.monthly)
        await eventually { accepted > beforeRenewal }
        NSLog("Makeet StoreKit test: refund")
        let transaction = try XCTUnwrap(session.allTransactions().last)
        try session.refundTransaction(identifier: transaction.identifier)
        await eventually { !store.hasPlus }
        XCTAssertFalse(store.hasPlus)
        session.clearTransactions(); serverActive = false
        await store.load(); await store.purchase(monthly); XCTAssertTrue(store.hasPlus)
        let expiring = try XCTUnwrap(session.allTransactions().last)
        let originalExpiry = try XCTUnwrap(expiring.expirationDate)
        try session.disableAutoRenewForTransaction(identifier: expiring.identifier)
        try session.expireSubscription(productIdentifier: SubscriptionStore.monthly)
        let expired = try XCTUnwrap(session.allTransactions().first { $0.identifier == expiring.identifier })
        XCTAssertLessThanOrEqual(try XCTUnwrap(expired.expirationDate), Date())
        serverTime = originalExpiry.addingTimeInterval(1)
        serverActive = false
        await store.load()
        await eventually { !store.hasPlus }
        XCTAssertFalse(store.hasPlus)
        store.stop(); XCTAssertFalse(store.hasPlus)
        #endif
    }
    @MainActor func testPerAccountPreviewPolicyNeverPurchases() async {
        let store = SubscriptionStore(userID: UUID(), submit: { _ in
            XCTFail("Free preview must not submit a transaction")
            return AccountEntitlement(billingEnabled: false, active: false)
        }, fetch: { AccountEntitlement(billingEnabled: false, active: false) })
        defer { store.stop() }
        XCTAssertNil(store.entitlement)
        await store.load()
        XCTAssertEqual(store.entitlement?.billingEnabled, false)
        XCTAssertFalse(store.hasPlus)
        XCTAssertTrue(store.products.isEmpty)
    }
    @MainActor func testCancelledPendingAndFailedPurchasesNeverUnlockPlus() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Isolated StoreKit test catalog is Simulator-only")
        #else
        executionTimeAllowance = 90
        let session = try await isolatedSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = SubscriptionStore(userID: UUID(), submit: { _ in
            XCTFail("Unsuccessful purchase must not be submitted")
            return AccountEntitlement(billingEnabled: true, active: false)
        }, fetch: { AccountEntitlement(billingEnabled: true, active: false) })
        defer { store.stop() }
        NSLog("Makeet StoreKit test: load unsuccessful-purchase products")
        await store.load()
        let product = try XCTUnwrap(store.products.first)
        NSLog("Makeet StoreKit test: simulate cancellation")
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        NSLog("Makeet StoreKit test: cancellation configured; purchase")
        await store.purchase(product); XCTAssertFalse(store.hasPlus)
        NSLog("Makeet StoreKit test: simulate failure")
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        NSLog("Makeet StoreKit test: failure configured; purchase")
        await store.purchase(product); XCTAssertFalse(store.hasPlus); XCTAssertNotNil(store.message)
        NSLog("Makeet StoreKit test: simulate pending purchase")
        try await session.setSimulatedError(nil, forAPI: .purchase)
        session.askToBuyEnabled = true
        await store.purchase(product); XCTAssertFalse(store.hasPlus); XCTAssertNotNil(store.message)
        store.stop()
        let pending = session.allTransactions().filter(\.pendingAskToBuyConfirmation)
        XCTAssertFalse(pending.isEmpty)
        for transaction in pending { try session.declineAskToBuyTransaction(identifier: transaction.identifier) }
        session.askToBuyEnabled = false
        #endif
    }
    @MainActor private func isolatedSession() async throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MakeetTests", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let preflight = try await session.buyProduct(identifier: SubscriptionStore.monthly, options: [.appAccountToken(UUID())])
        XCTAssertEqual(preflight.environment, .xcode)
        await preflight.finish()
        session.clearTransactions()
        return session
    }
    @MainActor private func eventually(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition())
    }
}
