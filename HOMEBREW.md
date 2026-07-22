# Claude Status Bar + Homebrew

Claude Status Bar is on Homebrew. This page is the full story: how to install, how updates work, and everything about the one-time transition in v0.4.0. If something brew-related looks broken, the answer is almost certainly below.

## New users

```
brew install --cask claude-status-bar && open -a "Claude Status Bar"
```

The `open` at the end launches the app once, and that first launch is what installs its Claude Code hooks (brew can't do it for you: installing only copies the app). After it, the app starts itself whenever a Claude Code session begins, and the spark appears in your menu bar whenever Claude Code does something.

If no Claude Code session is running when you install, the app may quit again a few seconds after that first launch. That's normal, not a failed install: the hooks are in place, and it reappears on its own the moment any session does anything (a prompt, a tool call, or a new session starting). (More of these "looks broken, isn't" cases: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).)

No Homebrew? Download `ClaudeStatusBar.dmg` from [Releases](https://github.com/m1ckc3s/claude-status-bar/releases/latest) and drag it to Applications, same as always.

## Already using the app? (installed from the DMG)

Run the same command:

```
brew install --cask claude-status-bar && open -a "Claude Status Bar"
```

Homebrew installs the new copy, and that first launch removes your old copy automatically (details below). Your settings, color choices, and hooks all carry over untouched. From then on you update through brew and never touch a DMG again.

You don't have to switch. The DMG keeps working forever, and the in-app updater will always offer it.

## Updating

```
brew upgrade --cask claude-status-bar
```

Or just wait for the app to tell you: when a new version is available, the dropdown shows an update line with a copy button. Click it, paste in your terminal, done.

Two things worth knowing about timing:

- **Homebrew lags new releases by a few hours to a day.** When a release ships, a Homebrew bot notices the new version and updates the cask automatically. Until it does, `brew upgrade` says you're up to date even though GitHub shows a newer release. This is normal. The app accounts for it: if you installed via brew, "update available" only appears once brew can actually deliver it.
- **The app checks for updates once a day**, so there can be up to a day between a release and the dropdown noticing. Impatient? `brew upgrade --cask claude-status-bar` any time.

## The v0.4.0 transition (one-time, then never again)

To join Homebrew, the app bundle had to be renamed to match its cask: `ClaudeStatusBar.app` became `Claude Status Bar.app` (with spaces, matching the app's actual name). That rename has a few one-time consequences:

**The old app deletes itself.** The first time v0.4.0 or later launches, it looks for the old `ClaudeStatusBar.app` in /Applications, verifies it is really this app (it checks the bundle identifier, so a renamed copy of something else is never touched), quits it if running, and removes it. This is deliberate: without it, updating from the DMG would leave you with two copies. If you see the old icon disappear right after first launch, that's this working.

**If you update via DMG across the rename:** drag `Claude Status Bar.app` to Applications as usual. Finder won't offer to replace the old app because the filename changed; don't worry about it, just launch the new one and the cleanup removes the old copy.

**If you switch to brew across the rename:** `brew install --cask claude-status-bar` works even with the old app still present, because the filenames differ. Launch the new app once and the old copy is gone.

**Scripts or shortcuts pointing at the old path** (`/Applications/ClaudeStatusBar.app`) need updating to `/Applications/Claude Status Bar.app`. Quote the path; it has spaces now.

## Tested scenarios

Every path through the transition was tested end to end before release:

| # | Scenario | Result |
|---|----------|--------|
| 1 | Fresh `brew install`, no prior copy of the app | Pass: installs and launches clean |
| 2 | **The main upgrade path:** v0.3.4 installed from the DMG and running in the menu bar, then `brew install --cask claude-status-bar` and launch | Pass: no extra commands needed, the old running copy was quit and removed automatically within seconds, one copy left |
| 3 | Old `ClaudeStatusBar.app` running, new DMG dragged in, both briefly present, new app launched | Pass: old copy quit and removed automatically, one copy left |
| 4 | Installed via brew, then `brew upgrade` across the rename | Pass: clean swap, no leftovers |
| 5 | Old copy installed manually, then plain `brew install` while the cask still pointed at the old version | Pass: brew reports "already an App" as expected, and `brew install --cask --force claude-status-bar` recovers (see FAQ) |
| 6 | Hooks and update checks from the renamed bundle | Pass: hooks reinstall themselves on first launch, update check reads both GitHub and Homebrew |

## FAQ / troubleshooting

**`Error: Cask 'claude-status-bar' is unavailable`** — run `brew update` first. If it still fails and the cask was added or bumped in the last day, you've hit the propagation lag; wait a few hours.

**`brew: command not found`** — you don't have Homebrew (or it isn't on your PATH). Either install it from [brew.sh](https://brew.sh) or skip brew entirely and use the DMG. If you installed brew in a nonstandard location, you already know how to fix your PATH.

**`Error: It seems there is already an App at '/Applications/Claude Status Bar.app'`** — brew won't overwrite an app it doesn't manage. You previously updated via DMG after installing via brew. Run `brew install --cask --force claude-status-bar` once to let brew take back over.

**Two copies of the app** — launch the new one (`Claude Status Bar.app`); the old copy removes itself. If somehow both linger, delete `ClaudeStatusBar.app` (the one without spaces) manually.

**`brew upgrade` says up to date but GitHub has a newer release** — propagation lag, see Updating above.

**Does brew send my data anywhere?** — no more than the DMG did. Installing downloads the same DMG from GitHub Releases. The app's update check hits the GitHub API and Homebrew's public formulae API; nothing is sent to anyone, there is no server.

**Uninstalling completely:**

```
node "/Applications/Claude Status Bar.app/Contents/Resources/uninstall.js"
brew uninstall --zap claude-status-bar
```

The first line removes ONLY this app's hook entries from `~/.claude/settings.json`. It never touches your own hooks, other tools' hooks, or any other Claude Code settings; brew can't edit that file (it's shared with Claude Code itself), so the app's own uninstaller does the surgical edit. The second removes the app and every file it ever created (`~/.claude/statusbar`, caches, preferences). If you installed via DMG instead, replace the second line with: delete the app, then trash `~/.claude/statusbar`.
