import Cocoa
import ServiceManagement

// SMAppService keys a login item on the bundle's code signature AND its recorded path.
// LaunchServices relaunches the app from /Applications, so registering from anywhere
// else (a dev build/path) records a path macOS won't relaunch — only register from there.
enum LoginItem {
    private static var eligible: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    static func setEnabled(_ on: Bool) {
        guard #available(macOS 13, *), eligible else { return } // no-op on macOS 12 / non-/Applications
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Ad-hoc dev builds (changing signature each rebuild) may orphan/duplicate the
            // entry or report .requiresApproval — expected; surface, don't crash.
            NSLog("ClaudeStatusBar: login item \(on ? "register" : "unregister") failed: \(error)")
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
