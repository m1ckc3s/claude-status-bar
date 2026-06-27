import Foundation

private var selfTestFailures = 0

// Prints PASS/FAIL per check and tracks failures for the final tally.
func expect(_ ok: Bool, _ msg: String) {
    if ok {
        print("PASS: \(msg)")
    } else {
        selfTestFailures += 1
        print("FAIL: \(msg)")
    }
}

func runSelfTests() -> Bool {
    selfTestFailures = 0
    testUsageStatus()
    testUsageParser()
    selfTestCredentials()
    selfTestLocalEstimate()
    runUsageStoreSelfTests()
    print(selfTestFailures == 0 ? "ALL PASS" : "\(selfTestFailures) FAILED")
    return selfTestFailures == 0
}

private func testUsageStatus() {
    // level thresholds: <50 safe, 50..<80 warn, >=80 critical (boundaries)
    expect(UsageStatus.level(0)    == .safe,     "level 0 -> safe")
    expect(UsageStatus.level(49.9) == .safe,     "level 49.9 -> safe")
    expect(UsageStatus.level(50)   == .warn,     "level 50 -> warn")
    expect(UsageStatus.level(79.9) == .warn,     "level 79.9 -> warn")
    expect(UsageStatus.level(80)   == .critical, "level 80 -> critical")
    expect(UsageStatus.level(100)  == .critical, "level 100 -> critical")
}

private func testUsageParser() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    // 0–100 JSON path: five_hour has fractional-second reset, seven_day has none.
    let jsonText = """
    {"five_hour":{"utilization":42,"resets_at":"2026-06-26T18:30:00.000Z"},
     "seven_day":{"utilization":67,"resets_at":"2026-06-29T09:00:00Z"}}
    """
    let json = jsonText.data(using: .utf8) ?? Data()
    let snap = UsageParser.parseUsageJSON(json, now: now)
    expect(snap?.source == .official, "JSON source -> official")
    expect((snap?.session?.utilization ?? -1) == 42, "JSON five_hour util -> 42")
    expect((snap?.week?.utilization ?? -1) == 67, "JSON seven_day util -> 67")
    expect(snap?.session?.resetsAt != nil, "JSON fractional resets_at parsed")
    expect(snap?.week?.resetsAt != nil, "JSON non-fractional resets_at parsed")
    expect(snap?.lastUpdated == now, "JSON lastUpdated stamped with now")

    // 0.0–1.0 header path: must *100 to match the JSON scale; resets are Unix seconds.
    let headers: [AnyHashable: Any] = [
        "Anthropic-Ratelimit-Unified-5h-Utilization": "0.42",   // mixed case on purpose
        "anthropic-ratelimit-unified-5h-reset": "1700001800",
        "anthropic-ratelimit-unified-7d-utilization": "0.67",
        "anthropic-ratelimit-unified-7d-reset": "1700100000",
    ]
    let hsnap = UsageParser.parseRateLimitHeaders(headers, now: now)
    expect(hsnap?.source == .ratelimitHeaders, "header source -> ratelimitHeaders")
    expect(abs((hsnap?.session?.utilization ?? -1) - 42) < 1e-6, "header 5h 0.42 -> 42 (case-insensitive)")
    expect(abs((hsnap?.week?.utilization ?? -1) - 67) < 1e-6, "header 7d 0.67 -> 67")
    expect(hsnap?.session?.resetsAt == Date(timeIntervalSince1970: 1_700_001_800), "header unix reset parsed")

    // same-scale proof: header path and JSON path agree on the session window.
    let same = abs((hsnap?.session?.utilization ?? -1) - (snap?.session?.utilization ?? -2)) < 1e-6
    expect(same, "JSON 0–100 and header 0–1 paths land on the SAME scale")

    // parseResetDate: with fractional, without fractional, and a bad string.
    expect(UsageParser.parseResetDate("2026-06-26T18:30:00.000Z") != nil, "resetDate with fractional seconds")
    expect(UsageParser.parseResetDate("2026-06-26T18:30:00Z") != nil, "resetDate without fractional seconds")
    expect(UsageParser.parseResetDate("not-a-date") == nil, "resetDate bad string -> nil")
}

func selfTestCredentials() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("selftest-cred-\(UUID().uuidString)")
    let claude = root.appendingPathComponent(".claude")
    try? fm.createDirectory(at: claude, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    // expiresAt in the past (epoch ms): Nov 2023, safely before any test run.
    let pastMs = 1_700_000_000_000
    let json = "{\"claudeAiOauth\":{\"accessToken\":\"file-token-abc\",\"expiresAt\":\(pastMs)}}"
    try? json.data(using: .utf8)?.write(to: claude.appendingPathComponent(".credentials.json"))

    let now = Date()

    // File token is resolved when no env override is present.
    let fileTok = CredentialResolver.resolve(env: [:], home: root, configDir: nil, runSecurity: { nil })
    expect(fileTok?.accessToken == "file-token-abc", "credentials: file token resolved")

    // A past expiresAt (ms) marks the token expired.
    expect(fileTok?.isExpired(now: now) == true, "credentials: past expiresAt -> isExpired true")

    // Env override takes precedence over the file.
    let envTok = CredentialResolver.resolve(env: ["CLAUDE_CODE_OAUTH_TOKEN": "env-token-xyz"],
                                            home: root, configDir: nil, runSecurity: { nil })
    expect(envTok?.accessToken == "env-token-xyz", "credentials: env token preferred over file")

    // A future expiry reads as not expired; a missing expiry is never expired.
    expect(OAuthToken(accessToken: "t", expiresAt: now.addingTimeInterval(3600)).isExpired(now: now) == false,
           "credentials: future expiresAt -> not expired")
    expect(OAuthToken(accessToken: "t", expiresAt: nil).isExpired(now: now) == false,
           "credentials: no expiresAt -> not expired")
}

