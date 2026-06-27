#!/usr/bin/env node
// SessionStart/SessionEnd: launch the app, and track each session as one file under
// state.d/<session_id>.json (race-free; the app aggregates them and quits itself when none
// remain). Rationale + history in CLAUDE.md.
// Usage: node lifecycle.js <start|end>   (hook JSON, incl. session_id, arrives on stdin)

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const BUNDLE_ID = "com.local.claudestatusbar";
const EXEC = "ClaudeStatusBar";
const dir = path.join(os.homedir(), ".claude", "statusbar");
const stateDir = path.join(dir, "state.d");
const event = process.argv[2];
const node = process.execPath;

fs.mkdirSync(stateDir, { recursive: true });

const running = () => { try { cp.execSync(`pgrep -x ${EXEC}`, { stdio: "ignore" }); return true; } catch { return false; } };
const safeId = (s) => String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";

const writeAtomic = (file, obj) => {
  const tmp = file + "." + process.pid + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(obj));
  fs.renameSync(tmp, file);
};

let input = "", done = false;
process.stdin.on("data", (d) => (input += d));
process.stdin.on("end", () => run());
process.stdin.on("error", () => run());
setTimeout(run, 1000);

function run() {
  if (done) return; done = true;
  let id = "", cwd = "";
  try { const j = JSON.parse(input); id = j.session_id; cwd = j.cwd || ""; } catch {}
  id = safeId(id);
  const statePath = path.join(stateDir, id + ".json");

  if (event === "start") {
    if (!running()) { try { for (const f of fs.readdirSync(stateDir)) fs.rmSync(path.join(stateDir, f), { force: true }); } catch {} }
    try {
      writeAtomic(statePath, { state: "idle", label: "", tool: "", project: cwd ? path.basename(cwd) : "", dirName: cwd ? path.basename(cwd) : "", sessionId: id, transcript: "", entrypoint: process.env.CLAUDE_CODE_ENTRYPOINT || "", term_program: process.env.TERM_PROGRAM || "", startedAt: 0, ts: Math.floor(Date.now() / 1000) });
    } catch {}
    cp.spawn("open", ["-g", "-b", BUNDLE_ID], { stdio: "ignore", detached: true }).unref();
    // Fire-and-forget: generate an LLM title for the session in the background.
    if (cwd) cp.spawn(node, [path.join(dir, "title.js"), id, cwd], { stdio: "ignore", detached: true, env: process.env }).unref();
  } else if (event === "end") {
    try { fs.rmSync(statePath, { force: true }); } catch {}
  }
  process.exit(0);
}
