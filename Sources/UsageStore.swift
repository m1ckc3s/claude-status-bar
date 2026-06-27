import Foundation

enum UsageEndpoints {
    // Force-unwrap is provably safe: these are compile-time-constant valid URLs.
    static let usage = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let messages = URL(string: "https://api.anthropic.com/v1/messages")!
    static let beta = "oauth-2025-04-20"
    static let anthropicVersion = "2023-06-01"
    static let userAgent = "claude-code/2.1.5"
}

final class UsageStore {
    private(set) var snapshot: UsageSnapshot?

    private let cacheURL: URL
    private let home: URL
    private let configDir: URL?
    private let session: URLSession
    private let now: () -> Date
    var minRefresh: TimeInterval // network floor; follows the user's refresh interval (main-thread only)

    private var lastFetch: Date = .distantPast
    private var inFlight = false

    init(cacheURL: URL,
         home: URL,
         configDir: URL?,
         session: URLSession = .shared,
         now: @escaping () -> Date = { Date() },
         minRefresh: TimeInterval = 300) {
        self.cacheURL = cacheURL
        self.home = home
        self.configDir = configDir
        self.session = session
        self.now = now
        self.minRefresh = minRefresh
        self.snapshot = UsageStore.loadCache(cacheURL)
    }

    // Honor `$CLAUDE_CONFIG_DIR`; else the standard ~/.claude location.
    private func claudeDir() -> URL { configDir ?? home.appendingPathComponent(".claude") }
    private func projectsDir() -> URL { claudeDir().appendingPathComponent("projects") }
}

extension UsageStore {
    // The network floor must sit BELOW the timer interval. `lastFetch` is stamped when a fetch
    // COMPLETES — a couple seconds after the tick that started it — so a tick exactly one interval
    // later lands a hair under a floor==interval and gets skipped, halving the real refresh rate
    // (a 2-min setting became ~4 min). A 30s margin clears that gap; force refreshes ignore it.
    static func floor(forIntervalMinutes minutes: Int) -> TimeInterval {
        max(30, TimeInterval(max(1, minutes) * 60 - 30))
    }

    static func shouldFetch(force: Bool, lastFetch: Date, now: Date, minRefresh: TimeInterval) -> Bool {
        if force { return true }
        return now.timeIntervalSince(lastFetch) >= minRefresh
    }
}

extension UsageStore {
    // Must be invoked on the main thread.
    func refresh(force: Bool, completion: @escaping (UsageSnapshot) -> Void) {
        // Floor only short-circuits when we have something to return.
        if let cached = snapshot,
           !UsageStore.shouldFetch(force: force, lastFetch: lastFetch, now: now(), minRefresh: minRefresh) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        if inFlight {
            let snap = snapshot ?? placeholder()
            DispatchQueue.main.async { completion(snap) }
            return
        }
        inFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let token = CredentialResolver.resolve(
                env: ProcessInfo.processInfo.environment,
                home: self.home,
                configDir: self.configDir,
                runSecurity: { SecurityKeychain.readToken(timeout: 8) }
            )

            guard let token else {
                // No token at all -> honest local totals, clearly a non-percentage source.
                let est = LocalUsageEstimator.estimate(projectsDir: self.projectsDir(), now: self.now())
                let snap = UsageSnapshot(session: nil, week: nil,
                                         localTokensToday: est.today, localTokensWeek: est.week,
                                         source: .signedOut, lastUpdated: self.now())
                self.complete(snap, persist: true, completion: completion)
                return
            }

            if token.isExpired(now: self.now()) {
                // We do not refresh the token ourselves in v1 -> "Re-login" state.
                let snap = UsageSnapshot(session: nil, week: nil,
                                         localTokensToday: nil, localTokensWeek: nil,
                                         source: .expired, lastUpdated: self.now())
                self.complete(snap, persist: false, completion: completion) // don't overwrite the on-disk last-good cache
                return
            }

            self.getUsage(token: token, completion: completion)
        }
    }

    // No cached snapshot yet (first launch, or the in-flight/error fallbacks) -> a minimal
    // signed-out shell so the widget still has something non-blank to show.
    private func placeholder() -> UsageSnapshot {
        UsageSnapshot(session: nil, week: nil, localTokensToday: nil, localTokensWeek: nil,
                      source: .signedOut, lastUpdated: now())
    }
}

