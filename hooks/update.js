#!/usr/bin/env node
// Invoked by Claude Code hooks. Reads the hook JSON payload on stdin, maps the
// event to a status, and atomically writes a PER-SESSION file:
//   ~/.claude/statusbar/state.d/<session_id>.json
// The app reads every file in state.d/ and aggregates them (see Sources/main.swift).
// Usage: node update.js <prompt|pre|post|notify|permreq|stop>

const fs = require("fs");
const os = require("os");
const path = require("path");

const dir = path.join(os.homedir(), ".claude", "statusbar");
const stateDir = path.join(dir, "state.d");
const event = process.argv[2] || "";

// Controlling tty of this session, for exact terminal-tab focus (the app matches a Terminal/iTerm
// tab by tty via AppleScript). Hooks run under the `claude` process, which holds the terminal's
// tty; stdio may be piped, so walk up the process tree to the first real ttysNNN. "" = no tty
// (e.g. the desktop app). Stable per session, so callers carry it over instead of re-running ps.
function ttyDev() {
  try {
    const { execSync } = require("child_process");
    let pid = String(process.pid);
    for (let i = 0; i < 6 && pid && pid !== "1"; i++) {
      const [tty, ppid] = execSync(`ps -o tty=,ppid= -p ${pid}`, { encoding: "utf8" }).trim().split(/\s+/);
      if (tty && tty.startsWith("tty")) return "/dev/" + tty;
      pid = ppid;
    }
  } catch {}
  return "";
}

const TOOL_LABELS = {
  Bash: "Running command", Edit: "Editing", Write: "Writing", MultiEdit: "Editing",
  NotebookEdit: "Editing", Read: "Reading", Grep: "Searching", Glob: "Searching",
  WebFetch: "Browsing web", WebSearch: "Searching web", Task: "Delegating",
  TodoWrite: "Planning",
};

const safeId = (s) => String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";

let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  let p = {};
  try { p = JSON.parse(raw || "{}"); } catch {}

  // Off by default; CLAUDE_STATUSBAR_DEBUG=1 logs every hook invocation to hooks.log.
  if (process.env.CLAUDE_STATUSBAR_DEBUG === "1") {
    try {
      fs.mkdirSync(dir, { recursive: true });
      fs.appendFileSync(path.join(dir, "hooks.log"),
        `${new Date().toISOString()} [${event}] tool=${p.tool_name || "-"} mode=${p.permission_mode || "-"} msg=${JSON.stringify(p.message || "").slice(0, 160)} keys=${Object.keys(p).join(",")}\n`);
    } catch {}
  }

  // This session's own file is the unit of state AND the liveness marker. Writing it on any
  // event also tracks sessions that predate the hook install (never fired SessionStart).
  const sid = safeId(p.session_id);
  const statePath = path.join(stateDir, sid + ".json");

  // Read THIS session's prior state (not a shared global) so startedAt/transcript carry over
  // within the session and never bleed across concurrent sessions.
  let prev = {};
  try { prev = JSON.parse(fs.readFileSync(statePath, "utf8")); } catch {}

  const project = p.cwd ? path.basename(p.cwd) : prev.project || "";
  const ts = Math.floor(Date.now() / 1000);
  let state = "idle", label = "", startedAt = prev.startedAt || 0;

  switch (event) {
    case "prompt":
      state = "thinking"; label = "Thinking…"; startedAt = ts; break;
    case "pre": {
      const t = p.tool_name || "";
      // Known tools get a friendly verb; everything else (incl. long mcp__server__method
      // names) collapses to a generic "Using tool".
      state = "tool"; label = TOOL_LABELS[t] || "Using tool";
      if (!startedAt) startedAt = ts;
      break;
    }
    case "post":
      state = "thinking"; label = "Thinking…";
      if (!startedAt) startedAt = ts;
      break;
    case "notify": {
      // Only a permission prompt drives the icon here (CLI path; desktop uses permreq). Ignore
      // every other Notification (esp. the idle_prompt "Claude is waiting for your input") so the
      // icon rests instead of parking on a confusing "Waiting for you". See CLAUDE.md.
      const m = (p.message || "").toLowerCase();
      const isPerm = p.notification_type === "permission_prompt" ||
        m.includes("permission") || m.includes("approve") || m.includes("allow");
      if (!isPerm) return;
      state = "permission"; label = "Awaiting permission"; startedAt = 0;
      break;
    }
    case "permreq":
      // Desktop-app permission signal; not redundant with notify (that's CLI-only). See CLAUDE.md.
      state = "permission"; label = "Awaiting permission"; startedAt = 0; break;
    case "stop":
      state = "done"; label = "Done"; startedAt = 0; break;
    default:
      return;
  }

  // CLAUDE_CODE_ENTRYPOINT tags the surface running this session ("cli", "claude-desktop", …);
  // carried over from prev for the odd event where the env var isn't set.
  const entrypoint = process.env.CLAUDE_CODE_ENTRYPOINT || prev.entrypoint || "";
  // TERM_PROGRAM identifies the terminal app for a CLI session (Apple_Terminal, iTerm.app,
  // vscode, WezTerm, …); the app uses it to bring that terminal to the front on a row click.
  const termProgram = process.env.TERM_PROGRAM || prev.term_program || "";
  const tty = prev.tty || ttyDev();
  const out = { state, label, tool: p.tool_name || "", project, sessionId: p.session_id || "", transcript: p.transcript_path || prev.transcript || "", entrypoint, term_program: termProgram, tty, startedAt, ts };
  try {
    fs.mkdirSync(stateDir, { recursive: true });
    const tmp = statePath + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, statePath);
  } catch {}
});
