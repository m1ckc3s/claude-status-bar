<img width="672" height="80" alt="Screen Recording 2026-06-23 at 3 57 47 AM 2" src="https://github.com/user-attachments/assets/97876ac9-cd4f-431b-873a-93220de5bd99" />
<br><br>

<a href="https://github.com/m1ckc3s/claude-status-bar/releases/latest/download/ClaudeStatusBar.dmg"><img src="assets/download.png" alt="Download ClaudeStatusBar.dmg for macOS" width="260"></a>
<br>

## Claude Status Bar

A tiny macOS menu bar app that shows **Claude Code's live status**: an animated Claude icon while it's thinking or running a tool, a yellow dot when it's awaiting your permission, and the elapsed time of the current turn. Lightweight, no window, no dock icon, no usage dashboards.

> Built so you can tab away during a long "thinking" stretch and still see, at a glance, whether Claude is working, waiting on you, or done._

<img width="600" height="488" alt="Screen Recording 2026-06-26 at 10 01 17 PM (1)" src="https://github.com/user-attachments/assets/4cc7a726-abe5-4e9c-aa5f-8525ddf6f398" />

> [!IMPORTANT]
> **Multi-session support.** When several Claude Code sessions run at once (multiple terminals, or
> a terminal plus the desktop app), the menu bar surfaces the highest-priority one — a session
> awaiting your permission is never hidden behind one that's merely thinking — names the repo, and
> the dropdown lists every live session. Click a session to jump to it: desktop sessions focus
> the Claude app, terminal sessions bring their terminal app to the front (the app, not yet the
> exact window or tab when you have several open). Precise per-tab focus is in progress:
> **[issue #19 →](https://github.com/m1ckc3s/claude-status-bar/issues/19)**.

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
  - **Claude Spark**, the web/chat "morph" spark
  - **Claude Code**, the terminal glyph spinner
  - **Crab Walking**, a pixel-art Clawd crab that scuttles while Claude works
- **Icon color:** **Orange** or **System** (adaptive black/white). All three styles follow this setting: in System mode Crab Walking renders as a shaded monochrome silhouette that matches the menu bar, and in Orange mode it stays its full-color pixel-art self.
- **Version and update:** the menu shows your current version, with a one-click "Update available" when a newer release exists.

## Where it works

| Surface | Tracked? |
|---|---|
| Claude Code CLI (terminal) | ✅ |
| Claude Code Desktop — **Code** tab | ✅ |
| Cursor (Claude Code extension) | ✅ |
| Claude Desktop — **Chat** tab | ❌ |
| **Cowork** | ❌ |

## Requirements

- macOS 12+
- [Claude Code](https://claude.com/claude-code) (CLI or the Desktop app)
- Node.js

## Install

### Option A — DMG (recommended) 

Signed and notarized. Open it, drag the app to Applications, launch once.

1. Download the latest `ClaudeStatusBar.dmg` from [Releases](../../releases).
2. Open it and drag **Claude Status Bar** into Applications.
3. Launch it once. On first launch it wires up the Claude Code hooks for you automatically.
4. Start a new Claude Code session, the icon appears whenever Claude Code is running.

### Updating

Download the latest DMG and drag it into Applications (choose **Replace**). 
Launch it once, it refreshes its hooks on a version change, then restart Claude Code to pick them up.

### Option B — Claude Code plugin

Installs the hooks (status + open/close lifecycle) automatically from inside Claude Code:

```
/plugin marketplace add m1ckc3s/claude-status-bar
/plugin install claude-status-bar@claude-status-bar
```

The plugin installs the hooks but not the app itself, so drag **Claude Status Bar** into Applications once (from the DMG). The plugin launches it automatically on session start.

## How it works

The app is stateless. Claude Code hooks write each session's status to its own file under `~/.claude/statusbar/state.d/<session_id>.json`; the app polls that directory every 0.4s, aggregates across all live sessions, and renders one icon and label (permission dot if any session needs approval, animating if any is working, resting only when all are idle). `SessionStart` launches it; it self-quits once the Claude desktop app is closed and no Claude Code session is active (each active session is its file under `~/.claude/statusbar/state.d/`).

The installer merges its hooks into `~/.claude/settings.json` (backing it up first), and the app's only network call is a once-a-day GitHub release check ([details](docs/privacy.md)).

## Uninstall

```bash
node "/Applications/ClaudeStatusBar.app/Contents/Resources/uninstall.js"   # removes only our hooks
```
Then drag the app to the Trash.

## Acknowledgements

I built this for myself, then open-sourced it because other people might find it handy too, and I'm genuinely thrilled that so many of you do. An extra thank-you to everyone who went the extra mile and contributed code, fixes, and ideas.

**[See the contributors →](docs/acknowledgements.md)**

## Trademark / Not Affiliated

This is an unofficial, open-source side project. **It is not affiliated with, endorsed by, or sponsored by Anthropic.** "Claude" and the Claude spark logo are trademarks of Anthropic, used here nominatively. This project is MIT licensed, but that covers the source code only and conveys no rights to Anthropic's trademarks or brand.

If I'm violating or impeding your trademark, Contact me on X Chat ([@mickces](https://x.com/mickces))
This is a free side project; I'm not monetizing it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for what fits, what doesn't, and how to build.

## License

MIT
