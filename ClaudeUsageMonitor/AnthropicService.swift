import Foundation

struct AnthropicService {
    private let usageURL    = "https://api.anthropic.com/api/oauth/usage"
    private let betaHeader  = "oauth-2025-04-20"

    func fetchUsage(tokens: OAuthTokens) async throws -> [UsageLimit] {
        // Refresh the access token if it is (nearly) expired
        var tok = tokens
        if tokens.isExpired {
            tok = try await OAuthManager.shared.refresh(tokens)
            _ = KeychainManager.shared.saveTokens(tok)
        }

        var req = URLRequest(url: URL(string: usageURL)!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(tok.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else { throw AnthropicError.invalidResponse }

        switch http.statusCode {
        case 200:  return try parse(data)
        case 401:  throw AnthropicError.invalidToken
        case 429:  throw AnthropicError.rateLimited
        default:   throw AnthropicError.serverError(statusCode: http.statusCode)
        }
    }

    // MARK: - Parsing

    private func parse(_ data: Data) throws -> [UsageLimit] {
        // The API may return a top-level array, or {"limits": [...]}
        if let arr = try? JSONDecoder().decode([LimitDTO].self, from: data) {
            return arr.map(\.toUsageLimit)
        }
        struct Wrapper: Decodable { let limits: [LimitDTO]? }
        if let w = try? JSONDecoder().decode(Wrapper.self, from: data) {
            return (w.limits ?? []).map(\.toUsageLimit)
        }
        throw AnthropicError.decodingError
    }

    private struct LimitDTO: Decodable {
        let rateLimitType: String?
        // The API returns utilization as 0–100 (Claude CLI renders it with Math.floor(H)+"% used")
        let utilization:   Double?
        let resetsAt:      Double?   // Unix timestamp in seconds

        var toUsageLimit: UsageLimit {
            let type = RateLimitType(rawValue: rateLimitType ?? "") ?? .unknown
            let pct: Int
            if let u = utilization {
                // Guard: if value is in 0–1 range treat as fraction, else already 0–100
                pct = u <= 1.5 ? Int((u * 100).rounded()) : Int(u.rounded())
            } else {
                pct = 0
            }
            let reset = resetsAt.map { Date(timeIntervalSince1970: $0) }
            return UsageLimit(type: type, percentage: pct, resetsAt: reset)
        }
    }
}

enum AnthropicError: LocalizedError {
    case invalidToken
    case invalidResponse
    case rateLimited
    case serverError(statusCode: Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidToken:       return "Session expired. Please log in again."
        case .invalidResponse:    return "Invalid response from server."
        case .rateLimited:        return "Rate limited. Please try again later."
        case .serverError(let c): return "Server error: \(c)"
        case .decodingError:      return "Failed to parse usage data."
        }
    }
}
