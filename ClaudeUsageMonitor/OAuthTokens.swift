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

enum OAuthError: LocalizedError {
    case callbackFailed
    case stateMismatch
    case tokenExchangeFailed(String)
    case noToken
    case cancelled
    case browserOpenFailed

    var errorDescription: String? {
        switch self {
        case .callbackFailed:             return "OAuth callback failed."
        case .stateMismatch:              return "Security check failed. Please try again."
        case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
        case .noToken:                    return "Not logged in."
        case .cancelled:                  return "Login cancelled."
        case .browserOpenFailed:          return "Could not open browser. Try manually opening the login URL."
        }
    }
}
