import XCTest
import StoreKit
import StoreKitTest

final class StoreKitEnvironmentTests: XCTestCase {
    @MainActor func testConfigureCatalogBeforePurchaseTestHostLaunch() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Isolated StoreKit test catalog is Simulator-only")
        #else
        executionTimeAllowance = 60
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MakeetTests", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: "org.turinglabs.makeet.plus.monthly", options: [.appAccountToken(UUID())])
        let claims = try XCTUnwrap(try JSONSerialization.jsonObject(with: transaction.jsonRepresentation) as? [String: Any])
        XCTAssertEqual(claims["bundleId"] as? String, Bundle.main.bundleIdentifier)
        XCTAssertEqual(transaction.environment, .xcode)
        await transaction.finish()
        #endif
    }
}
