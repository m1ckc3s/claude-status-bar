# Event-driven Claude Desktop liveness check

`checkLifecycle()` polls every 0.4s to decide whether the app should stay alive, and used to call `claudeDesktopRunning()` on every tick — a synchronous `NSWorkspace.runningApplications` (LaunchServices) query, regardless of whether Claude Desktop's state had actually changed. That's a real contributor to the CPU usage reported in [#53](https://github.com/m1ckc3s/claude-status-bar/issues/53). We replaced the poll with `NSWorkspace` launch/terminate notifications for the Claude Desktop bundle ID, cached in `claudeDesktopIsRunning`, seeded once synchronously at launch.

## Considered options

- **Throttle the poll** (e.g. once every 2–3s instead of every tick): simpler, but still pays occasional LaunchServices IPC for no reason — the app either is or isn't running, which is an edge to react to, not a value that needs sampling.
- **Event-driven (chosen)**: zero IPC cost outside an actual launch/terminate, and matches the intent already implied by the surrounding comment ("Stay while Claude desktop is open OR a session is active").
