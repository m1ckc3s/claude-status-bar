import Foundation

// Node-free hook + install layer. Everything Claude Code's hooks used to shell out to
// `node update.js` / `lifecycle.js` / `install.js` / `uninstall.js` now runs inside this
// one signed binary, invoked as `ClaudeStatusBar --hook <evt>` / `--install` / `--uninstall`.
// Why: a Swift binary starts in ~10ms vs ~80ms for a node process spawned on EVERY tool
// call, and there is no hard-coded node path in settings.json to rot when nvm/fnm changes.

enum SB {
    static let home = NSHomeDirectory()
    static let dir = (home as NSString).appendingPathComponent(".claude/statusbar")
    static let sessionsDir = (dir as NSString).appendingPathComponent("sessions.d")
    static let settingsPath = (home as NSString).appendingPathComponent(".claude/settings.json")
    // Legacy artifacts from the node era; install/uninstall sweep these away.
    static let legacyStatePath = (dir as NSString).appendingPathComponent("state.json")
    static let legacyScripts = ["update.js", "lifecycle.js", "install.js", "uninstall.js", "watcher.sh"]
    static let bundleID = "com.local.claudestatusbar"

    static func ensureDirs() {
        try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
    }
    // Session ids come straight off a hook payload — sanitize before using as a filename.
    static func safeID(_ s: String?) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")
        let cleaned = String((s ?? "").filter { allowed.contains($0) }.prefix(64))
        return cleaned.isEmpty ? "default" : cleaned
    }
    static func sessionFile(_ id: String) -> String {
        (sessionsDir as NSString).appendingPathComponent("\(id).json")
    }
    // Atomic write: a half-written state file must never be read by the polling app.
    static func atomicWrite(_ data: Data, to path: String) {
        let tmp = path + ".\(ProcessInfo.processInfo.processIdentifier).tmp"
        do {
            try data.write(to: URL(fileURLWithPath: tmp))
            _ = try? FileManager.default.removeItem(atPath: path)
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
        } catch {
            try? FileManager.default.removeItem(atPath: tmp)
        }
    }
    static func readJSON(_ path: String) -> [String: Any] {
        guard let d = FileManager.default.contents(atPath: path),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return o
    }
}

// MARK: - Hook runner (state + lifecycle events)

enum HookRunner {
    static let toolLabels: [String: String] = [
        "Bash": "Running command", "Edit": "Editing", "Write": "Writing", "MultiEdit": "Editing",
        "NotebookEdit": "Editing", "Read": "Reading", "Grep": "Searching", "Glob": "Searching",
        "WebFetch": "Browsing web", "WebSearch": "Searching web", "Task": "Delegating",
        "TodoWrite": "Planning",
    ]

    static func run(event: String) {
        // Watchdog: a hook must never hang a Claude session. If stdin never closes, bail.
        let watchdog = Thread { sleep(3); exit(0) }
        watchdog.stackSize = 64 * 1024
        watchdog.start()

        let payload = readStdinJSON()
        SB.ensureDirs()
        let sid = SB.safeID(payload["session_id"] as? String)

        switch event {
        case "start":
            // App not running => any leftover session files are stale (prior crash). Start clean.
            if !appRunning() { clearSessions() }
            writeState(sid: sid, base: ["state": "idle", "label": ""], payload: payload)
            launchApp()
        case "end":
            try? FileManager.default.removeItem(atPath: SB.sessionFile(sid))
        default:
            let prev = SB.readJSON(SB.sessionFile(sid))
            guard let next = computeState(event: event, payload: payload, prev: prev) else { exit(0) }
            writeState(sid: sid, base: next, payload: payload)
        }
        exit(0)
    }

    static func readStdinJSON() -> [String: Any] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // Mirrors the old update.js event→state mapping. Returns nil for unknown events.
    static func computeState(event: String, payload: [String: Any], prev: [String: Any]) -> [String: Any]? {
        let now = Date().timeIntervalSince1970
        let prevStarted = (prev["startedAt"] as? NSNumber)?.doubleValue ?? 0
        var state = "idle", label = "", started = prevStarted

        switch event {
        case "prompt":
            state = "thinking"; label = "Thinking…"; started = now
        case "pre":
            let t = payload["tool_name"] as? String ?? ""
            state = "tool"; label = toolLabels[t] ?? "Using tool"
            if started == 0 { started = now }
        case "post":
            state = "thinking"; label = "Thinking…"
            if started == 0 { started = now }
        case "notify":
            let m = (payload["message"] as? String ?? "").lowercased()
            if m.contains("permission") || m.contains("approve") || m.contains("allow") {
                state = "permission"; label = "Awaiting permission"
            } else if m.contains("waiting") {
                state = "waiting"; label = "Waiting for you"
            } else {
                state = "waiting"; label = (payload["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Waiting"
            }
            started = 0
        case "permreq":
            state = "permission"; label = "Awaiting permission"; started = 0
        case "stop":
            state = "done"; label = "Done"; started = 0
        default:
            return nil
        }
        return ["state": state, "label": label, "startedAt": started]
    }

    // Merge the computed state with carry-over fields (project, transcript) and write atomically.
    static func writeState(sid: String, base: [String: Any], payload: [String: Any]) {
        let prev = SB.readJSON(SB.sessionFile(sid))
        var out = base
        let cwd = payload["cwd"] as? String
        out["tool"] = payload["tool_name"] as? String ?? ""
        out["project"] = cwd.map { ($0 as NSString).lastPathComponent } ?? (prev["project"] as? String ?? "")
        out["sessionId"] = payload["session_id"] as? String ?? sid
        out["transcript"] = payload["transcript_path"] as? String ?? (prev["transcript"] as? String ?? "")
        if out["startedAt"] == nil { out["startedAt"] = prev["startedAt"] ?? 0 }
        out["ts"] = Date().timeIntervalSince1970.rounded()
        if let data = try? JSONSerialization.data(withJSONObject: out) {
            SB.atomicWrite(data, to: SB.sessionFile(sid))
        }
    }

    static func appRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "ClaudeStatusBar"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func clearSessions() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: SB.sessionsDir) else { return }
        for f in files { try? FileManager.default.removeItem(atPath: (SB.sessionsDir as NSString).appendingPathComponent(f)) }
    }

