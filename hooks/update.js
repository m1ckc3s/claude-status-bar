#!/usr/bin/env node
// Invoked by Claude Code hooks. Reads the hook JSON payload on stdin, maps the
// event to a status, and atomically writes ~/.claude/statusbar/state.json.
// Usage: node update.js <prompt|pre|post|notify|permreq|stop>

const fs = require("fs");
const os = require("os");
const path = require("path");

const dir = path.join(os.homedir(), ".claude", "statusbar");
const statePath = path.join(dir, "state.json");
const event = process.argv[2] || "";

const TOOL_LABELS = {
  Bash: "Running command", Edit: "Editing", Write: "Writing", MultiEdit: "Editing",
  NotebookEdit: "Editing", Read: "Reading", Grep: "Searching", Glob: "Searching",
  WebFetch: "Browsing web", WebSearch: "Searching web", Task: "Delegating",
  TodoWrite: "Planning",
};

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

  // Register the session here too, so a session that predates the hook install (never
  // fired SessionStart) still gets tracked once it does anything. See CLAUDE.md gotcha.
  const sid = String(p.session_id || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64);
  if (sid) {
    try {
      const sessDir = path.join(dir, "sessions.d");
      fs.mkdirSync(sessDir, { recursive: true });
      fs.writeFileSync(path.join(sessDir, sid), "");
    } catch {}
  }

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
      const m = (p.message || "").toLowerCase();
      if (m.includes("permission") || m.includes("approve") || m.includes("allow")) {
        state = "permission"; label = "Awaiting permission";
      } else if (m.includes("waiting")) {
        state = "waiting"; label = "Waiting for you";
      } else {
        state = "waiting"; label = p.message || "Waiting";
      }
      startedAt = 0;
      break;
    }
    case "permreq":
      // PermissionRequest fires the instant the approval dialog is shown, in BOTH the
      // CLI and the Desktop app (unlike Notification, which is CLI-only). Fires ~30ms
      // after `pre` so it correctly overrides the running state with the dot. On approve,
      // `post` clears it; on deny nothing fires, so the next prompt/tool/stop clears it.
      state = "permission"; label = "Awaiting permission"; startedAt = 0; break;
    case "stop":
      state = "done"; label = "Done"; startedAt = 0; break;
    default:
      return;
  }

  const out = { state, label, tool: p.tool_name || "", project, sessionId: p.session_id || "", transcript: p.transcript_path || prev.transcript || "", startedAt, ts };
  try {
    fs.mkdirSync(dir, { recursive: true });
    const tmp = statePath + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, statePath);
  } catch {}
});
