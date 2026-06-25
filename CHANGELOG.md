# Changelog

All notable changes to Claude Status Bar are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.2.1] - 2026-06-25

### Fixed
- Edge case where closing the app (or the Claude desktop app) mid-animation left the menu bar stuck. On reopen it would still show the old "thinking" state with the timer climbing, because a force-quit fires no Stop hook. The status now resets to the idle resting icon when the owning session ends or resumes.
- The menu bar no longer parks on "Waiting for you" after a turn. Claude Code's CLI sends an idle notification ("Claude is waiting for your input") when a session sits idle, and the app was turning that into a persistent label. Now only permission notifications affect the icon, so it simply rests when idle.

## [0.2.0] - 2026-06-25

### Added
- **Awaiting-permission dot now works in the Claude desktop app**, not just the terminal CLI. Previously the yellow "awaiting permission" dot only appeared in the CLI, because the only signal we had (the `Notification` hook) never fires for permission prompts in the desktop app. The app now also listens to Claude Code's `PermissionRequest` hook, which fires the moment an approval dialog is shown in both the CLI and the desktop app, so the dot lights up the instant Claude is waiting on you to approve a tool.

## [0.1.0] - 2026-06-22

### Added
- **Crab Walking** animation style: a pixel-art Clawd crab that scuttles in the menu bar while Claude works. Pick it under Animation. It's always its orange pixel-art self (the Claude and Claude Code styles still follow the Orange/System color setting).
- Optional **completion sound**: a soft chime when a turn longer than a minute finishes. Off by default, toggle it under Options.
- **Version and update check** in the menu: shows your current version, plus a one-click "Update available" that opens the latest release when there's a newer one. The check is a once-a-day read of GitHub's public release tag; no data is collected and nothing is sent to the developer.
- Menu **section headers** (Options / Animation / Color) for easier navigation.

## [0.0.5] - 2026-06-22

### Fixed
- The app no longer quits while a session that was already running before you installed it is actively working. Such a session never fired its one-time `SessionStart` hook, so it wasn't being tracked, even though its other hooks fire normally. The status hooks now register the session on any activity, so any actively-working session keeps the icon alive. (Thanks to the bug report that pinned this down.)

## [0.0.4] - 2026-06-22

### Fixed
- The app now actually runs on macOS 12 (Monterey) and later, as the README states. Earlier builds were compiled without a pinned deployment target, so the binary inherited the build machine's OS (macOS 26) and refused to launch on anything older, despite the stated 12.0 requirement. The build now targets macOS 12.0 explicitly.

## [0.0.3] - 2026-06-22

### Changed
- Reworked how the icon appears on desktop-app launch. The app is now started by the existing session hook (which fires when the Claude desktop app opens, when `claude` runs in a terminal, or when a conversation is opened) and quits itself when Claude is closed and no session is active. This keeps the "icon appears when the desktop app opens" behavior from 0.0.2 with no background helper.

### Removed
- The background watcher (a `launchd` LaunchAgent running a shell script) introduced in 0.0.2. It showed up as a "bash" item under Login Items and Extensions, which was confusing. There is no longer any login item or background item. Upgrading from 0.0.2 removes the old LaunchAgent automatically.

### Fixed
- The menu bar icon now reliably disappears when you quit the Claude desktop app, detected directly rather than relying on the session-end hook (which is unreliable during app shutdown).
- Upgrades now self-heal: the app re-runs its installer when the version changes, so updating from an older version refreshes the hooks and removes the old background watcher without any manual step. Previously the installer only ran on a first-ever install.

## [0.0.2] - 2026-06-21

### Added
- Desktop app watcher: the menu bar icon now appears the moment the Claude desktop app opens, before you start a conversation, and disappears shortly after you quit it. Previously the icon only showed once a session began. Implemented as a lightweight `launchd` LaunchAgent that tracks the Claude desktop process (installed via `install.js`, removed via `uninstall.js`).

### Changed
- Ending a Claude Code session no longer hides the icon while the Claude desktop app is still open.

### Fixed
- Uninstall now removes all of the app's own hooks, including the `SessionStart` / `SessionEnd` lifecycle hooks that a previous version left behind. It only ever touches this app's hooks, never any others.

### Notes
- The desktop watcher is part of the DMG / standalone install path. The Claude Code plugin install path keeps the session-only behavior.

## [0.0.1] - 2026-06-21

### Added
- Initial release: macOS menu bar status indicator for Claude Code, driven entirely by Claude Code hooks.
- Animated Claude spark, elapsed turn timer, and an "awaiting permission" dot.
- Two animation styles (Claude, Claude Code) and two color modes (Orange, System), persisted in preferences.
- Refcounted session lifecycle: launches when Claude Code opens, quits when the last session ends.
- Signed and notarized DMG so it opens without a Gatekeeper warning.
- Claude Code plugin marketplace manifest for the plugin install path.

[0.2.1]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.2.1
[0.2.0]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.2.0
[0.1.0]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.1.0
[0.0.5]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.0.5
[0.0.4]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.0.4
[0.0.3]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.0.3
[0.0.2]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.0.2
[0.0.1]: https://github.com/m1ckc3s/claude-status-bar/releases/tag/v0.0.1
