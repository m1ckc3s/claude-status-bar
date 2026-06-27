import Foundation

struct OAuthToken {
    var accessToken: String
    var expiresAt: Date?

    // No expiry known (e.g. an env-provided token) counts as still valid: v1 never refreshes
    // tokens itself, so "expired" exists only to drive the Re-login state.
    func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

enum CredentialResolver {
    static func resolve(env: [String: String], home: URL, configDir: URL?, runSecurity: () -> String?) -> OAuthToken? {
        // 1. Environment override wins outright.
        if let raw = env["CLAUDE_CODE_OAUTH_TOKEN"], !raw.isEmpty {
            return OAuthToken(accessToken: raw, expiresAt: nil)
        }

        // 2. Credentials file (Linux/WSL location; usually absent on macOS). Honor $CLAUDE_CONFIG_DIR.
        let base = configDir ?? home.appendingPathComponent(".claude")
        let fileURL = base.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: fileURL), let token = parse(data) {
            return token
        }

        // 3. macOS Keychain, read through the injected `security` subprocess.
        if let raw = runSecurity(), let data = raw.data(using: .utf8), let token = parse(data) {
            return token
        }

        return nil
    }

    // expiresAt is epoch milliseconds in both the file and the Keychain payload.
    private static func parse(_ data: Data) -> OAuthToken? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String, !access.isEmpty else { return nil }
        var expires: Date?
        if let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue { expires = Date(timeIntervalSince1970: ms / 1000) }
        return OAuthToken(accessToken: access, expiresAt: expires)
    }
}

enum SecurityKeychain {
    static let service = "Claude Code-credentials"

    // `/usr/bin/security` has been observed to hang indefinitely on recent macOS, so we run it
    // under a hard deadline and kill it on timeout. MUST be called off the main thread
    // (UsageStore runs it inside its refresh worker).
    static func readToken(timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        // -a scopes the lookup to this login user's item (what the Claude Code CLI stores under).
        process.arguments = ["find-generic-password", "-s", service, "-a", NSUserName(), "-w"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 0.5) // brief grace, then force-kill
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let raw = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}
