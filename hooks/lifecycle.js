#!/usr/bin/env node
// SessionStart/SessionEnd hooks. Usage: node lifecycle.js <start|end>  (hook JSON, incl. session_id, on stdin)

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const BUNDLE_ID = "com.local.claudestatusbar";
const EXEC = "ClaudeStatusBar";
const dir = path.join(os.homedir(), ".claude", "statusbar");
const stateDir = path.join(dir, "state.d");
const event = process.argv[2];

fs.mkdirSync(stateDir, { recursive: true });

const running = () => { try { cp.execSync(`pgrep -x ${EXEC}`, { stdio: "ignore" }); return true; } catch { return false; } };
const safeId = (s) => String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";

// Controlling tty (for exact terminal-tab focus). Walk up the process tree to the first real
// ttysNNN, since the hook's own stdio may be piped. "" = no tty (e.g. the desktop app).
const ttyDev = () => {
  try {
    let pid = String(process.pid);
    for (let i = 0; i < 6 && pid && pid !== "1"; i++) {
      const [tty, ppid] = cp.execSync(`ps -o tty=,ppid= -p ${pid}`, { encoding: "utf8" }).trim().split(/\s+/);
      if (tty && tty.startsWith("tty")) return "/dev/" + tty;
      pid = ppid;
    }
  } catch {}
  return "";
};

const writeAtomic = (file, obj) => {
  const tmp = file + "." + process.pid + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(obj));
  fs.renameSync(tmp, file);
};

let input = "", done = false;
process.stdin.on("data", (d) => (input += d));
process.stdin.on("end", () => run());
process.stdin.on("error", () => run());
setTimeout(run, 1000); // hooks always pipe stdin, but never hang the session

function run() {
  if (done) return; done = true;
  let id = "", cwd = "";
  try { const j = JSON.parse(input); id = j.session_id; cwd = j.cwd || ""; } catch {}
  id = safeId(id);
  const statePath = path.join(stateDir, id + ".json");

  if (event === "start") {
    // If the app isn't running, any leftover session files are stale (e.g. a prior
    // crash) — clear them so the count starts honest.
    if (!running()) { try { for (const f of fs.readdirSync(stateDir)) fs.rmSync(path.join(stateDir, f), { force: true }); } catch {} }
    // Seed an idle file: counts the session immediately, and clears any frozen state from a
    // resume (SessionStart fires on resume with no active turn).
    try {
      // started:false — a merely-opened conversation seeds this for launch + liveness but stays out of
      // the dropdown until it has real activity (update.js flips started:true on a prompt/tool).
      // tty: the session's controlling terminal, for exact tab focus on a row click.
      writeAtomic(statePath, { state: "idle", label: "", tool: "", project: cwd ? path.basename(cwd) : "", sessionId: id, transcript: "", entrypoint: process.env.CLAUDE_CODE_ENTRYPOINT || "", term_program: process.env.TERM_PROGRAM || "", pid: process.ppid, started: false, tty: ttyDev(), startedAt: 0, ts: Math.floor(Date.now() / 1000) });
    } catch {}
    cp.spawn("open", ["-g", "-b", BUNDLE_ID], { stdio: "ignore", detached: true }).unref();
  } else if (event === "end") {
    // Removing the file drops this session from the aggregate — this is also what recovers a
    // frozen animation on force-quit (SessionEnd fires, but no Stop). No state rewrite needed.
    try { fs.rmSync(statePath, { force: true }); } catch {}
  }
  process.exit(0);
}
