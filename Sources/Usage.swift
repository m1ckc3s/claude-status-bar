import Foundation

// One rate-limit window as reported by the usage endpoint's `limits[]` array.
struct UsageLimit {
    let label: String     // display name: "Session", "Weekly", "Weekly (Opus)"
    let group: String     // "session" | "weekly"
    let percent: Int      // utilization, whole percent
    let reset: Date?      // when this window resets (nil if not applicable to the plan)
    let severity: String  // "normal" | "warning" | "critical" — from the API
}

// Fetches Claude subscription rate-limit utilization from the OAuth usage endpoint — the same
// data as the `/usage` command. Reads the `limits[]` array and labels each window by its
// semantic `group`/`kind` (Session / Weekly), rather than hardcoding plan-specific durations
// like "5h"/"7d", so it stays correct across Pro and Max (incl. Max's model-scoped weekly caps).
//
// The access token is read fresh on every call — from the macOS Keychain first, falling back to
// ~/.claude/.credentials.json — so token rotations AND account switches are picked up
// automatically. (Newer Claude Code treats the Keychain item as authoritative and leaves the
// file as a stale cache that only re-syncs on a CLI session start; reading the Keychain keeps us
// on the active account.) Read-only: the token never leaves this machine except as the Bearer
// auth on the request to Anthropic's own API.
final class UsageFetcher {
    private(set) var limits: [UsageLimit] = []
    var onUpdate: (() -> Void)?   // called on the main thread after a successful fetch

    private let endpoint = "https://api.anthropic.com/api/oauth/usage"
    private let credsPath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/.credentials.json")

    // resets_at looks like "2026-07-14T12:00:00.084096+00:00"; some payloads omit the
    // fractional seconds, so try both.
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private func parseDate(_ s: String) -> Date? { Self.isoFrac.date(from: s) ?? Self.isoPlain.date(from: s) }

    private let keychainService = "Claude Code-credentials"

    // Both sources store the same JSON shape ({ "claudeAiOauth": { "accessToken": … } }); some
    // hold the bare token instead, so accept either.
    private func tokenFromBlob(_ data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = obj["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           raw.hasPrefix("sk-ant-") {
            return raw
        }
        return nil
    }

    // Read the token via /usr/bin/security rather than SecItemCopyMatching directly: the CLI is
    // Apple-signed and already trusted in the item's ACL, so it reads without the keychain-access
    // prompt that an unsigned/ad-hoc app triggers. This is also what follows account switches (the
    // active account's token lives in the Keychain; the file is only a stale cache).
    private func keychainToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return tokenFromBlob(data)
    }

    private func fileToken() -> String? {
        guard let data = FileManager.default.contents(atPath: credsPath) else { return nil }
        return tokenFromBlob(data)
    }

    private func accessToken() -> String? { keychainToken() ?? fileToken() }

    private func parseLimits(_ arr: [[String: Any]]) -> [UsageLimit] {
        arr.compactMap { l in
            guard let group = l["group"] as? String else { return nil }
            let kind = l["kind"] as? String ?? ""
            let percent = (l["percent"] as? Int) ?? (l["percent"] as? Double).map { Int($0.rounded()) } ?? 0
            let reset = (l["resets_at"] as? String).flatMap(parseDate)
            let severity = l["severity"] as? String ?? "normal"

            var label: String
            switch group {
            case "session": label = "Session"
            case "weekly":
                label = "Weekly"
                // A model-scoped weekly cap (Max plans) carries the model under scope.model.
                if kind == "weekly_scoped",
                   let scope = l["scope"] as? [String: Any],
                   let model = scope["model"] as? [String: Any],
                   let name = model["display_name"] as? String {
                    label = "Weekly (\(name))"
                }
            default: label = group.prefix(1).uppercased() + group.dropFirst()
            }
            return UsageLimit(label: label, group: group, percent: percent, reset: reset, severity: severity)
        }
    }

    func refresh() {
        guard let token = accessToken(), let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }
            DispatchQueue.main.async { if self.apply(data) { self.onUpdate?() } }
        }.resume()
    }

    // Parses a usage response and, if it carries any limits, stores them. Returns whether it
    // updated — a throttled/error body (empty or missing `limits`) is ignored so the last good
    // values stay put. Split out from refresh() so it can be exercised without a live call.
    @discardableResult
    func apply(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["limits"] as? [[String: Any]] else { return false }
        let parsed = parseLimits(raw)
        guard !parsed.isEmpty else { return false }
        limits = parsed
        return true
    }

    // MARK: formatting

    // "7:00 PM" for windows resetting within a day; "Sun, Jul 20" for ones further out.
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()
    private static func resetStr(_ d: Date) -> String {
        d.timeIntervalSinceNow < 24 * 3600 ? timeFmt.string(from: d) : dayFmt.string(from: d)
    }

    // Windows worth showing: an active window has a reset time or non-zero usage. This drops
    // inapplicable entries (e.g. a Pro plan's empty model-scoped weekly cap).
    private var displayLimits: [UsageLimit] { limits.filter { $0.reset != nil || $0.percent > 0 } }

    // Compact menu-bar label — the session window only, e.g. "Session 91%". nil until first fetch.
    var barText: String? {
        guard let s = limits.first(where: { $0.group == "session" }) else { return nil }
        return "\(s.label) \(s.percent)%"
    }

    // Dropdown detail rows, e.g. "Session:  91%  ·  resets 7:00 PM".
    var detailLines: [String] {
        displayLimits.map { l in
            let r = l.reset.map { "  ·  resets \(Self.resetStr($0))" } ?? ""
            return "\(l.label):  \(l.percent)%\(r)"
        }
    }
}
