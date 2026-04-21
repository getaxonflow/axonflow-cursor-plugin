# AxonFlow Plugin for Cursor IDE

**Runtime governance for Cursor: block dangerous commands before they run, scan every tool output for PII and secrets, and keep a compliance-grade audit trail — without leaving the editor.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

> **→ Full integration walkthrough:** **[docs.getaxonflow.com/docs/integration/cursor](https://docs.getaxonflow.com/docs/integration/cursor/)** — architecture, policy examples, latency numbers, troubleshooting, and the 10 MCP tools the platform exposes.

---

## Why you'd add this

Cursor is the fastest-growing AI code editor — VS Code with deep AI integration, native MCP support, terminal execution, multi-file edits. It's excellent at developer productivity. It was never designed to be the layer where your security and compliance team lives.

The gaps start surfacing the moment Cursor moves from one developer's laptop to a team or production setting:

| Production requirement | Cursor alone | With this plugin |
|---|---|---|
| Policy enforcement before tool execution | Hooks available, no governance logic | **80+ built-in policies evaluated on every governed tool call** |
| Dangerous command blocking in the terminal | Terminal runs anything | **Reverse shells, `rm -rf /`, `curl \| bash`, cloud metadata, credential access — all blocked** |
| PII / secrets detection in tool outputs | Developer responsibility | **Auto-scan; agent instructed to use redacted version** |
| SQL-injection detection on MCP queries | MCP server's problem | **30+ patterns evaluated on every MCP tool call** |
| Compliance-grade audit trail | Session logs, not compliance-formatted | **Every governed call recorded with policies, decision, duration** |
| Decision explainability after a block | Generic hook failure message | **`decision_id` surfaced in stderr; `explain_decision` MCP tool returns the full record** |
| Self-service, time-bounded exceptions | Not available | **`create_override` with mandatory justification, fully audited** |
| File-write protection for editor config | Not addressed | **`.cursor/settings.json` and `.cursorrules` protected by policy** |

You get all of that with no change to how developers use Cursor. Hooks fire on every governed tool call, the deny message tells you why, and MCP tools are there when you want to investigate or unblock.

---

## How it works

```
Cursor selects a tool (Shell, Write, Edit, MCP, etc.)
    │
    ▼
PreToolUse hook fires automatically
    │ → check_policy("cursor.Shell", "curl 169.254.169.254")
    │
    ├─ BLOCKED (exit 2) → Cursor receives denial with decision_id + risk_level
    │                     in stderr; agent can call explain_decision / create_override
    │
    └─ ALLOWED (exit 0) → Tool executes normally
                      │
                      ▼
                 PostToolUse hook fires automatically
                      │ → audit_tool_call(tool, input, output)  [non-blocking]
                      │ → check_output(tool result for PII/secrets)
                      │
                      ├─ Sensitive data found → agent instructed to use
                      │                          redacted version in its reply
                      └─ Clean → Silent
```

**Governed tools:** `Shell`, `Write`, `Edit`, `Read`, `Task`, `NotebookEdit`, and all MCP tools (`mcp__*`). Cursor maps Claude Code's `Bash` tool to `Shell`.

**Fail behavior:**
- AxonFlow unreachable (network) → fail-open, tool execution continues
- AxonFlow auth/config error → fail-closed (exit 2), tool call blocked until config is fixed
- PostToolUse failures → never block (audit and PII scan are best-effort)

---

## Where this kicks in during daily IDE use

### 1. The governed-unblock workflow

Your IDE is where developers feel the tension between safety and speed most sharply. A terse "blocked" on a shell command wastes minutes every time.

**With the plugin:** the deny message carries `decision_id` and `risk_level` in stderr. The developer can ask Cursor to call `explain_decision` to see exactly which policy family triggered. If the decision is overridable, `create_override` produces a time-bounded, audit-logged exception with mandatory justification — without leaving the IDE or opening a separate admin surface.

### 2. The MCP query that returns too much

A dev connects Cursor to a production PostgreSQL MCP server for debugging. Results stream into the conversation with customer names, emails, and phone numbers. Session logs aren't structured for audit.

**With the plugin:** `check_policy` fires before the query runs (SQL-injection scan, sensitive-operation scan), `check_output` scans the result for PII, and `audit_tool_call` records everything with matched policies and decision ID. Search via `search_audit_events` later.

### 3. The editor config that shouldn't be writable

Governance has to survive the *next* developer too. Cursor's `.cursor/settings.json` and `.cursorrules` shape agent behavior — if an agent can rewrite them, governance is one hook modification away from being bypassed.

**With the plugin:** Cursor-specific integration policies activate when `AXONFLOW_INTEGRATIONS=cursor` (or automatically on detection) — `.cursor/settings.json` writes are blocked, `.cursor-plugin/*.json` and `.mdc` rule modifications are flagged.

---

## Install

### Prerequisites

- [Cursor IDE](https://cursor.com)
- [AxonFlow](https://github.com/getaxonflow/axonflow) v6.0.0+ running (`docker compose up -d`)
- `jq` and `curl` on `PATH`

### Install the plugin

```bash
# 1. Clone
git clone https://github.com/getaxonflow/axonflow-cursor-plugin.git

# 2. Install into Cursor's local plugin directory
cp -r axonflow-cursor-plugin ~/.cursor/plugins/local/axonflow-cursor-plugin

# 3. Reload Cursor (Cmd+Shift+P → "Developer: Reload Window")
# 4. Verify in Settings (Cmd+Shift+J) → Plugins → "Axonflow Cursor Plugin"
```

Symlinks don't work — Cursor requires a real copy.

### Start AxonFlow

The plugin connects to AxonFlow, a self-hosted governance platform. **No LLM provider keys are required** — Cursor handles every LLM call; AxonFlow only evaluates policies and records audit trails.

```bash
git clone https://github.com/getaxonflow/axonflow.git
cd axonflow && docker compose up -d

# verify
curl -s http://localhost:8080/health | jq .
```

See [Getting Started](https://docs.getaxonflow.com/docs/getting-started/) for production deployment options.

---

## Configure

```bash
export AXONFLOW_ENDPOINT=http://localhost:8080
export AXONFLOW_AUTH=""                # empty for community mode
export AXONFLOW_TIMEOUT_SECONDS=12     # optional: remote/VPN deployments
```

In community mode (`DEPLOYMENT_MODE=community`), no auth is needed. For enterprise credentials:

```bash
export AXONFLOW_AUTH=$(echo -n "your-client-id:your-client-secret" | base64)
```

---

## What gets checked

AxonFlow ships with **80+ built-in system policies** that apply to Cursor automatically. No configuration required — new policies added to the platform are immediately enforced.

| Category | Coverage |
|---|---|
| **Dangerous commands** | Reverse shells, `rm -rf /`, `curl \| bash`, credential file access (`cat ~/.ssh/`, `cat ~/.aws/`), path traversal |
| **SQL injection** | 30+ patterns including UNION injection, stacked queries, auth bypass, encoding tricks |
| **PII detection** | SSN, credit card, Aadhaar, PAN, email, phone, NRIC/FIN (Singapore), and more — with redaction |
| **Secrets exposure** | API keys, connection strings, hardcoded credentials, code secrets |
| **SSRF** | Cloud metadata endpoint (`169.254.169.254`) and internal-network blocking |
| **Prompt injection** | Instruction override, jailbreak attempts, role hijacking |
| **Cursor-specific** | `.cursor/settings.json` write protection, `.cursorrules` and `.mdc` rule-file modification warnings |

Custom policies are easy — `POST /api/v1/dynamic-policies` or the Customer Portal. See [Policy Enforcement](https://docs.getaxonflow.com/docs/mcp/policy-enforcement/).

---

## The 10 MCP tools Cursor can call

Beyond automatic hooks, the agent's MCP server exposes **10 tools** Cursor can invoke directly. All served by the platform at `/api/v1/mcp-server` — the plugin's `mcp.json` just points Cursor there.

### Governance (6)

| Tool | Purpose |
|------|---------|
| `check_policy` | Evaluate specific inputs against policies |
| `check_output` | Scan specific content for PII/secrets |
| `audit_tool_call` | Record an additional audit entry |
| `list_policies` | List active governance policies |
| `get_policy_stats` | Summary of governance activity |
| `search_audit_events` | Search individual audit records for debugging and compliance |

### Decision explainability & session overrides (4)

| Tool | Purpose |
|------|---------|
| `explain_decision` | Return the full [DecisionExplanation](https://docs.getaxonflow.com/docs/governance/explainability/) for a decision ID |
| `create_override` | Create a time-bounded, audit-logged session override (mandatory justification) |
| `delete_override` | Revoke an active session override |
| `list_overrides` | List active overrides scoped to the caller's tenant |

See [Session Overrides](https://docs.getaxonflow.com/docs/governance/overrides/).

---

## Skills and rules

The plugin ships skills (invocable explicitly) and `.mdc` rules (always-on context):

**Skills:** `check-governance`, `audit-search`, `policy-stats`, `pii-scan`, `governance-status`, `policy-list`

**Rules:** `axonflow-governance.mdc` — injected into every conversation so Cursor knows governance is active and how to react when tools are blocked or PII is detected.

---

## Latency

| Operation | Typical overhead |
|-----------|-----------------|
| Policy pre-check | 2–5 ms |
| PII detection | 1–3 ms |
| SQL-injection scan | 1–2 ms |
| Audit write (async) | 0 ms (non-blocking) |
| **Total per-tool overhead** | **3–10 ms** |

Imperceptible in an IDE session.

---

## Sister integrations

Same governance platform, same 80+ policies, same 10 MCP tools — different agent hosts:

| Integration | Repo | Docs |
|---|---|---|
| Cursor IDE | *this repo* | [cursor](https://docs.getaxonflow.com/docs/integration/cursor/) |
| Claude Code | [axonflow-claude-plugin](https://github.com/getaxonflow/axonflow-claude-plugin) | [claude-code](https://docs.getaxonflow.com/docs/integration/claude-code/) |
| OpenAI Codex | [axonflow-codex-plugin](https://github.com/getaxonflow/axonflow-codex-plugin) | [codex](https://docs.getaxonflow.com/docs/integration/codex/) |
| OpenClaw | [axonflow-openclaw-plugin](https://github.com/getaxonflow/axonflow-openclaw-plugin) | [openclaw](https://docs.getaxonflow.com/docs/integration/openclaw/) |

---

## Plugin structure

```
axonflow-cursor-plugin/
├── .cursor-plugin/
│   └── plugin.json         # Plugin metadata
├── mcp.json                # MCP server connection (points at the platform)
├── hooks/
│   └── hooks.json          # PreToolUse + PostToolUse hook definitions
├── skills/
│   ├── check-governance/
│   ├── audit-search/
│   ├── policy-stats/
│   ├── pii-scan/
│   ├── governance-status/
│   └── policy-list/
├── rules/
│   └── axonflow-governance.mdc  # Always-on governance context
├── scripts/
│   ├── pre-tool-check.sh   # Policy evaluation (PreToolUse)
│   ├── post-tool-audit.sh  # Audit + PII scan (PostToolUse)
│   └── telemetry-ping.sh   # Anonymous telemetry (fires once per install)
└── tests/
    ├── test-hooks.sh       # Regression tests (mock + live)
    └── e2e/                # Smoke E2E against live AxonFlow
```

---

## Testing

```bash
# Hook regression tests (no live stack required)
./tests/test-hooks.sh

# Smoke E2E against a live AxonFlow at localhost:8080
bash tests/e2e/smoke-block-context.sh
```

The smoke scenario runs the plugin's `pre-tool-check.sh` against a running platform, feeds a SQLi-bearing Bash tool invocation through it, and asserts Cursor's deny semantics (exit 2 + stderr prefix `AxonFlow policy violation`) carry the richer-context markers (`decision:`, `risk:`). Exits 0 with `SKIP:` if no stack is reachable.

Full install-and-use matrix lives in `axonflow-enterprise/tests/e2e/plugin-batch-1/cursor-install/`.

---

## Troubleshooting

**Plugin doesn't show in settings?** Cursor loads local plugins from `~/.cursor/plugins/local/`. The plugin must be a real copy (symlinks do not work). After copying, run "Developer: Reload Window" or restart Cursor.

**Hooks not firing?** Check the Hooks tab in Cursor Settings. Common issues: missing `"version": 1` in `hooks/hooks.json`; hook matcher using `Bash` instead of `Shell` (Cursor uses `Shell`); plugin directory not at `~/.cursor/plugins/local/axonflow-cursor-plugin`.

**PII in file writes not detected?** Cursor writes files via shell commands (`printf > file`). The `beforeShellExecution` hook scans write content for PII. Set `PII_ACTION` to control behavior: `redact` (default — blocks and instructs the agent to rewrite), `block`, `warn`, or `log`.

More troubleshooting in the [integration guide](https://docs.getaxonflow.com/docs/integration/cursor/#troubleshooting).

---

## Telemetry

Anonymous one-time ping on first hook invocation: plugin version, OS, architecture, bash version, AxonFlow platform version. **Never** tool arguments, message contents, or policy data.

Opt out:
- `DO_NOT_TRACK=1` (standard)
- `AXONFLOW_TELEMETRY=off`

Guarded by a stamp file at `$HOME/.cache/axonflow/cursor-plugin-telemetry-sent` (delete to re-send). Details: [docs.getaxonflow.com/docs/telemetry](https://docs.getaxonflow.com/docs/telemetry/).

---

## Links

- **[Cursor Integration Guide](https://docs.getaxonflow.com/docs/integration/cursor/)** — the full walkthrough (recommended starting point)
- [AxonFlow Documentation](https://docs.getaxonflow.com)
- [Policy Enforcement](https://docs.getaxonflow.com/docs/mcp/policy-enforcement/)
- [Decision Explainability](https://docs.getaxonflow.com/docs/governance/explainability/)
- [Session Overrides](https://docs.getaxonflow.com/docs/governance/overrides/)
- [Self-Hosted Deployment](https://docs.getaxonflow.com/docs/deployment/self-hosted/)
- [Security Best Practices](https://docs.getaxonflow.com/docs/security/best-practices/)
- Sister plugins: [Claude Code](https://github.com/getaxonflow/axonflow-claude-plugin) · [Codex](https://github.com/getaxonflow/axonflow-codex-plugin) · [OpenClaw](https://github.com/getaxonflow/axonflow-openclaw-plugin)

## License

MIT
