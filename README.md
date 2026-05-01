# AxonFlow Plugin for Cursor IDE

**Runtime governance for Cursor: block dangerous commands before they run, scan every tool output for PII and secrets, and keep a compliance-grade audit trail — without leaving the editor.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

> **→ Full integration walkthrough:** **[docs.getaxonflow.com/docs/integration/cursor](https://docs.getaxonflow.com/docs/integration/cursor/)** — architecture, policy examples, latency numbers, troubleshooting, and the 10 MCP tools the platform exposes.

> **Upgrade strongly recommended.** AxonFlow ships substantial monthly security and quality hardening; staying on the latest major is the security-supported release line. [Latest release](https://github.com/getaxonflow/axonflow-cursor-plugin/releases/latest) · [Security advisories](https://github.com/getaxonflow/axonflow-cursor-plugin/security/advisories)

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

## Try AxonFlow on a real plugin rollout

We're opening limited **Plugin Design Partner** slots.

30-minute hook lifecycle review, policy pack scoping, override workflow design, and IDE/CLI rollout pattern walkthrough — for solo developers and small teams putting governance on Cursor.

[Apply here](https://getaxonflow.com/plugins/design-partner?utm_source=readme_plugin_cursor) or email [design-partners@getaxonflow.com](mailto:design-partners@getaxonflow.com). Personal email is fine — solo developers welcome.

### See AxonFlow in Action

Three short videos covering different angles of the platform:

- **[Community Quickstart Demo (Code + Terminal, 2.5 min)](https://youtu.be/BSqU1z0xxCo)** — governed calls, PII block, Gateway Mode with LangChain/CrewAI, and MAP from YAML
- **[Runtime Control Demo (Portal + Workflow, 3 min)](https://youtu.be/6UatGpn7KwE)** — approvals, retry safety, execution state, and the audit viewer
- **[Architecture Deep Dive (12 min)](https://youtu.be/Q2CZ1qnquhg)** — how the control plane works, policy enforcement flow, and multi-agent planning

### Plugin Evaluation Tier (Free 90-day License)

Outgrown Community on a real plugin install? Evaluation unlocks the capacity and features that matter for plugin users — without moving to Enterprise yet:

| Capability | Community | Evaluation (Free) | Enterprise |
|---|---|---|---|
| Tenant policies | 20 | 50 | Unlimited |
| Org-wide policies | 0 | 5 | Unlimited |
| Audit retention | 3 days | 14 days | Up to 10 years |
| HITL approval gates | — | 25 pending, 24h expiry | Unlimited, 24h |
| Evidence export (CSV/JSON) | — | 5,000 records · 14d window · 3/day | Unlimited |
| Policy simulation | — | 300/day | Unlimited |
| Session overrides (self-service unblock) | — | — | Enterprise-only |

Org-wide policies and session overrides are **Enterprise-only** — those are the actual upgrade triggers for plugin users.

[Get a free Plugin Evaluation license](https://getaxonflow.com/plugins/evaluation-license?utm_source=readme_plugin_cursor_eval)

---

## Privacy notice

**Read before installing.** AxonFlow [Community SaaS](https://docs.getaxonflow.com/docs/deployment/community-saas/) at `try.getaxonflow.com` is the zero-config endpoint the plugin uses if neither `AXONFLOW_ENDPOINT` nor `AXONFLOW_AUTH` is configured. In that mode, governed tool inputs (tool name + arguments) and outbound message bodies are checked by AxonFlow's policy enforcement endpoint. **Community SaaS is for early exploration only** — not for production workloads, regulated environments, real user data, personal data, or any other sensitive information. It is offered "as is" on a best-effort basis with no SLA, no warranties, and no commitment to retention, deletion, or incident-response timelines.

For any serious use, choose one of the following instead:

1. **[Self-host AxonFlow Community Edition](https://docs.getaxonflow.com/docs/deployment/self-hosted/)** — runs entirely on your infrastructure and keeps data within your boundary. Recommended for any real workload. The in-README quick start is in [Step 1](#step-1-install-the-axonflow-platform) below.
2. **Community Edition with an [Evaluation License](https://docs.getaxonflow.com/docs/deployment/evaluation-rollout-guide/)** — for production use with real users or clients on the open core; adds production-fit limits and license-gated features. Free 90-day [evaluation license](https://getaxonflow.com/plugins/evaluation-license).
3. **[AxonFlow Enterprise](https://docs.getaxonflow.com/docs/deployment/community-to-enterprise-migration/)** — production-grade governance, regulatory-grade controls, SLOs, and contractual commitments suitable for regulated industries. Contact [hello@getaxonflow.com](mailto:hello@getaxonflow.com).

To skip Community SaaS entirely: set `AXONFLOW_ENDPOINT` to a self-hosted AxonFlow URL. That alone flips the plugin into self-hosted mode — the Community SaaS auto-bootstrap is not attempted, and no env var is required. Get the AxonFlow platform from [getaxonflow/axonflow](https://github.com/getaxonflow/axonflow) and follow the [Getting Started](https://docs.getaxonflow.com/docs/getting-started/) guide for the Docker Compose setup. For air-gapped environments where AxonFlow is not yet reachable but you want to suppress the bootstrap attempt, set `AXONFLOW_COMMUNITY_SAAS=0`; set `AXONFLOW_TELEMETRY=off` to also disable the anonymous 7-day heartbeat.

LLM provider keys never leave the user's machine in any mode — Cursor handles every LLM call; AxonFlow only enforces policies and records audit trails.

---

## Install

This is a **three-step** install: stand up the AxonFlow platform, add the plugin to Cursor, then point the plugin at the platform. The plugin alone does not enforce policy — its hook scripts are thin clients that talk to an AxonFlow agent gateway. If the platform is not installed and reachable, governed tool calls have nothing to evaluate against. **Skipping Step 3 is the most common mistake**: the platform is running locally but the plugin still falls back to Community SaaS because no `AXONFLOW_ENDPOINT` is configured.

### Prerequisites

- [Cursor IDE](https://cursor.com)
- `jq` and `curl` on `PATH`

### Step 1: install the AxonFlow platform

For any real workload, run AxonFlow on your own infrastructure via Docker Compose:

```bash
git clone https://github.com/getaxonflow/axonflow.git
cd axonflow && docker compose up -d

# verify
curl -s http://localhost:8080/health | jq .
```

Follow the [Getting Started](https://docs.getaxonflow.com/docs/getting-started/) guide for prerequisites (Docker Engine or Desktop, Docker Compose v2, 4 GB RAM, 10 GB disk) and the [Self-Hosted Deployment Guide](https://docs.getaxonflow.com/docs/deployment/self-hosted/) for production options. For production with real users or clients, run Community Edition with a free 90-day [Evaluation License](https://docs.getaxonflow.com/docs/deployment/evaluation-rollout-guide/) or [AxonFlow Enterprise](https://docs.getaxonflow.com/docs/deployment/community-to-enterprise-migration/).

> Skipping Step 1 makes the plugin fall back to the [Community SaaS](https://docs.getaxonflow.com/docs/deployment/community-saas/) endpoint at `try.getaxonflow.com` for early exploration only. **Do not skip Step 1 for any real workload** — see the [Privacy notice](#privacy-notice) above.

### Step 2: install the plugin

```bash
# 1. Clone
git clone https://github.com/getaxonflow/axonflow-cursor-plugin.git

# 2. Install into Cursor's local plugin directory
cp -r axonflow-cursor-plugin ~/.cursor/plugins/local/axonflow-cursor-plugin

# 3. Reload Cursor (Cmd+Shift+P → "Developer: Reload Window")
# 4. Verify in Settings (Cmd+Shift+J) → Plugins → "Axonflow Cursor Plugin"
```

Symlinks don't work — Cursor requires a real copy.

### Step 3: point the plugin at the platform

Without this step the plugin auto-registers with Community SaaS regardless of whether you ran Step 1 — it does not auto-detect a locally-running AxonFlow. Set `AXONFLOW_ENDPOINT` (and `AXONFLOW_AUTH` if you have credentials):

```bash
# Self-hosted local agent — that alone flips mode to self-hosted, no other env var needed
export AXONFLOW_ENDPOINT=http://localhost:8080

# Self-hosted remote agent with credentials
export AXONFLOW_ENDPOINT=https://axonflow.your-company.com
export AXONFLOW_AUTH=$(echo -n "your-client-id:your-client-secret" | base64)

# Optional: longer request timeout for remote / VPN deployments
export AXONFLOW_TIMEOUT_SECONDS=12
```

Every hook invocation logs a one-line canary on stderr confirming the active mode:

```
[AxonFlow] Connected to AxonFlow at http://localhost:8080 (mode=self-hosted)
```

If the canary says `mode=community-saas` after you ran Step 1, the plugin is still hitting `try.getaxonflow.com` because Step 3 was skipped or `AXONFLOW_ENDPOINT` is unset. Fix Step 3 and reload.

---

## Mode-specific reference

The recommended self-hosted path is covered in [Install Step 1](#step-1-install-the-axonflow-platform). Two more modes worth knowing about:

### Community SaaS — for early exploration only

The plugin's zero-config fallback when neither `AXONFLOW_ENDPOINT` nor `AXONFLOW_AUTH` is configured. The plugin registers a tenant with `try.getaxonflow.com` on first run and persists credentials at `~/.config/axonflow/try-registration.json` (mode `0600`).

**Use only for early exploration of the plugin's behaviour. Not for production workloads, regulated environments, real user data, personal data, or any other sensitive information.**

| What goes to `try.getaxonflow.com` | What does NOT |
|---|---|
| Tool name + arguments before each governed call | LLM provider API keys |
| Outbound message bodies before delivery (PII/secret scan) | Cursor conversation history outside governed tools |
| Anonymous 7-day heartbeat (plugin version, OS, runtime) | Files outside the Cursor runtime |

The endpoint runs against shared Ollama models, rate-limits at 20 req/min · 500 req/day per tenant, and is offered "as is" on a best-effort basis with no SLA, no warranties, no commitment to retention or deletion timelines, and may be modified or discontinued without notice. Read the [Try AxonFlow — Free Trial Server](https://docs.getaxonflow.com/docs/deployment/community-saas/) page for the full disclosure, including [data retention](https://docs.getaxonflow.com/docs/deployment/community-saas/#limitations-and-disclaimers) and [registration mechanics](https://docs.getaxonflow.com/docs/deployment/community-saas/#registration).

### Air-gapped: zero outbound

For environments where no outbound traffic is permitted at all — air-gapped labs, regulated networks, classified deployments — set both env vars before the Cursor process starts:

```bash
export AXONFLOW_COMMUNITY_SAAS=0   # disable Community SaaS auto-bootstrap
export AXONFLOW_TELEMETRY=off      # disable the anonymous 7-day heartbeat
export AXONFLOW_ENDPOINT=http://your-internal-axonflow:8080
```

With both env vars set and `AXONFLOW_ENDPOINT` pointing at a same-network instance, no traffic leaves your environment.

---

## Configure

[Step 3](#step-3-point-the-plugin-at-the-platform) above covers `AXONFLOW_ENDPOINT`, `AXONFLOW_AUTH`, and `AXONFLOW_TIMEOUT_SECONDS`. Other connection options:

For Evaluation License or Enterprise credentials, set both endpoint and auth:

```bash
export AXONFLOW_ENDPOINT=https://your-axonflow.example.com
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
│   ├── pre-tool-check.sh    # Policy evaluation (PreToolUse)
│   ├── post-tool-audit.sh   # Audit + PII scan (PostToolUse)
│   ├── mcp-auth-headers.sh  # Basic-auth header generation for MCP
│   └── telemetry-ping.sh    # Anonymous telemetry (fires once per install)
└── tests/
    ├── test-hooks.sh        # Regression tests (mock + live)
    ├── E2E_TESTING_PLAYBOOK.md
    └── e2e/                 # Smoke E2E against live AxonFlow
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

For the broader validation story — explain-decision, override lifecycle, audit-filter parity, cache invalidation — see the [Cursor integration guide](https://docs.getaxonflow.com/docs/integration/cursor/).

---

## Troubleshooting

**Plugin doesn't show in settings?** Cursor loads local plugins from `~/.cursor/plugins/local/`. The plugin must be a real copy (symlinks do not work). After copying, run "Developer: Reload Window" or restart Cursor.

**Hooks not firing?** Check the Hooks tab in Cursor Settings. Common issues: missing `"version": 1` in `hooks/hooks.json`; hook matcher using `Bash` instead of `Shell` (Cursor uses `Shell`); plugin directory not at `~/.cursor/plugins/local/axonflow-cursor-plugin`.

**PII in file writes not detected?** Cursor writes files via shell commands (`printf > file`). The `beforeShellExecution` hook scans write content for PII. Set `PII_ACTION` to control behavior: `redact` (default — blocks and instructs the agent to rewrite), `block`, `warn`, or `log`.

More troubleshooting in the [integration guide](https://docs.getaxonflow.com/docs/integration/cursor/#troubleshooting).

---

## Telemetry

Anonymous heartbeat at most once every 7 days per machine: plugin version, OS, architecture, bash version, AxonFlow platform version, deployment mode (community-saas / self-hosted production / self-hosted development). **Never** tool arguments, message contents, or policy data. The stamp file mtime advances only after the HTTP POST returns 2xx, so a transient network failure does not silence telemetry until the next window.

Opt out: set `AXONFLOW_TELEMETRY=off` in the environment Cursor runs in.

`DO_NOT_TRACK` is **not** honored as an opt-out for AxonFlow telemetry. It is commonly inherited from host tools and developer environments, which makes it an unreliable expression of user intent.

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
