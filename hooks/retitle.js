#!/usr/bin/env node
// Conversation-based title generator. Called by update.js after a placeholder ("新对话" / "New Chat")
// session accumulates 3+ user turns. Reads the transcript to understand what
// the conversation is about, then asks the LLM for a short title.
// Usage: node retitle.js <session_id> <transcript_path>

const fs = require("fs");
const os = require("os");
const path = require("path");

const [,, sessionId, transcriptPath] = process.argv;
if (!sessionId || !transcriptPath) process.exit(1);

const dir = path.join(os.homedir(), ".claude", "statusbar");
const stateDir = path.join(dir, "state.d");
const sid = String(sessionId).replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64);
const titleFile = path.join(stateDir, sid + ".title");
const statePath = path.join(stateDir, sid + ".json");

// Debounce: skip if the title was updated less than 30 seconds ago.
try {
  const st = fs.statSync(titleFile);
  if ((Date.now() - st.mtimeMs) < 30_000) process.exit(0);
} catch {}

// ── Extract recent user messages from transcript ────────────────────
// Claude Code transcript uses: {"type":"user", "message":{"role":"user","content":"..."}}
// Tool results also have type=user/role=user but content is [{"type":"tool_result",...}] — skip those.
function extractMessages(transcriptPath) {
  const messages = [];
  try {
    const raw = fs.readFileSync(transcriptPath, "utf8");
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      try {
        const obj = JSON.parse(line);
        if (obj.type !== "user") continue;
        const msg = obj.message || {};
        if (msg.role !== "user") continue;
        const content = msg.content;
        // Real user prompts are plain strings. Tool results are arrays
        // whose first block is {"type":"tool_result",...} — skip those.
        if (typeof content === "string" && content.length > 0) {
          messages.push(content);
        } else if (Array.isArray(content)) {
          // Only count if the first block is a user text, not a tool_result.
          if (content.length > 0 && content[0].type !== "tool_result") {
            const text = content.map(b => (b && b.text) ? b.text : "").join(" ").trim();
            if (text) messages.push(text);
          }
        }
      } catch {}
    }
  } catch {}
  return messages;
}

const allMessages = extractMessages(transcriptPath);
if (allMessages.length === 0) process.exit(1);

// Last 5 user messages, each capped at 200 chars for the prompt.
const recent = allMessages.slice(-5).map(m => m.slice(0, 200));

const prompt = [
  "Below are the user's most recent messages in this Claude Code session.",
  "Generate a SHORT title (4-12 characters) summarizing what this session is about.",
  "Rules: prefer Chinese if the conversation is in Chinese; no quotes, no punctuation;",
  'no abbreviations like "I18n", "a11y", "cfg"; no code-style concatenations with + or -;',
  'no filler words like "session" or "chat"; output ONLY the title, max 12 characters.',
  "",
  "Recent messages:",
  ...recent.map((m, i) => `${i + 1}. ${m}`),
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
    const title = raw.slice(0, 12);
    if (!title || title === "新对话" || title === "New Chat") process.exit(1); // retry-worthy failure
    fs.mkdirSync(stateDir, { recursive: true });
    fs.writeFileSync(titleFile, title);
    // Patch the state file so the app reflects the title immediately.
    try {
      const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
      state.project = title;
      const tmp = statePath + ".retitle." + process.pid + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(state));
      fs.renameSync(tmp, statePath);
    } catch {}
    process.exit(0);
  })
  .catch(() => process.exit(1));
