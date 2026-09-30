import Foundation

public struct GammaEngageConfig: Sendable {
    /// Your GammaEngage API origin, e.g. `https://api.example.com`.
    public let baseURL: String
    /// The brand (tenant) id.
    public let brandId: String
    /// The brand's API key, sent as `X-Tenant-API-Key`.
    public let apiKey: String
    /// The API key's HMAC secret. Optional — when set, every request is signed.
    public let hmacSecret: String?
    /// Print SDK activity to the console.
    public let debug: Bool

    public init(baseURL: String, brandId: String, apiKey: String, hmacSecret: String? = nil, debug: Bool = false) {
        self.baseURL = baseURL
        self.brandId = brandId
        self.apiKey = apiKey
        self.hmacSecret = hmacSecret
        self.debug = debug
    }
}
