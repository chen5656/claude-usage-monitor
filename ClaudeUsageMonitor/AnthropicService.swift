import Foundation

struct AnthropicService {
    private let baseURL = "https://api.anthropic.com"
    private let anthropicVersion = "2023-06-01"

    // Fetch usage data by calling the models endpoint and reading rate-limit headers.
    // The headers provide the per-window token quota and remaining tokens.
    func fetchUsage(apiKey: String) async throws -> UsageData {
        let url = URL(string: "\(baseURL)/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return parseRateLimitHeaders(from: http)
        case 401:
            throw AnthropicError.invalidAPIKey
        case 429:
            throw AnthropicError.rateLimited
        default:
            throw AnthropicError.serverError(statusCode: http.statusCode)
        }
    }

    func validateAPIKey(_ apiKey: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }

        if http.statusCode == 401 { throw AnthropicError.invalidAPIKey }
        return http.statusCode == 200
    }

    private func parseRateLimitHeaders(from response: HTTPURLResponse) -> UsageData {
        let headers = response.allHeaderFields

        let tokensLimit = intHeader("anthropic-ratelimit-tokens-limit", from: headers)
        let tokensRemaining = intHeader("anthropic-ratelimit-tokens-remaining", from: headers)
        let resetString = headers["anthropic-ratelimit-tokens-reset"] as? String

        let tokensUsed = max(0, tokensLimit - tokensRemaining)
        let percentage: Double = tokensLimit > 0
            ? Double(tokensUsed) / Double(tokensLimit) * 100.0
            : 0

        var resetDate: Date?
        if let s = resetString {
            resetDate = ISO8601DateFormatter().date(from: s)
        }

        return UsageData(
            tokensUsed: tokensUsed,
            tokensLimit: tokensLimit,
            tokensRemaining: tokensRemaining,
            usagePercentage: percentage,
            resetAt: resetDate
        )
    }

    private func intHeader(_ key: String, from headers: [AnyHashable: Any]) -> Int {
        if let v = headers[key] as? String { return Int(v) ?? 0 }
        return 0
    }
}

enum AnthropicError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case rateLimited
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:      return "Invalid API key. Please check your settings."
        case .invalidResponse:    return "Invalid response from server."
        case .rateLimited:        return "Rate limited. Please try again later."
        case .serverError(let c): return "Server error: \(c)"
        }
    }
}