func selfTestLocalEstimate() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("selftest-est-\(UUID().uuidString)")
    let dirA = root.appendingPathComponent("projA")
    let dirB = root.appendingPathComponent("projB/nested")
    try? fm.createDirectory(at: dirA, withIntermediateDirectories: true)
    try? fm.createDirectory(at: dirB, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let cal = Calendar.current
    // Wednesday 2026-06-24 12:00 local; that week's Monday is 2026-06-22.
    var nowC = DateComponents()
    nowC.year = 2026; nowC.month = 6; nowC.day = 24; nowC.hour = 12
    guard let now = cal.date(from: nowC) else { expect(false, "localEstimate: could not build fixture now"); return }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h
        return cal.date(from: c) ?? now
    }
    func record(id: String, req: String, at date: Date, input: Int, output: Int, cacheC: Int, cacheR: Int) -> String {
        let ts = iso.string(from: date)
        return "{\"timestamp\":\"\(ts)\",\"requestId\":\"\(req)\",\"message\":{\"id\":\"\(id)\",\"usage\":{"
            + "\"input_tokens\":\(input),\"output_tokens\":\(output),"
            + "\"cache_creation_input_tokens\":\(cacheC),\"cache_read_input_tokens\":\(cacheR)}}}"
    }

    // Today (Wed): 10+20+5+5 = 40 tokens; written twice as an exact duplicate -> counted once.
    let todayLine = record(id: "m1", req: "r1", at: at(2026, 6, 24, 10), input: 10, output: 20, cacheC: 5, cacheR: 5)
    let fileA = [todayLine, todayLine].joined(separator: "\n") + "\n"
    try? fileA.data(using: .utf8)?.write(to: dirA.appendingPathComponent("s1.jsonl"))

    // Tuesday (this week, not today): 100 tokens. Old (2 weeks back): 1000 tokens, outside the week.
    let tuesLine = record(id: "m2", req: "r2", at: at(2026, 6, 23, 9), input: 100, output: 0, cacheC: 0, cacheR: 0)
    let oldLine  = record(id: "m3", req: "r3", at: at(2026, 6, 10, 9), input: 1000, output: 0, cacheC: 0, cacheR: 0)
    let fileB = [tuesLine, oldLine].joined(separator: "\n") + "\n"
    try? fileB.data(using: .utf8)?.write(to: dirB.appendingPathComponent("s2.jsonl"))

    let (today, week) = LocalUsageEstimator.estimate(projectsDir: root, now: now)
    // today = 40 (duplicate collapsed); the Tuesday and old records are not today.
    expect(today == 40, "localEstimate: today total = 40 (got \(today))")
    // week = 40 (today) + 100 (Tuesday); the 2-week-old 1000 is excluded.
    expect(week == 140, "localEstimate: week total = 140 (got \(week))")
}

func runUsageStoreSelfTests() {
    // 5-minute floor decision
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    expect(UsageStore.shouldFetch(force: false, lastFetch: t0, now: t0.addingTimeInterval(100), minRefresh: 300) == false,
           "floor blocks a refresh 100s after last fetch")
    expect(UsageStore.shouldFetch(force: false, lastFetch: t0, now: t0.addingTimeInterval(400), minRefresh: 300) == true,
           "floor allows a refresh 400s after last fetch")
    expect(UsageStore.shouldFetch(force: true, lastFetch: t0, now: t0.addingTimeInterval(1), minRefresh: 300) == true,
           "force bypasses the 5-minute floor")

    // Regression: the floor must sit BELOW the interval, or a scheduled tick (which lands a few
    // seconds shy of the full interval, since lastFetch is stamped at completion) gets skipped —
    // the bug that turned a 2-min setting into ~4-min.
    let twoMinFloor = UsageStore.floor(forIntervalMinutes: 2)
    expect(twoMinFloor < 120, "floor(2min)=\(Int(twoMinFloor))s sits below the 120s interval")
    expect(UsageStore.shouldFetch(force: false, lastFetch: t0, now: t0.addingTimeInterval(117), minRefresh: twoMinFloor) == true,
           "a scheduled 2-min tick (117s after last fetch) fetches with the corrected floor")
    expect(UsageStore.shouldFetch(force: false, lastFetch: t0, now: t0.addingTimeInterval(117), minRefresh: 120) == false,
           "regression guard: floor==interval (120s) would have skipped that 2-min tick")

    // cache read/write round-trip
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ust-\(UUID().uuidString).json")
    let snap = UsageSnapshot(
        session: WindowUsage(utilization: 42, resetsAt: Date(timeIntervalSince1970: 1_700_000_000)),
        week: WindowUsage(utilization: 67, resetsAt: nil),
        localTokensToday: nil, localTokensWeek: nil,
        source: .official,
        lastUpdated: Date(timeIntervalSince1970: 1_699_999_000)
    )
    UsageStore.saveCache(snap, to: tmp)
    expect(UsageStore.loadCache(tmp) == snap, "cache round-trips an identical UsageSnapshot")
    try? FileManager.default.removeItem(at: tmp)
    expect(UsageStore.loadCache(FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).json")) == nil,
           "loadCache returns nil for a missing file")
}
