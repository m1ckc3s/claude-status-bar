import Foundation

// Fetches Claude subscription rate-limit utilization (5h / 7d windows) — the same numbers
// as the `/usage` command — from the OAuth usage endpoint. The access token is read fresh
// from ~/.claude/.credentials.json on every call, so when Claude Code rotates the token we
// pick it up automatically. Read-only: the token never leaves this machine except as the
// Bearer auth on the request to Anthropic's own API.
final class UsageFetcher {
    private(set) var fiveHour: Int?         // 5-hour window utilization, whole percent
    private(set) var sevenDay: Int?         // 7-day window utilization, whole percent
    private(set) var fiveHourReset: Date?   // when the 5-hour window resets
    private(set) var sevenDayReset: Date?   // when the 7-day window resets
    var onUpdate: (() -> Void)?             // called on the main thread after a successful fetch

    private let endpoint = "https://api.anthropic.com/api/oauth/usage"
    private let credsPath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/.credentials.json")

    // resets_at looks like "2026-07-14T11:59:59.649659+00:00"; some payloads omit the
    // fractional seconds, so try both.
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private func parseDate(_ s: String) -> Date? { Self.isoFrac.date(from: s) ?? Self.isoPlain.date(from: s) }

    private func accessToken() -> String? {
        guard let data = FileManager.default.contents(atPath: credsPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    // A window looks like { "utilization": 62.0, "resets_at": "…", … }.
    private func parseWindow(_ w: [String: Any]?) -> (percent: Int?, reset: Date?) {
        guard let w = w else { return (nil, nil) }
        var pct: Int?
        if let u = w["utilization"] as? Double { pct = Int(u.rounded()) }
        else if let u = w["utilization"] as? Int { pct = u }
        let reset = (w["resets_at"] as? String).flatMap(parseDate)
        return (pct, reset)
    }

    func refresh() {
        guard let token = accessToken(), let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let five = self.parseWindow(obj["five_hour"] as? [String: Any])
            let seven = self.parseWindow(obj["seven_day"] as? [String: Any])
            guard five.percent != nil || seven.percent != nil else { return }  // ignore 401/error bodies
            DispatchQueue.main.async {
                self.fiveHour = five.percent;   self.fiveHourReset = five.reset
                self.sevenDay = seven.percent;  self.sevenDayReset = seven.reset
                self.onUpdate?()
            }
        }.resume()
    }

    // MARK: formatting

    // "7:00 PM" — for windows that reset within a day (the 5-hour one).
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
    // "Sun, Jul 20" — for windows days out (the 7-day one).
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()

    // Compact label for the menu bar, e.g. "5h 62%" (5-hour window only; 7-day lives in the
    // dropdown). nil until the first fetch lands.
    var barText: String? {
        guard let f = fiveHour else { return nil }
        return "5h \(f)%"
    }

    // Dropdown detail rows, e.g. "5-hour:  68%  ·  resets 7:00 PM".
    var fiveHourDetail: String? {
        guard let p = fiveHour else { return nil }
        let r = fiveHourReset.map { "  ·  resets \(Self.timeFmt.string(from: $0))" } ?? ""
        return "5-hour:  \(p)%\(r)"
    }
    var sevenDayDetail: String? {
        guard let p = sevenDay else { return nil }
        let r = sevenDayReset.map { "  ·  resets \(Self.dayFmt.string(from: $0))" } ?? ""
        return "7-day:  \(p)%\(r)"
    }
}
