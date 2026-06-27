import Foundation

enum UsageParser {
    // /oauth/usage body: { "five_hour": {utilization 0–100, resets_at ISO-8601}, "seven_day": {...} }
    static func parseUsageJSON(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let session = jsonWindow(obj["five_hour"])
        let week = jsonWindow(obj["seven_day"])
        guard session != nil || week != nil else { return nil }
        return UsageSnapshot(session: session, week: week,
                             localTokensToday: nil, localTokensWeek: nil,
                             source: .official, lastUpdated: now)
    }

    // Messages-API rate-limit headers: unified-5h/7d-utilization are 0.0–1.0 (->*100);
    // -reset are Unix seconds.
    static func parseRateLimitHeaders(_ headers: [AnyHashable: Any], now: Date) -> UsageSnapshot? {
        let lower = normalize(headers)
        let session = headerWindow(lower,
                                   utilKey: "anthropic-ratelimit-unified-5h-utilization",
                                   resetKey: "anthropic-ratelimit-unified-5h-reset")
        let week = headerWindow(lower,
                                utilKey: "anthropic-ratelimit-unified-7d-utilization",
                                resetKey: "anthropic-ratelimit-unified-7d-reset")
        guard session != nil || week != nil else { return nil }
        return UsageSnapshot(session: session, week: week,
                             localTokensToday: nil, localTokensWeek: nil,
                             source: .ratelimitHeaders, lastUpdated: now)
    }

    // Fractional seconds first; the API has omitted them before, so fall back to plain
    // internet-date-time (a single hard formatter would silently fail on the other shape).
    // Cached statics: this runs once per transcript line in the local-estimate scan and
    // ISO8601DateFormatter init is expensive. Also the single canonical ISO-8601 parser —
    // LocalUsageEstimator reuses it rather than carrying a duplicate.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parseResetDate(_ s: String) -> Date? {
        if let d = isoFractional.date(from: s) { return d }
        return isoPlain.date(from: s)
    }

    // MARK: - helpers

    private static func jsonWindow(_ any: Any?) -> WindowUsage? {
        guard let dict = any as? [String: Any],
              let util = (dict["utilization"] as? NSNumber)?.doubleValue else { return nil }
        let resets = (dict["resets_at"] as? String).flatMap(parseResetDate)
        return WindowUsage(utilization: clamp(util), resetsAt: resets)
    }

    private static func headerWindow(_ lower: [String: String], utilKey: String, resetKey: String) -> WindowUsage? {
        guard let utilStr = lower[utilKey], let util = Double(utilStr) else { return nil }
        let resets = lower[resetKey].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
        return WindowUsage(utilization: clamp(util * 100), resetsAt: resets)
    }

    private static func normalize(_ headers: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers {
            guard let key = k as? String else { continue }
            out[key.lowercased()] = "\(v)"
        }
        return out
    }

    private static func clamp(_ v: Double) -> Double { min(100, max(0, v)) }
}
