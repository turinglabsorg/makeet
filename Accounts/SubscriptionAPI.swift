import Foundation

public struct AccountEntitlement: Codable, Sendable {
    public let billingEnabled: Bool
    public let active: Bool
    public let productID: String
    public let expiresAt: Int64
    enum CodingKeys: String, CodingKey { case billingEnabled = "billing_enabled", active, productID = "product_id", expiresAt = "expires_at" }
    public init(billingEnabled: Bool, active: Bool, productID: String = "", expiresAt: Int64 = 0) {
        self.billingEnabled = billingEnabled; self.active = active; self.productID = productID; self.expiresAt = expiresAt
    }
}
