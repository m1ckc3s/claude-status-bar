# Claude Status Bar

A tiny macOS menu bar app that shows **Claude Code's live status**: an animated Claude spark while it's thinking or running a tool, a yellow dot when it's awaiting your permission, and the elapsed time of the current turn. It sits next to your battery/clock and stays out of the way, no window, no dock icon, no usage dashboards.

> Built so you can tab away during a long "thinking" stretch and still see, at a glance, whether Claude is working, waiting on you, or done.

## What it shows

- **Thinking / working** — the Claude spark animates, with a live `1m 1s` timer.
- **Running a tool** — a short label (`Editing`, `Reading`, `Running command`, `Using tool`, …).
- **Awaiting permission** — a paused yellow dot (CLI only, see below).
- **Idle / done** — rests on the Claude logo.

Two animation styles (pick in the menu): **Claude** (the web "morph" spark) and **Claude Code** (the terminal glyph spinner). Icon color can be **Orange** (Anthropic's `#d97757`) or **System** (adaptive black/white, like your other menu bar icons). The elapsed timer can be toggled off.

## Where it works

This is a **Claude Code** indicator, driven by Claude Code hooks. It tracks:

| Surface | Tracked? |
|---|---|
| Claude Code CLI (terminal) | ✅ |
| Claude Code Desktop — **Code** tab | ✅ |
| Claude Desktop — **Chat** tab | ❌ |
| **Cowork** | ❌ |
| IDE extensions (VS Code / JetBrains) | ❌ |

Chat and Cowork don't use Claude Code's hook system, so the status bar won't update while you're in those. It reflects Claude **Code** activity only.

### Permission detection is CLI-only

The yellow "Awaiting permission" dot appears when Claude Code fires its permission *notification*, which it does in the **CLI**. The **Desktop app** doesn't emit that hook for its in-app permission prompts, so the dot won't show there, the icon just stays on the current tool (e.g. "Writing") while the prompt is open. Everything else (thinking, tools, the open/close lifecycle) works the same in both. And if you run on **auto / bypass mode**, permission prompts never happen anyway, so this is a non-issue.

## Requirements

- macOS 12+
- [Claude Code](https://claude.com/claude-code) (CLI or the Desktop app)
- Node.js (used by the lightweight hook scripts)

## Install

### Option A — DMG (recommended)

1. Download the latest `ClaudeStatusBar.dmg` from [Releases](../../releases).
2. Open it and drag **Claude Status Bar** into Applications.
3. Launch it once — on first launch it wires up the Claude Code hooks for you automatically.
4. Start a new Claude Code session — the spark appears whenever Claude Code is running.

> The DMG is signed and notarized, so it opens normally, no Gatekeeper warning, no right-click needed.

If first-launch setup ever doesn't take, you can run it manually:
`node "/Applications/ClaudeStatusBar.app/Contents/Resources/install.js"`

### Option B — Claude Code plugin

Installs the hooks (status + open/close lifecycle) automatically from inside Claude Code:

```
/plugin marketplace add m1ckc3s/claude-status-bar
/plugin install claude-status-bar@claude-status-bar
```

You'll still drag the app into Applications once (the plugin launches it on session start).

## How it works

Claude Code fires hooks on its lifecycle events. Small scripts write the current status to `~/.claude/statusbar/state.json`; the menu bar app polls that file and renders the spark + label. Two `SessionStart` / `SessionEnd` hooks launch the app when Claude Code opens and quit it when the **last** session closes (a session counter handles multiple windows).

The installer merges its hooks into `~/.claude/settings.json` without touching your existing hooks, and backs the file up first (`settings.json.bak-statusbar`).

## Uninstall

```bash
node "/Applications/ClaudeStatusBar.app/Contents/Resources/uninstall.js"   # removes only our hooks
```
Then drag the app to the Trash.

## Build from source

```bash
git clone https://github.com/m1ckc3s/claude-status-bar
cd claude-status-bar
./build.sh            # builds build/ClaudeStatusBar.app
./build.sh --dmg      # also produces build/ClaudeStatusBar.dmg
```
Requires the Xcode Command Line Tools (`xcode-select --install`).

## Trademark / not affiliated

This is an unofficial, open-source side project. **It is not affiliated with, endorsed by, or sponsored by Anthropic.** "Claude" and the Claude logo are trademarks of Anthropic.

If I'm violating or impeding your trademark, please DM me on X ([@mickces](https://x.com/mickces)) and I'll rename this repo immediately. This is a free side project; I'm not monetizing it.

## License

MIT
