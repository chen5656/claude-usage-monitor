import Foundation

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
