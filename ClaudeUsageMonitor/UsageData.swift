import Foundation

enum RateLimitType: String {
    case fiveHour        = "five_hour"
    case sevenDay        = "seven_day"
    case sevenDaySonnet  = "seven_day_sonnet"
    case sevenDayOpus    = "seven_day_opus"
    case overage         = "overage"
    case unknown         = ""

    var displayName: String {
        switch self {
        case .fiveHour:       return "Session"
        case .sevenDay:       return "Weekly"
        case .sevenDaySonnet: return "Sonnet Weekly"
        case .sevenDayOpus:   return "Opus Weekly"
        case .overage:        return "Extra"
        case .unknown:        return "Usage"
        }
    }
}

struct UsageLimit {
    let type: RateLimitType
    /// 0–100
    let percentage: Int
    let resetsAt: Date?
}
