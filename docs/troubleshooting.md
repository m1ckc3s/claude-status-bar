# Troubleshooting

**You don't open this app, it opens itself.** The only time you launch it by hand is once, right after install, so it can wire up the Claude Code hooks. After that it starts itself whenever a Claude Code session is running and quits when none is. So opening it from Finder or Spotlight with no session active can look like it launches and immediately quits. That is expected, not a crash: just start a Claude Code session and the icon appears on its own. Upgrades self-heal: drop the new version into Applications and it refreshes its own hooks the next time it starts up. (It relaunches itself when your next session begins, and on a version change it re-runs its installer automatically, so you never run anything by hand.)

**Updated (or just installed) while Claude Code sessions were already running?** Those sessions only show up once they do something after the new hooks are in place, so the menu can look empty even with terminals open. Send a prompt in each one, or start a fresh `claude` session, and they appear. (Restarting the terminal works too, since that starts a new session.)

**Using Cursor (or another IDE)?** This tracks Claude Code, not the IDE's own built-in agent. Use the **Claude Code plugin** or a terminal inside Cursor; the default agent window doesn't fire Claude Code hooks, so the icon won't move there.

**The icon doesn't appear at all?**
- Make sure a Claude session is actually running. Start a new session (or restart Claude Code) and the bar appears automatically.
- A session that was already running *before* you installed gets picked up once it does something, but starting a fresh session is the reliable way to bring the bar up the first time.
- Confirm it's running with `pgrep -x ClaudeStatusBar`: a number means it's running (it may just be hidden), no output means it exited because no Claude session is active.
- If first-launch setup never took, run the installer manually: `node "/Applications/ClaudeStatusBar.app/Contents/Resources/install.js"`

**Seeing 2 icons?** The desktop app shows its own menu bar icon (the quick-screenshot one). To avoid two icons sitting side by side, open Claude's **Settings → General** and turn that built-in menu bar item off.

---
Back to the [README](../README.md).
