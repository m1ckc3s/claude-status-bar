<img width="672" height="80" alt="Screen Recording 2026-06-23 at 3 57 47 AM 2" src="https://github.com/user-attachments/assets/97876ac9-cd4f-431b-873a-93220de5bd99" />
<br><br>

<a href="https://github.com/m1ckc3s/claude-status-bar/releases/latest/download/ClaudeStatusBar.dmg"><img src="assets/download.png" alt="Download ClaudeStatusBar.dmg for macOS" width="260"></a>
<br>

## Claude Status Bar

A tiny macOS menu bar app that shows **Claude Code's live status**: an animated Claude icon while it's thinking or running a tool, a yellow dot when it's awaiting your permission, and the elapsed time of the current turn. Lightweight, no window, no dock icon, no usage dashboards.

_Built so you can tab away during a long "thinking" stretch and still see, at a glance, whether Claude is working, waiting on you, or done._

Signed and notarized. Open it, drag the app to Applications, launch once.

<img width="1016" height="566" alt="Claude Status Bar demo" src="https://github.com/user-attachments/assets/55a7b294-e893-4f73-b16b-b8beef784400" />
<img width="656" height="883" alt="Screenshot 2026-06-25 at 5 27 42 AM" src="https://github.com/user-attachments/assets/7a164fda-ea23-434f-a13a-18ad7bcb1b25" />

> [!IMPORTANT]
> **Multi-session support.** This is built for one active Claude Code session at a time. If you
> run multiple sessions at once (several terminals, or a terminal plus the desktop app), the menu
> bar follows the most recently active one. Here is the why, and how you can add it yourself:
> **[read the story →](https://github.com/m1ckc3s/claude-status-bar/issues/8)**

---

## What it shows

- **Thinking / working** — the icon animates, with a live `1m 1s` timer.
- **Running a tool** — a short label (`Editing`, `Reading`, `Running command`, `Using tool`, …).
- **Awaiting permission** — a paused yellow dot, in both the CLI and the Desktop app.
- **Idle / done** — rests on the Claude logo.

Everything is controlled from the menu:

- **Show timer:** toggle the elapsed `1m 1s` clock.
- **Play completion sound:** a soft chime when a turn longer than a minute finishes (off by default).
- **Animation style:**
  - **Claude**, the web "morph" spark
  - **Claude Code**, the terminal glyph spinner
  - **Crab Walking**, a pixel-art Clawd crab that scuttles while Claude works
- **Icon color:** **Orange** or **System** (adaptive black/white). The Claude and Claude Code styles follow this setting; Crab Walking is always its orange pixel-art self.
- **Version and update:** the menu shows your current version, with a one-click "Update available" when a newer release exists.

## Where it works

| Surface | Tracked? |
|---|---|
| Claude Code CLI (terminal) | ✅ |
| Claude Code Desktop — **Code** tab | ✅ |
| Cursor (Claude Code extension) | ✅ |
| Claude Desktop — **Chat** tab | ❌ |
| **Cowork** | ❌ |

### Awaiting-permission dot

🟡 As of 0.2.0 the yellow "Awaiting permission" dot fires in both the CLI and the Desktop app. It lights up the moment Claude is waiting for you to approve a tool, via Claude Code's `PermissionRequest` hook. (On auto, accept-edits, or bypass permission modes there are no prompts, so the dot never needs to show.)

## Requirements

- macOS 12+
- [Claude Code](https://claude.com/claude-code) (CLI or the Desktop app)
- Node.js (used by the hook scripts)

## Install

### Option A — DMG (recommended)

1. Download the latest `ClaudeStatusBar.dmg` from [Releases](../../releases).
2. Open it and drag **Claude Status Bar** into Applications.
3. Launch it once. On first launch it wires up the Claude Code hooks for you automatically.
4. Start a new Claude Code session, the icon appears whenever Claude Code is running.

### Updating

Download the latest DMG and drag it into Applications (choose **Replace**). Launch it once, it refreshes its hooks on a version change, then restart Claude Code to pick them up.

### Option B — Claude Code plugin

Installs the hooks (status + open/close lifecycle) automatically from inside Claude Code:

```
/plugin marketplace add m1ckc3s/claude-status-bar
/plugin install claude-status-bar@claude-status-bar
```

The plugin installs the hooks but not the app itself, so drag **Claude Status Bar** into Applications once (from the DMG). The plugin launches it automatically on session start.

## How it works

The app is stateless. Claude Code hooks write the current status to `~/.claude/statusbar/state.json`; the app polls that file every 0.4s and renders the icon and label. `SessionStart` launches it; it self-quits once the Claude desktop app is closed and no Claude Code session is active (each active session is a file under `~/.claude/statusbar/sessions.d/`).

The installer merges its hooks into `~/.claude/settings.json` (backing it up first), and the app's only network call is a once-a-day GitHub release check ([details](docs/privacy.md)).

## Uninstall

```bash
node "/Applications/ClaudeStatusBar.app/Contents/Resources/uninstall.js"   # removes only our hooks
```
Then drag the app to the Trash.

## Trademark / not affiliated

This is an unofficial, open-source side project. **It is not affiliated with, endorsed by, or sponsored by Anthropic.** "Claude" and the Claude spark logo are trademarks of Anthropic, used here nominatively. This project is MIT licensed, but that covers the source code only and conveys no rights to Anthropic's trademarks or brand.

If I'm violating or impeding your trademark, DM me on X ([@mickces](https://x.com/mickces)) and I'll rename this repo. 
This is a free side project; I'm not monetizing it.

## License

MIT
