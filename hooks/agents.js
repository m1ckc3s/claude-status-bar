#!/usr/bin/env node
// SubagentStart/SubagentStop hooks. Usage: node agents.js <start|stop>  (hook JSON on stdin)
//
// One tiny file per RUNNING subagent: ~/.claude/statusbar/state.d/<session_id>.agents.d/<agent_id>.json
// created on SubagentStart, removed on SubagentStop. Files are independent (atomic tmp+rename),
// so parallel subagents never race a shared file. update.js/lifecycle.js clear the whole dir on
// prompt/stop/session boundaries, so a missed SubagentStop (interrupt, crash) can't leave stale
// entries past the turn.

const fs = require("fs");
const os = require("os");
const path = require("path");

const dir = path.join(os.homedir(), ".claude", "statusbar");
const stateDir = path.join(dir, "state.d");
const event = process.argv[2];

const safeId = (s) => String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";

const writeAtomic = (file, obj) => {
  const tmp = file + "." + process.pid + ".tmp"; // no .json suffix: the app ignores it mid-write
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
  let p = {};
  try { p = JSON.parse(input || "{}"); } catch {}

  if (process.env.CLAUDE_STATUSBAR_DEBUG === "1") {
    try {
      fs.appendFileSync(path.join(dir, "hooks.log"),
        `${new Date().toISOString()} [agents:${event}] agent=${p.agent_id || "-"} type=${p.agent_type || "-"} keys=${Object.keys(p).join(",")}\n`);
    } catch {}
  }

  // Without both ids there is nothing to key the file on — bail rather than write "unknown".
  if (!p.session_id || !p.agent_id) process.exit(0);
  const agentsDir = path.join(stateDir, safeId(p.session_id) + ".agents.d");
  const agentPath = path.join(agentsDir, safeId(p.agent_id) + ".json");

  if (event === "start") {
    const ts = Math.floor(Date.now() / 1000);
    // task is the delegation prompt Claude wrote; keep a one-line snippet for the row + tooltip.
    const task = String(p.task || "").replace(/\s+/g, " ").trim().slice(0, 200);
    try {
      fs.mkdirSync(agentsDir, { recursive: true });
      writeAtomic(agentPath, {
        agentType: String(p.agent_type || ""),
        task,
        parentAgentId: p.parent_agent_id ? String(p.parent_agent_id) : "",
        startedAt: ts,
        ts,
      });
    } catch {}
  } else if (event === "stop") {
    try { fs.rmSync(agentPath, { force: true }); } catch {}
    // Last one out sweeps the shell (fails silently while siblings still run). Subagents can
    // outlive the parent turn (they run in the background), so the turn-boundary reaps in
    // update.js may have already emptied the dir — this catches the straggler's leftover.
    try { fs.rmdirSync(agentsDir); } catch {}
  }
  process.exit(0);
}