    static func launchApp() {
        // Launch the bundle this hook binary lives in (…/Contents/MacOS/ClaudeStatusBar → app root).
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let appPath = ((((exe as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent as NSString).deletingLastPathComponent) // strip MacOS, Contents
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", appPath]
        try? p.run()
    }
}

// MARK: - Installer (settings.json hook wiring)

enum HookInstaller {
    // A command is "ours" if it points at this app bundle OR at the legacy node script dir.
    static func isOurs(_ cmd: String) -> Bool {
        cmd.contains("ClaudeStatusBar.app") || cmd.contains("/.claude/statusbar")
    }

    static func install() {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let q = "\"\(exe)\""
        let cmd: (String) -> String = { "\(q) --hook \($0)" }

        guard var settings = loadSettingsForWrite() else { return }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // (event, matcher?, hookArg)
        let entries: [(String, Bool, String)] = [
            ("UserPromptSubmit", false, "prompt"),
            ("PreToolUse", true, "pre"),
            ("PostToolUse", true, "post"),
            ("Notification", false, "notify"),
            ("PermissionRequest", true, "permreq"),
            ("Stop", false, "stop"),
            ("SessionStart", false, "start"),
            ("SessionEnd", false, "end"),
        ]
        for (evt, matched, arg) in entries {
            var arr = stripOurs(hooks[evt] as? [[String: Any]] ?? [])
            var entry: [String: Any] = ["hooks": [["type": "command", "command": cmd(arg)]]]
            if matched { entry["matcher"] = "*" }
            arr.append(entry)
            hooks[evt] = arr
        }
        settings["hooks"] = hooks
        writeSettings(settings)
        sweepLegacy()
        NSLog("ClaudeStatusBar: hooks installed (node-free) into \(SB.settingsPath)")
    }

    static func uninstall() {
        guard FileManager.default.fileExists(atPath: SB.settingsPath),
              var settings = parseSettings() else { return }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for evt in Array(hooks.keys) {
            let cleaned = stripOurs(hooks[evt] as? [[String: Any]] ?? [])
            if cleaned.isEmpty { hooks.removeValue(forKey: evt) } else { hooks[evt] = cleaned }
        }
        settings["hooks"] = hooks
        writeSettings(settings)
        sweepLegacy()
        NSLog("ClaudeStatusBar: hooks removed from \(SB.settingsPath)")
    }

    // Drop our hook objects from an event's array; drop now-empty entries.
    static func stripOurs(_ arr: [[String: Any]]) -> [[String: Any]] {
        arr.compactMap { entry in
            var e = entry
            let inner = (entry["hooks"] as? [[String: Any]] ?? []).filter { h in
                !isOurs(h["command"] as? String ?? "")
            }
            if inner.isEmpty { return nil }
            e["hooks"] = inner
            return e
        }
    }

    // Parse settings.json defensively. Returns nil ONLY when the file exists but is
    // unparseable — in that case we refuse to touch it rather than clobber the user's config.
    static func parseSettings() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: SB.settingsPath) else { return [:] }
        guard let d = FileManager.default.contents(atPath: SB.settingsPath) else { return [:] }
        if d.isEmpty { return [:] }
        guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            NSLog("ClaudeStatusBar: settings.json is not valid JSON — leaving it untouched")
            return nil
        }
        return o
    }

    // Parse + back up once before the first write of this install lineage.
    static func loadSettingsForWrite() -> [String: Any]? {
        guard let settings = parseSettings() else { return nil }
        let bak = SB.settingsPath + ".bak-statusbar"
        if FileManager.default.fileExists(atPath: SB.settingsPath),
           !FileManager.default.fileExists(atPath: bak) {
            try? FileManager.default.copyItem(atPath: SB.settingsPath, toPath: bak)
        }
        return settings
    }

    static func writeSettings(_ settings: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { return }
        var blob = data
        blob.append(0x0A) // trailing newline, matching the prior installer
        SB.atomicWrite(blob, to: SB.settingsPath)
    }

    // Remove the old node-era scripts, the global state.json, legacy empty session
    // markers (the node lifecycle.js wrote 0-byte files named by id, not <id>.json),
    // and the old LaunchAgent.
    static func sweepLegacy() {
        for s in SB.legacyScripts {
            try? FileManager.default.removeItem(atPath: (SB.dir as NSString).appendingPathComponent(s))
        }
        try? FileManager.default.removeItem(atPath: SB.legacyStatePath)
        if let markers = try? FileManager.default.contentsOfDirectory(atPath: SB.sessionsDir) {
            for f in markers where !f.hasSuffix(".json") {
                try? FileManager.default.removeItem(atPath: (SB.sessionsDir as NSString).appendingPathComponent(f))
            }
        }
        let label = "com.local.claudestatusbar.watcher"
        let plist = (SB.home as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")
        if FileManager.default.fileExists(atPath: plist) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
            p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            try? FileManager.default.removeItem(atPath: plist)
        }
    }
}
