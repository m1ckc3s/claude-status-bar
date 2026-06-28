# Contributing

Thanks for your interest. This is a tiny menu bar app and I'd like to keep it that way.

It does one thing: show Claude Code's live status. It stays local (the only network call is a daily update check), free (no API key, no spend), and small (a status bar, not a dashboard).

## What's welcome

Bug fixes, performance wins, animation and visual polish, better session focus, and compatibility fixes (macOS versions, CPU architectures, terminals).

Also the [known issues and suggestions](https://github.com/m1ckc3s/claude-status-bar/issues/22): it tracks proposed enhancements, and anything marked in scope there is open to pick up.

## Won't be merged

- Sending your conversation, files, or project to any API or relay.
- Anything that costs money or needs an API key.
- Usage meters, cost dashboards, analytics, or telemetry. Build a separate app for that; [Anthrocite](https://github.com/MarquesCoding/anthrocite) is one example to look into.
- Heavy work in the hooks. They run on every event, so they write one small state file and exit: no network, no per-prompt API calls.
- Hardcoding for one locale, provider, relay, or terminal.
- New settings stores or dependencies for a minor feature when what's already there works.

## Building

You'll need macOS 12+, the Swift toolchain (Xcode Command Line Tools), and Node.js (the hooks run on Node).

```bash
./build.sh          # -> build/ClaudeStatusBar.app
./build.sh --dmg    # also builds a .dmg
```

Signing and notarization use the maintainer's Developer ID; without it you get an ad-hoc build, which is fine for testing. Launch it, start a Claude Code session, and the icon appears.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`, `chore`, `refactor`, `style`, `docs`, `perf`. Branches: `type/kebab-case-description`.

## License

MIT. By contributing, you agree your contributions are licensed under it.
