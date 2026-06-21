#!/usr/bin/env node
// Invoked by Claude Code hooks. Reads the hook JSON payload on stdin, maps the
// event to a status, and atomically writes ~/.claude/statusbar/state.json.
// Usage: node update.js <prompt|pre|post|notify|stop>

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

  // Optional debug log of every hook invocation (event, tool, message, payload keys).
  // Off by default; enable with CLAUDE_STATUSBAR_DEBUG=1 to inspect what fires.
  if (process.env.CLAUDE_STATUSBAR_DEBUG === "1") {
    try {
      fs.mkdirSync(dir, { recursive: true });
      fs.appendFileSync(path.join(dir, "hooks.log"),
        `${new Date().toISOString()} [${event}] tool=${p.tool_name || "-"} mode=${p.permission_mode || "-"} msg=${JSON.stringify(p.message || "").slice(0, 160)} keys=${Object.keys(p).join(",")}\n`);
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
