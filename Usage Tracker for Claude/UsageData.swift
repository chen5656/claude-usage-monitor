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

enum DemoModeStore {
    private static let key = "demoModeEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }

    static func sampleLimits(now: Date = Date()) -> [UsageLimit] {
        let minuteSeed = Int(now.timeIntervalSince1970 / 60)

        let sessionPct = 25 + (minuteSeed % 60)
        let weeklyPct = min(95, 40 + (minuteSeed % 45))
        let sonnetPct = min(95, 15 + ((minuteSeed * 3) % 70))
        let opusPct = min(95, 8 + ((minuteSeed * 5) % 60))

        return [
            UsageLimit(type: .fiveHour, percentage: sessionPct, resetsAt: next5HourBoundary(from: now)),
            UsageLimit(type: .sevenDay, percentage: weeklyPct, resetsAt: nextWeeklyBoundary(from: now)),
            UsageLimit(type: .sevenDaySonnet, percentage: sonnetPct, resetsAt: nextWeeklyBoundary(from: now, dayOffset: 1)),
            UsageLimit(type: .sevenDayOpus, percentage: opusPct, resetsAt: nextWeeklyBoundary(from: now, dayOffset: 2))
        ]
    }

    private static func next5HourBoundary(from now: Date) -> Date {
        let interval: TimeInterval = 5 * 60 * 60
        let next = ceil(now.timeIntervalSince1970 / interval) * interval
        return Date(timeIntervalSince1970: next)
    }

    private static func nextWeeklyBoundary(from now: Date, dayOffset: Int = 0) -> Date {
        let cal = Calendar.current
        // Next Monday at 00:00 local time
        var next = cal.nextDate(after: now,
                                matching: DateComponents(hour: 0, minute: 0, second: 0, weekday: 2),
                                matchingPolicy: .nextTime,
                                direction: .forward) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        if dayOffset > 0 {
            next = cal.date(byAdding: .day, value: dayOffset, to: next) ?? next
        }
        return next
    }
}
