import Foundation

// String-backed so the cache encodes/decodes via rawValue (case names == the strings persisted).
enum UsageSource: String { case official, ratelimitHeaders, signedOut, expired }

// utilization is ALWAYS 0...100 after parsing (header path multiplies 0.0–1.0 by 100).
struct WindowUsage: Equatable {
    var utilization: Double
    var resetsAt: Date?
}

struct UsageSnapshot: Equatable {
    var session: WindowUsage?      // five_hour
    var week: WindowUsage?         // seven_day
    var localTokensToday: Int?     // set on the no-token (.signedOut) path
    var localTokensWeek: Int?
    var source: UsageSource
    var lastUpdated: Date
}

enum UsageLevel { case safe, warn, critical }     // used%: <50 safe, 50..<80 warn, >=80 critical

enum UsageStatus {
    static func level(_ utilization: Double) -> UsageLevel {
        switch utilization {
        case ..<50:  return .safe
        case ..<80:  return .warn
        default:     return .critical
        }
    }
}
