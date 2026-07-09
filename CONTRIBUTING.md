# Contributing

Thanks for your interest. This is a tiny menu bar app and I'd like to keep it that way.

It does one thing: show Claude Code's live status. It stays local (the only network call is a daily update check), free (no API key, no spend), and small (a status bar, not a dashboard).

It's also inspired a bunch of forks and ports, Codex versions, Linux, Windows, other agents, and I love seeing that. If your idea is one of those, it almost certainly belongs in your own fork, not here. This app is Claude Code on macOS, and I want to keep it that.

## What's welcome

Bug fixes, performance wins, animation and visual polish, better session focus, and compatibility fixes (macOS versions, CPU architectures, terminals).

Also the [known issues and suggestions](https://github.com/m1ckc3s/claude-status-bar/issues/22): it tracks proposed enhancements, and anything marked in scope there is open to pick up.

## Won't be merged

- Sending your conversation, files, or project to any API or relay.
- Anything that costs money or needs an API key.
- Usage meters, cost dashboards, analytics, or telemetry.
- Heavy work in the hooks. They run on every event, so they write one small state file and exit: no network, no per-prompt API calls.
- Hardcoding for one locale, provider, relay, or terminal.
- New settings stores or dependencies for a minor feature when what's already there works.
- Changing how your machine behaves: preventing sleep, holding power assertions, running privileged helpers, or any background action beyond showing status. The app displays state, it doesn't act on your system.
- Codex support, ports to Linux or Windows, or support for other agents. Great projects, but as your own fork. This one is Claude Code on macOS.

## Building

You'll need macOS 12+, the Swift toolchain (Xcode Command Line Tools), and Node.js (the hooks run on Node).

```bash
./build.sh          # -> build/ClaudeStatusBar.app
./build.sh --dmg    # also builds a .dmg
```

Signing and notarization use the maintainer's Developer ID; without it you get an ad-hoc build, which is fine for testing. Launch it, start a Claude Code session, and the icon appears.

Build off the latest `main` so you're not fixing something that already changed.

## Testing

Before you open a PR, actually run it. "Builds clean" is not testing.

Test it on both surfaces, because they behave differently:

- the **Claude desktop app**, and
- the **CLI, in a terminal**.

And tell me which terminal you used (Terminal.app, Ghostty, iTerm2, WezTerm, and so on). Behavior genuinely differs between them. For any visual or timing change, attach a screenshot or a short screen recording.


## What to expect

This is a solo hobby project. Replies can be slow, and I may decline a perfectly good PR because it adds complexity or scope I don't want to carry. That's not a knock on your work. When in doubt keep the change small, and check the [known issues](https://github.com/m1ckc3s/claude-status-bar/issues/22) first: some behavior that looks like a bug is intentional and already understood, timing, lifecycle, and self-quit especially.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`, `chore`, `refactor`, `style`, `docs`, `perf`. Branches: `type/kebab-case-description`.

## License

MIT. By contributing, you agree your contributions are licensed under it.
