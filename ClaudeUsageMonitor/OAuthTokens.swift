import Foundation

struct OAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    /// True when the token expires within the next 5 minutes
    var isExpired: Bool {
        Date().addingTimeInterval(300) >= expiresAt
    }
}
