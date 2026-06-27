#!/usr/bin/env node
// Invoked by Claude Code hooks. Reads the hook JSON payload on stdin, maps the
// event to a status, and atomically writes a PER-SESSION file:
//   ~/.claude/statusbar/state.d/<session_id>.json
// The app reads every file in state.d/ and aggregates them (see Sources/main.swift).
// Usage: node update.js <prompt|pre|post|notify|permreq|stop>

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const dir = path.join(os.homedir(), ".claude", "statusbar");
const stateDir = path.join(dir, "state.d");
const prefsPath = path.join(dir, "prefs.json");
const event = process.argv[2] || "";

const TOOL_LABELS = {
  Bash: "Running command", Edit: "Editing", Write: "Writing", MultiEdit: "Editing",
  NotebookEdit: "Editing", Read: "Reading", Grep: "Searching", Glob: "Searching",
  WebFetch: "Browsing web", WebSearch: "Searching web", Task: "Delegating",
  TodoWrite: "Planning",
};

const safeId = (s) => String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";

// Read titleMode preference. Defaults to "llm" if the file doesn't exist.
function readTitleMode() {
  try { const p = JSON.parse(fs.readFileSync(prefsPath, "utf8")); return p.titleMode || "llm"; } catch { return "llm"; }
}

// Spawn retitle.js in background to generate a title from conversation content.
function spawnRetitle(sid, transcriptPath) {
  if (!transcriptPath) return;
  const node = process.execPath;
  const script = path.join(dir, "retitle.js");
  if (!fs.existsSync(script)) return;
  cp.spawn(node, [script, sid, transcriptPath], {
    stdio: "ignore",
    detached: true,
    env: process.env,
  }).unref();
}

let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  let p = {};
  try { p = JSON.parse(raw || "{}"); } catch {}

  if (process.env.CLAUDE_STATUSBAR_DEBUG === "1") {
    try {
      fs.mkdirSync(dir, { recursive: true });
      fs.appendFileSync(path.join(dir, "hooks.log"),
        `${new Date().toISOString()} [${event}] tool=${p.tool_name || "-"} mode=${p.permission_mode || "-"} msg=${JSON.stringify(p.message || "").slice(0, 160)} keys=${Object.keys(p).join(",")}\n`);
    } catch {}
  }

  const sid = safeId(p.session_id);
  const statePath = path.join(stateDir, sid + ".json");

  let prev = {};
  try { prev = JSON.parse(fs.readFileSync(statePath, "utf8")); } catch {}

  // ── Project / title resolution ───────────────────────────────────
  let project = "";
  const titleMode = readTitleMode();
  if (titleMode === "folder") {
    project = p.cwd ? path.basename(p.cwd) : prev.project || "";
  } else {
    const titleFile = path.join(stateDir, sid + ".title");
    try { project = fs.readFileSync(titleFile, "utf8").trim(); } catch {}
    project = project || (p.cwd ? path.basename(p.cwd) : prev.project || "");
  }

  const ts = Math.floor(Date.now() / 1000);
  let state = "idle", label = "", startedAt = prev.startedAt || 0;

  switch (event) {
    case "prompt":
      state = "thinking"; label = "Thinking…"; startedAt = ts; break;
    case "pre": {
      const t = p.tool_name || "";
      state = "tool"; label = TOOL_LABELS[t] || "Using tool";
      if (!startedAt) startedAt = ts;
      break;
    }
    case "post":
      state = "thinking"; label = "Thinking…";
      if (!startedAt) startedAt = ts;
      break;
    case "notify": {
      const m = (p.message || "").toLowerCase();
      const isPerm = p.notification_type === "permission_prompt" ||
        m.includes("permission") || m.includes("approve") || m.includes("allow");
      if (!isPerm) return;
      state = "permission"; label = "Awaiting permission"; startedAt = 0;
      break;
    }
    case "permreq":
      state = "permission"; label = "Awaiting permission"; startedAt = 0; break;
    case "stop":
      state = "done"; label = "Done"; startedAt = 0; break;
    default:
      return;
  }

  const entrypoint = process.env.CLAUDE_CODE_ENTRYPOINT || prev.entrypoint || "";
  const termProgram = process.env.TERM_PROGRAM || prev.term_program || "";
  const transcript = p.transcript_path || prev.transcript || "";
  // dirName is the raw folder basename — always stored so the app can switch
  // between "Smart" / "Folder" modes in real time without re-running hooks.
  const dirName = p.cwd ? path.basename(p.cwd) : prev.dirName || project;
  const out = { state, label, tool: p.tool_name || "", project, dirName, sessionId: p.session_id || "", transcript, entrypoint, term_program: termProgram, startedAt, ts };
  try {
    fs.mkdirSync(stateDir, { recursive: true });
    const tmp = statePath + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, statePath);
  } catch {}

  // ── Per-message retitle: spawn on every prompt ──────────────────
  if (event === "prompt" && titleMode === "llm") {
    spawnRetitle(sid, transcript);
  }
});
