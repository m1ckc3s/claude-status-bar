# Troubleshooting

You don't launch the app yourself; the session launches it.

**The icon doesn't appear at all?**
- Make sure a Claude session is actually running. Start a new session (or restart Claude Code) and the bar appears automatically.
- A session that was already running *before* you installed gets picked up once it does something, but starting a fresh session is the reliable way to bring the bar up the first time.
- Confirm it's running with `pgrep -x ClaudeStatusBar`: a number means it's running (it may just be hidden) no output means it exited because no Claude session is active.
- If first-launch setup never took, run the installer manually: `"/Applications/ClaudeStatusBar.app/Contents/MacOS/ClaudeStatusBar" --install`
- Seeing 2 icons? The desktop app shows its own menu bar icon (the quick-screenshot one). To avoid two icons sitting side by side, open Claude's **Settings → General** and turn that built-in menu bar item off.

---
Back to the [README](../README.md).
