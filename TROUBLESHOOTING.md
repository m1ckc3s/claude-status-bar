# Troubleshooting

**You don't open this app, it opens itself.** The only time you launch it by hand is once, right after install, so it can wire up the Claude Code hooks. After that it starts itself whenever a Claude Code session is running and quits when none is. So opening it from Finder or Spotlight with no session active can look like it launches and immediately quits. That is expected, not a crash: just start a Claude Code session and the icon appears on its own. Upgrades self-heal: drop the new version into Applications and it refreshes its own hooks the next time it starts up. (It relaunches itself when your next session begins, and on a version change it re-runs its installer automatically, so you never run anything by hand.)

**Updated (or just installed) while Claude Code sessions were already running?** Sessions already open appear the next time they do something (a prompt or a tool call), so the menu can look empty until then. Starting a new `claude` session also works. (On 0.4.0 and earlier, a new session was the only way; update if you're seeing that.)

**Using Chat or Cowork in the desktop app?** Those don't move the icon. Claude Code Chat and Cowork don't fire the same hooks this app runs on, so there's no live signal to drive the timer or the animation. Only Claude Code sessions move it: the desktop app's Code mode, or `claude` in a terminal. You'll still see the resting spark while the desktop app is open.

**Icon stuck on "thinking" in the terminal after you interrupted?** If you press Esc or Ctrl+C during the early thinking phase, before any output has streamed, Claude Code doesn't emit a signal for the app to catch, so the icon can sit on thinking until it times out (about 15 minutes). Sending any new prompt clears it right away. This one is terminal only, and it's an upstream Claude Code quirk, tracked in the [known issues](https://github.com/m1ckc3s/claude-status-bar/issues/22).

**Icon stuck on "thinking" in the desktop app?** If a session hits your usage limit mid-turn, Claude Code fires no hook to close it out, so the icon keeps thinking until it times out (about 15 minutes). To clear it right away, click the icon in the menu bar and choose **Quit**.

**The icon doesn't appear at all?**
- Make sure a Claude session is actually running, not just a terminal window open. Start a new session (or restart Claude Code) and the bar appears automatically.
- A session that was already running *before* you installed won't show up until you start a fresh session.
- Confirm it's running with `pgrep -x ClaudeStatusBar`: a number means it's running (it may just be hidden), no output means it exited because no Claude session is active.
- If first-launch setup never took, run the installer manually: `node "/Applications/ClaudeStatusBar.app/Contents/Resources/install.js"`

**Installed via Homebrew?** Everything brew-specific (install, updates, the v0.4.0 rename transition, brew errors) lives in [HOMEBREW.md](HOMEBREW.md).

**Seeing 2 icons?** The desktop app shows its own menu bar icon (the quick-screenshot one). To avoid two icons sitting side by side, open Claude's **Settings → General** and turn that built-in menu bar item off.

---
Back to the [README](README.md).
