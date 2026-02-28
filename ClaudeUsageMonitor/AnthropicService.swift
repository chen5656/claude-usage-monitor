import Foundation

struct AnthropicService {
    private let usageURL   = "https://api.anthropic.com/api/oauth/usage"
    private let betaHeader = "oauth-2025-04-20"

    func fetchUsage(tokens: OAuthTokens) async throws -> [UsageLimit] {
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

    // Response shape (actual API):
    // {
    //   "five_hour":   {"utilization": 21.0, "resets_at": "2026-02-28T04:00:00.451018+00:00"},
    //   "seven_day":   {"utilization": 15.0, "resets_at": "2026-03-06T13:00:00.451039+00:00"},
    //   "seven_day_sonnet": null,
    //   "seven_day_opus":   null,
    //   ...
    // }
    private func parse(_ data: Data) throws -> [UsageLimit] {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase

        // ISO 8601 with fractional seconds: "2026-02-28T04:00:00.451018+00:00"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dec.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            if let date = iso.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised date: \(str)")
        }

        struct LimitInfo: Decodable {
            let utilization: Double?
            let resetsAt: Date?
        }

        // Decode the top-level dictionary keys we care about.
        // Unknown/null keys (seven_day_cowork, iguana_necktie, extra_usage…) are simply ignored.
        struct UsageResponse: Decodable {
            let fiveHour: LimitInfo?
            let sevenDay: LimitInfo?
            let sevenDaySonnet: LimitInfo?
            let sevenDayOpus: LimitInfo?
        }

        let r = try dec.decode(UsageResponse.self, from: data)

        var limits: [UsageLimit] = []
        func add(_ info: LimitInfo?, type: RateLimitType) {
            guard let info, let pctRaw = info.utilization else { return }
            let pct = Int(pctRaw.rounded())
            limits.append(UsageLimit(type: type, percentage: pct, resetsAt: info.resetsAt))
        }

        add(r.fiveHour,       type: .fiveHour)
        add(r.sevenDay,       type: .sevenDay)
        add(r.sevenDaySonnet, type: .sevenDaySonnet)
        add(r.sevenDayOpus,   type: .sevenDayOpus)
        return limits
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