extension UsageStore {
    private func getUsage(token: OAuthToken, completion: @escaping (UsageSnapshot) -> Void) {
        var req = URLRequest(url: UsageEndpoints.usage)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(UsageEndpoints.beta, forHTTPHeaderField: "anthropic-beta")
        req.setValue(UsageEndpoints.userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200, let data, let snap = UsageParser.parseUsageJSON(data, now: self.now()) {
                self.complete(snap, persist: true, completion: completion)
                return
            }
            // Endpoint disabled / unauthorized / rate-limited -> Messages-headers fallback.
            if [401, 404, 410, 429].contains(code) {
                self.postMessages(token: token, completion: completion)
                return
            }
            self.finishFallback(completion: completion) // transient error -> keep last-good
        }.resume()
    }

    private func postMessages(token: OAuthToken, completion: @escaping (UsageSnapshot) -> Void) {
        var req = URLRequest(url: UsageEndpoints.messages)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(UsageEndpoints.beta, forHTTPHeaderField: "anthropic-beta")
        req.setValue(UsageEndpoints.anthropicVersion, forHTTPHeaderField: "anthropic-version") // required
        req.setValue(UsageEndpoints.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: req) { [weak self] _, response, _ in
            guard let self else { return }
            if let http = response as? HTTPURLResponse,
               let snap = UsageParser.parseRateLimitHeaders(http.allHeaderFields, now: self.now()) {
                self.complete(snap, persist: true, completion: completion)
                return
            }
            self.finishFallback(completion: completion)
        }.resume()
    }

    // Off-main: persist only touches the immutable cacheURL + the passed-in value, so disk IO here
    // is safe; all mutable-state writes are deferred to the main thread.
    private func complete(_ snap: UsageSnapshot, persist: Bool, completion: @escaping (UsageSnapshot) -> Void) {
        if persist { UsageStore.saveCache(snap, to: cacheURL) }
        DispatchQueue.main.async {
            self.snapshot = snap
            self.lastFetch = self.now() // any network attempt counts toward the 5-min floor
            self.inFlight = false
            completion(snap)
        }
    }

    // Never blank: reuse last-good, else a minimal signed-out shell. Hops to main FIRST so the
    // `snapshot` read happens on the same thread that writes it (no cross-thread access).
    private func finishFallback(completion: @escaping (UsageSnapshot) -> Void) {
        DispatchQueue.main.async {
            let snap = self.snapshot ?? self.placeholder()
            self.lastFetch = self.now() // a failed attempt still counts toward the 5-min floor
            self.inFlight = false
            completion(snap)
        }
    }
}

extension UsageStore {
    private struct CachedWindow: Codable { var utilization: Double; var resetsAt: Date? }
    private struct CachedSnapshot: Codable {
        var session: CachedWindow?
        var week: CachedWindow?
        var localTokensToday: Int?
        var localTokensWeek: Int?
        var source: String
        var lastUpdated: Date
    }

    static func saveCache(_ snap: UsageSnapshot, to url: URL) {
        let dto = CachedSnapshot(
            session: snap.session.map { CachedWindow(utilization: $0.utilization, resetsAt: $0.resetsAt) },
            week: snap.week.map { CachedWindow(utilization: $0.utilization, resetsAt: $0.resetsAt) },
            localTokensToday: snap.localTokensToday,
            localTokensWeek: snap.localTokensWeek,
            source: snap.source.rawValue,
            lastUpdated: snap.lastUpdated
        )
        guard let data = try? JSONEncoder().encode(dto) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func loadCache(_ url: URL) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let dto = try? JSONDecoder().decode(CachedSnapshot.self, from: data) else { return nil }
        return UsageSnapshot(
            session: dto.session.map { WindowUsage(utilization: $0.utilization, resetsAt: $0.resetsAt) },
            week: dto.week.map { WindowUsage(utilization: $0.utilization, resetsAt: $0.resetsAt) },
            localTokensToday: dto.localTokensToday,
            localTokensWeek: dto.localTokensWeek,
            source: UsageSource(rawValue: dto.source) ?? .signedOut, // unknown/newer string -> safe default, keeps the rest of the snapshot
            lastUpdated: dto.lastUpdated
        )
    }
}
