import Foundation

enum LocalUsageEstimator {
    static func estimate(projectsDir: URL, now: Date) -> (today: Int, week: Int) {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: projectsDir,
                                         includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return (0, 0)
        }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let startOfWeek = mostRecentMonday(onOrBefore: now, calendar: cal)

        var seen = Set<String>()
        var today = 0
        var week = 0

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            // Transcripts are append-only, so a file last modified before the week boundary
            // holds no in-window entries — skip it without reading (avoids re-parsing all history).
            if let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mtime < startOfWeek { continue }
            guard let data = fm.contents(atPath: url.path),
                  let text = String(data: data, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }

                // Dedupe by message.id + requestId: the same assistant turn appears across
                // multiple transcripts (resumes, sidechains). Skip dedupe only if both are absent.
                let id = (message["id"] as? String) ?? ""
                let req = (obj["requestId"] as? String) ?? ""
                if !id.isEmpty || !req.isEmpty {
                    let key = id + "|" + req
                    if seen.contains(key) { continue }
                    seen.insert(key)
                }

                let tokens = intToken(usage, "input_tokens")
                    + intToken(usage, "output_tokens")
                    + intToken(usage, "cache_creation_input_tokens")
                    + intToken(usage, "cache_read_input_tokens")
                if tokens == 0 { continue }

                guard let ts = (obj["timestamp"] as? String).flatMap(UsageParser.parseResetDate) else { continue }
                if ts >= startOfWeek { week += tokens }
                if ts >= startOfToday { today += tokens }
            }
        }

        return (today, week)
    }

    private static func intToken(_ usage: [String: Any], _ key: String) -> Int {
        (usage[key] as? NSNumber)?.intValue ?? 0
    }

    // Most recent Monday 00:00 local (today if today is Monday). weekday: 1=Sun … 7=Sat.
    private static func mostRecentMonday(onOrBefore now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7    // Mon->0, Tue->1 … Sun->6
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }
}
