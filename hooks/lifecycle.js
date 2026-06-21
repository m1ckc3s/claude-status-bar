#!/usr/bin/env node
// SessionStart/SessionEnd lifecycle: launch the menu bar app when Claude Code opens,
// and quit it when the LAST session ends. A small counter file tracks concurrent
// sessions so closing one of several doesn't kill the indicator for the others.
// Usage: node lifecycle.js <start|end>

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const BUNDLE_ID = "com.local.claudestatusbar";
const EXEC = "ClaudeStatusBar";
const dir = path.join(os.homedir(), ".claude", "statusbar");
const countFile = path.join(dir, "sessions");
const event = process.argv[2];

fs.mkdirSync(dir, { recursive: true });
const read = () => { try { return parseInt(fs.readFileSync(countFile, "utf8"), 10) || 0; } catch { return 0; } };
const write = (n) => fs.writeFileSync(countFile, String(Math.max(0, n)));

const running = () => { try { cp.execSync(`pgrep -x ${EXEC}`, { stdio: "ignore" }); return true; } catch { return false; } };

if (event === "start") {
  // If the app isn't running, any leftover count is stale (e.g. a prior crash) — reset.
  write((running() ? read() : 0) + 1);
  cp.spawn("open", ["-g", "-b", BUNDLE_ID], { stdio: "ignore", detached: true }).unref();
} else if (event === "end") {
  const n = read() - 1;
  write(n);
  if (n <= 0) {
    write(0);
    cp.spawn("pkill", ["-x", EXEC], { stdio: "ignore" });
  }
}
