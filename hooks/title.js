#!/usr/bin/env node
// LLM-powered session title generator. Called from lifecycle.js on SessionStart.
// Reads project context from cwd, asks the LLM for a 2-4 word title, caches it.
// When no project descriptor files exist, writes a placeholder ("新对话"/"New Chat");
// retitle.js will generate a real title later from conversation content.
// Usage: node title.js <session_id> <cwd>

const fs = require("fs");
const os = require("os");
const path = require("path");

const [,, sessionId, cwd] = process.argv;
if (!sessionId || !cwd) process.exit(1);

const dir = path.join(os.homedir(), ".claude", "statusbar");
const stateDir = path.join(dir, "state.d");
const sid = String(sessionId).replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64);
const titleFile = path.join(stateDir, sid + ".title");
const statePath = path.join(stateDir, sid + ".json");

// Already generated for this session — don't waste an API call.
if (fs.existsSync(titleFile)) process.exit(0);

// ── Gather project context ──────────────────────────────────────────
const DESCRIPTOR_FILES = [
  "CLAUDE.md", "README.md", "README.org", "readme.md",
  "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
  "Gemfile", "Makefile", "docker-compose.yml", "Dockerfile",
];

function gatherContext(cwd) {
  const files = [];
  for (const name of DESCRIPTOR_FILES) {
    try {
      const raw = fs.readFileSync(path.join(cwd, name), "utf8");
      files.push({ name, preview: raw.slice(0, 400) });
    } catch {}
  }
  return files;
}

const context = gatherContext(cwd);
const dirBasename = path.basename(cwd);

// Placeholder label: locale-aware so non-Chinese users see "New Chat".
const NEW_CHAT = (process.env.LANG || process.env.LC_ALL || "").startsWith("zh") ? "新对话" : "New Chat";

// ── Function to update state file atomically ─────────────────────────
function patchState(projectTitle) {
  try {
    const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
    state.project = projectTitle;
    state.dirName = dirBasename;
    const tmp = statePath + ".title." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(state));
    fs.renameSync(tmp, statePath);
  } catch {}
}

// No descriptor files found — label with placeholder; retitle.js handles the rest.
if (context.length === 0) {
  fs.mkdirSync(stateDir, { recursive: true });
  fs.writeFileSync(titleFile, NEW_CHAT);
  patchState(NEW_CHAT);
  process.exit(0);
}

const prompt = [
  `The working directory is named "${dirBasename}".`,
  "Below are previews of key files found in this directory:",
  ...context.map(f => `--- ${f.name} ---\n${f.preview}`),
  "",
  'Give this coding/AI session a VERY SHORT descriptive title.',
  'Rules: 2-4 words; prefer Chinese if the project content is in Chinese; no quotes, no punctuation, no "Project" or "Session" filler.',
  "Output ONLY the title, nothing else.",
].join("\n");

// ── Call LLM ─────────────────────────────────────────────────────────
const baseUrl = (process.env.ANTHROPIC_BASE_URL || "https://api.anthropic.com").replace(/\/$/, "");
const apiKey = process.env.ANTHROPIC_AUTH_TOKEN || "";
const model = process.env.ANTHROPIC_MODEL || "claude-sonnet-4-6";

fetch(baseUrl + "/v1/messages", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01",
  },
  body: JSON.stringify({
    model,
    max_tokens: 60,
    messages: [{ role: "user", content: prompt }],
    thinking: { type: "disabled" },
  }),
})
  .then(r => {
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  })
  .then(data => {
    const blocks = data.content || [];
    const textBlock = blocks.find(b => b.type === "text") || blocks[0] || {};
    const raw = (textBlock.text || textBlock.thinking || "").replace(/["'\n]/g, "").trim();
    const title = raw.slice(0, 30) || dirBasename;
    fs.mkdirSync(stateDir, { recursive: true });
    fs.writeFileSync(titleFile, title);
    patchState(title);
    process.exit(0);
  })
  .catch(() => process.exit(1));
