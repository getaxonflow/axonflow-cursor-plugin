# AxonFlow Plugin for Cursor IDE

**Runtime governance for Cursor: block dangerous commands before they run, scan every tool output for PII and secrets, and keep a compliance-grade audit trail — without leaving the editor.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

> **→ Full integration walkthrough:** **[docs.getaxonflow.com/docs/integration/cursor](https://docs.getaxonflow.com/docs/integration/cursor/)** — architecture, policy examples, latency numbers, troubleshooting, and the 15 MCP tools the platform exposes.

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
| A governed call when AxonFlow cannot decide | Not addressed | **A rejected credential, a limit, a refusal or an unreachable agent blocks the call ([posture](#when-axonflow-cannot-decide))** |
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
    ├─ BLOCKED (exit 2) → Cursor receives the denial with decision_id (stderr,
    │                     and the deny JSON on stdout); agent can call explain_decision
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

**When AxonFlow cannot decide:** a rejected credential, a limit, a refusal, and (by default, on Cursor) an unreachable agent block the tool call. PostToolUse never blocks; it tells the agent not to use an output it could not check. The full table is in [When AxonFlow cannot decide](#when-axonflow-cannot-decide).

---

## Where this kicks in during daily IDE use

### 1. The governed-unblock workflow

Your IDE is where developers feel the tension between safety and speed most sharply. A terse "blocked" on a shell command wastes minutes every time.

**With the plugin:** the deny message carries `decision_id`. The developer can ask Cursor to call `explain_decision` to see exactly which policy family triggered, without leaving the IDE. Changing the verdict is an administrator's edit to the organization's policy: session overrides are retired from AxonFlow v11.0.0.

### 2. The MCP query that returns too much

A dev connects Cursor to a production PostgreSQL MCP server for debugging. Results stream into the conversation with customer names, emails, and phone numbers. Session logs aren't structured for audit.

**With the plugin:** `check_policy` fires before the query runs (SQL-injection scan, sensitive-operation scan), `check_output` scans the result for PII, and `audit_tool_call` records everything with matched policies and decision ID. Search via `search_audit_events` later.

### 3. The editor config that shouldn't be writable

Governance has to survive the *next* developer too. Cursor's `.cursor/settings.json` and `.cursorrules` shape agent behavior — if an agent can rewrite them, governance is one hook modification away from being bypassed.

**With the plugin:** Cursor-specific integration policies activate when `AXONFLOW_INTEGRATIONS=cursor` (or automatically on detection) — `.cursor/settings.json` writes are blocked, `.cursor-plugin/*.json` and `.mdc` rule modifications are flagged.

---

## Take a governed plugin rollout into production

Solo developers and self-serve teams can use the free 90-day [Plugin Evaluation License](https://getaxonflow.com/plugins/evaluation-license?utm_source=readme_plugin_cursor_eval) to validate hook behavior and policy packs.

### See AxonFlow in Action

Videos covering different angles of the platform:

- **[Product demos: Platform + Fraud & Risk](https://getaxonflow.com/demo/?utm_source=github&utm_medium=readme&utm_campaign=product_demo&utm_content=axonflow-cursor-plugin)** - runtime enforcement, HITL approvals, audit evidence, cost visibility, and agentic payment controls
- **[Community Quickstart walkthrough (2 min)](https://youtu.be/BSqU1z0xxCo)** - governed calls, PII blocking, Gateway Mode with LangChain/CrewAI, and MAP from YAML
- **[Architecture deep dive (12 min)](https://youtu.be/Q2CZ1qnquhg)** - how the control plane works, policy enforcement flow, and multi-agent planning

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

Org-wide policies are **Enterprise-only**, the actual upgrade trigger for plugin users. Session overrides are retired from AxonFlow v11.0.0 in every edition.

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

# Optional (Enterprise): admin-minted per-user token for a VERIFIED
# {identity, role} — role-scoped access instead of client-scoped-only
# attribution. See "Per-user authorization token" below.
export AXONFLOW_USER_TOKEN=<token minted by your org admin>
```

## Pro tier license token (`AXONFLOW_LICENSE_TOKEN`)

Plugin Pro extends the Free baseline (3-day audit retention, 200 governed events / day, 2 active custom policies, 1 HITL approval per rolling 7d) to **30-day retention**, **2,000 events / day**, **unlimited active custom policies**, **unlimited HITL approvals**, and adds the **LLM cost pre-flight** tool (estimate token cost for a multi-step plan before it runs). 90-day window, one-time **$9.99 USD** payment, no auto-renewal, 14-day no-questions refund. See [getaxonflow.com/pricing](https://getaxonflow.com/pricing/) for the full breakdown and the Stripe buy button.

To activate Pro on this Cursor install:

1. **Find your client ID.** From the plugin install root, run:

    ```bash
    cd ~/.cursor/plugins/local/axonflow-cursor-plugin
    bash scripts/status.sh
    ```

    The output includes a `client_id:  cs_<uuid>` line — that's the value Stripe Checkout needs. Copy it. (Same value the v1.4.x output called `tenant_id`; renamed in v1.5.0 for consistency with the rest of AxonFlow's v9 terminology.) Or ask the agent in chat: "what is my AxonFlow client ID?" (both "client ID" and "tenant ID" still work) — the [`axonflow-status` skill](#cursor-skills) will run the script for you and surface the value.

2. **Buy at the pricing page.** Visit [getaxonflow.com/pricing](https://getaxonflow.com/pricing/) and click **Buy Plugin Pro — $9.99**. At Stripe Checkout, paste your `client_id` into the **AxonFlow tenant ID** custom field. (The Stripe form's field label is still "AxonFlow tenant ID" — same value, the label will be renamed in a future release.)

3. **Install the issued license token.** After checkout you'll receive an `AXON-...` token by email. The plugin forwards it as the `X-License-Token` header on every governed agent call once it's loaded. Two ways to load it (token-resolution order described below):

The plugin reads the token in this order — first match wins:

1. `AXONFLOW_LICENSE_TOKEN` environment variable (drop into your shell profile for cross-session persistence).
2. `~/.config/axonflow/license-token` file (mode `0600` inside the same `0700` directory the community-saas registration lives in). Convenient when you don't want the token in your shell history; safe-mode-only — files with looser permissions are refused with a stderr warning.

When a token is loaded, the mode-clarity canary appends a `Pro tier active` suffix so it's visible at a glance:

```
[AxonFlow] Connected to AxonFlow at http://localhost:8080 (mode=self-hosted) — Pro tier active
```

The free / community tier behaviour is unchanged when no token is set — the plugin sends no `X-License-Token` header and the agent treats the request as free-tier.

### Check status (`scripts/status.sh`)

Need your `client_id` (to paste into the Stripe Checkout custom field at `https://getaxonflow.com/pricing/`)? Want to confirm whether your Pro license token is loaded? Run:

```bash
cd ~/.cursor/plugins/local/axonflow-cursor-plugin
bash scripts/status.sh
```

Sample output (free tier):

```
AxonFlow Cursor plugin — status

  endpoint           https://try.getaxonflow.com
  mode               community-saas
  client_id:         cs_a1b2c3d4-...  (formerly tenant_id)
  registration file  /home/you/.config/axonflow/try-registration.json
  license token      unset
  tier               Free
  upgrade            https://getaxonflow.com/pricing/

To upgrade to Pro, copy your client_id above, visit
https://getaxonflow.com/pricing/, paste the client_id into the Stripe checkout custom field
(currently labeled "Your AxonFlow tenant ID" on the Stripe form),
and complete checkout. ...
```

Sample output (Pro tier):

```
  license token      set (AXON-...wxyz, source=env)
  tier               Pro
```

The license token is **always** redacted to its last 4 chars. The full token is never printed — output is safe to screen-share or paste into a support ticket.

In the chat, use the `/axonflow-status` skill to have the agent run this for you and surface the `client_id` and tier.

> **Tip:** the same information is available without spawning a shell — just ask the agent "what's my AxonFlow client ID?" (or "tenant ID" — both phrasings still work) and it will call the agent-side `axonflow_get_tenant_id` MCP tool (the wire name keeps its `_tenant_id` suffix for backwards compatibility), which returns the same identifier, the server-resolved tier, and the upgrade URLs. Other agent-callable Pro-related tools include `axonflow_list_pro_features` ("what would I get if I upgraded?") and `axonflow_get_cost_estimate` (Pro-only LLM cost pre-flight). Auto-discovered via the existing MCP HTTP transport — no extra wiring.

### Free-tier limits and upgrade prompts

When the plugin's hooks hit a Free-tier cap (200 events/day, 2 active custom policies, 1 HITL approval per rolling 7d, or a Pro-only feature), the agent returns a structured upgrade envelope. The plugin parses it and prints a single-line nudge to stderr — visible in Cursor's hook log:

```
[AxonFlow] Daily limit reached on Free tier (200 events). Pro raises this to 2,000/day. Resets at midnight UTC.
[AxonFlow] Upgrade: https://buy.stripe.com/bJe28qbztcdVchjdkw8k800
```

The plugin also stamps the shared back-off file ([below](#when-axonflow-cannot-decide)). A request-rate limit (`daily_quota`, `per_minute`) blocks governed calls locally, with no request sent, for at most 300 seconds after it was stamped; then the plugin asks the platform again, which answers the limit again if it still holds. A feature or object-count limit (`feature_pro_only`, `active_policies`, `hitl_approvals_window`, `decision_list_size`) shows its nudge and blocks nothing beyond the call it answered. The upgrade nudge is shown at most once per UTC day so it doesn't spam every hook.

### Recovering lost credentials (`scripts/recover-credentials.sh`)

If you lose your `~/.config/axonflow/try-registration.json` (deleted by mistake, switched machines, hit the unsafe-permissions guard, etc.), run the recovery helper from the plugin install directory:

```bash
cd ~/.cursor/plugins/local/axonflow-cursor-plugin
bash scripts/recover-credentials.sh
```

The script prompts for the email the tenant was originally registered with, requests a magic link via `POST /api/v1/recover` (which always returns `202` to defend against email enumeration), waits for you to paste either the magic-link URL or the bare token from the email, calls `POST /api/v1/recover/verify`, and writes the new credentials to `~/.config/axonflow/try-registration.json` with mode `0600`. The community-saas bootstrap picks them up on the next governed tool call — no shell re-export, no Cursor reload.

In the chat, use the `/recover-credentials` skill to have the agent walk you through the same flow. The skill instructs the agent to invoke the script via the Shell tool; you fill in the email and token in the integrated terminal.

Recovery is for **free-tier credential loss only**. If you lose your Pro `AXONFLOW_LICENSE_TOKEN`, recover it from the original Stripe / billing email rather than this script.

---

## Per-user authorization token (`AXONFLOW_USER_TOKEN`)

By default, a fleet of Cursor developers sharing one `AXONFLOW_AUTH` credential
is attributed as the *tenant*, not as individual people. The **per-user token**
fixes that with a verified identity. On an Enterprise platform that validates
per-user tokens (first platform release after v9.9.0), an org admin mints a
token per developer (`POST /api/v1/admin/organizations/{org_id}/user-tokens`,
or OIDC tokens from your IdP), and the plugin sends it as the `X-User-Token`
header on every governed request — the MCP connection and both hooks. The
platform validates it (signature, expiry, revocation, org binding) and
resolves a **non-forgeable `{identity, role}`** for the developer: audit rows
attribute to the verified identity, and role-scoped features (e.g. who can
read the whole tenant's audit trail vs. only their own rows) key on the
validated role instead of treating every fleet developer identically.

Resolution precedence on the **hook surfaces** (`pre-tool-check.sh`,
`post-tool-audit.sh` — mirrors the license-token discipline):

1. **`AXONFLOW_USER_TOKEN`** — set per developer via managed settings / MDM
   (fleet) or the shell profile (individual). Wins outright.
2. **`~/.config/axonflow/user-token.json`** — `{"token": "<minted token>"}`,
   written by your fleet's provisioning tooling. The file **must be `0600`**
   (owner read/write only); the plugin refuses a group/world-readable token
   file with a stderr warning rather than loading it silently:

   ```bash
   umask 077
   printf '{"token":"%s"}' "<minted token>" > ~/.config/axonflow/user-token.json
   chmod 600 ~/.config/axonflow/user-token.json
   ```

3. **Unset** — no `X-User-Token` header is sent (never an empty header) and
   requests are exactly what a pre-1.6 plugin sends; the platform keeps its
   least-privilege attribution path.

> **Cursor-specific: the MCP connection is env-var-only.** The MCP server
> connection Cursor itself opens uses `mcp.json`'s *static* headers with plain
> env expansion — Cursor has no dynamic header helper — so that plane reads
> `${AXONFLOW_USER_TOKEN}` from the environment **only**: the `0600` file
> fallback covers the hook surfaces, not the MCP connection. When the env var
> is unset, Cursor expands the header to an empty value, which the platform
> treats as absent — unconfigured users are unaffected. But a **malformed**
> env value (mis-paste with whitespace/quotes) is sent **raw** by Cursor on
> this plane — the platform then fails closed with `401` on MCP traffic until
> you fix or remove the env var. The hooks drop a malformed value locally and
> warn on stderr instead. Fleet provisioning that needs the MCP plane covered
> must therefore set the env var (MDM / managed settings), not just the file.

### Capability handshake on the MCP connection (`AXONFLOW_PEP_AUDIENCE`)

The hooks send the ADR-065 capability handshake (`X-Axonflow-PEP-Handshake`) whenever `AXONFLOW_PEP_AUDIENCE` is set. Cursor's MCP connection cannot compute it: `mcp.json` has static headers only, and an unset variable becomes an **empty** header value, which the platform refuses as malformed (HTTP 400, `pep_handshake_malformed`). So the shipped `mcp.json` carries **no** handshake header. To give the MCP connection the handshake, run this from the installed plugin directory after setting the audience, then reload Cursor:

```bash
cd ~/.cursor/plugins/local/axonflow-cursor-plugin
AXONFLOW_PEP_AUDIENCE=<your audience> bash scripts/configure-mcp-handshake.sh
```

It writes the declaration the hooks send (`pep_id` `cursor-plugin`, an empty capability list) into that `mcp.json`. With it, a governed MCP call that would carry a mandatory redaction obligation is refused (`block_reason: unsupported_obligation`) instead of being allowed with a `redacted_message` nothing substitutes. Run it without `AXONFLOW_PEP_AUDIENCE` to remove the header, and again whenever the audience changes. A malformed audience removes the header and exits non-zero. The script builds the declaration from `AXONFLOW_PEP_AUDIENCE` only; if `AXONFLOW_PEP_HANDSHAKE` is already set in the hooks' environment, the hooks send that value as it is, while the MCP entry gets only what this script writes. A symlinked `mcp.json` is written through to its target, which keeps its mode; a file you cannot write is refused and left unchanged. The write replaces the file, so another hard link to it keeps the old content.

The token is a **credential**: the plugin never logs or echoes its value, and
on the hook surfaces a malformed candidate (whitespace/control/quote bytes — a
mis-paste) is dropped locally with a diagnostic instead of being sent. Note
the platform **fails closed** on a presented-but-invalid token (expired,
revoked, minted for a different org): governed calls are then blocked until
the token is rotated or removed — the block message names the token as the
likely cause. Rotation/revocation is admin-driven on the platform;
re-provisioning the new token to the developer's env/file is all the plugin
needs.

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

## The 15 MCP tools Cursor can call

Beyond automatic hooks, the agent's MCP server exposes **15 tools** Cursor can invoke directly. All served by the platform at `/api/v1/mcp-server` — the plugin's `mcp.json` just points Cursor there. New platform tools are auto-discovered via the existing MCP HTTP transport.

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
| `create_override` | **Retired from AxonFlow v11.0.0**: answers a tool error beginning `LEGACY_POLICY_WRITE_FROZEN: ` (or, with no per-user identity on the session, the identity refusal) and creates nothing |
| `delete_override` | **Retired from AxonFlow v11.0.0**: answers the same tool error |
| `list_overrides` | List the overrides recorded for the caller's tenant (an unchanged read; from v11.0.0 an override changes no verdict) |

### Tenant identity & tier capability (5 — V1 Plugin Pro)

| Tool | Free access | Pro access |
|------|-------------|------------|
| `axonflow_get_tenant_id` | Visible + callable — returns tenant_id, server-resolved tier, upgrade URL | Same |
| `axonflow_list_pro_features` | Visible + callable — locked Pro feature list (5 differentiators + $9.99 / 90-day pricing) | Same |
| `axonflow_request_approval` | Visible + 1 per rolling 7d | Unlimited |
| `axonflow_create_tenant_policy` | Visible + 2 active max | Unlimited |
| `axonflow_get_cost_estimate` | Filtered out of `tools/list` — Pro-only | Visible + callable |

When a Free-tier cap is hit on these tools, the agent returns a structured upgrade envelope (same shape as the 429 daily-quota envelope) and the plugin surfaces the upgrade prompt to stderr — see [Free-tier limits and upgrade prompts](#free-tier-limits-and-upgrade-prompts).

**After a block:** the deny carries the `decision_id`; ask Cursor to call `explain_decision` to see which policy fired and why. **Session overrides are retired from AxonFlow v11.0.0:** no override changes a verdict, and a retry does not succeed because one was requested. What changes a verdict is an administrator's edit to the policy in the organization's typed policy document (a shipped system control is in its `system_controls` section), through `/api/v1/typed-policies`.

---

## When AxonFlow cannot decide

Every governed call gets one of these answers. PreToolUse blocks by exiting 2, which Cursor documents as a deny, and also prints Cursor's documented deny JSON on stdout (`{"permission":"deny","user_message":...,"agent_message":...}`, shown to the user and sent to the agent). Which of the two Cursor reads on exit 2 has not been verified in a Cursor session; exit 2 blocks on its own. PostToolUse never blocks: when it could not check an output it tells the agent not to use it, in Cursor's documented `additional_context` (and in `hookSpecificOutput.additionalContext`, the shape the hook emitted before).

| AxonFlow's answer | PreToolUse | PostToolUse |
|---|---|---|
| A policy decision (a JSON-RPC result on any HTTP status but 401 and 429) | as decided: a deny blocks | a deny or a redaction is a governance alert |
| A result that decides nothing (no boolean `allowed`, or `isError`) | **blocked** | alert |
| **HTTP 401**, with or without a per-user token, and the cooldown it starts | **blocked**, quoting the agent; the cooldown blocks locally for 300 seconds (`_AXONFLOW_AUTH_FAILURE_COOLDOWN_SECONDS`), naming the seconds left and the file to delete | alert |
| **HTTP 429**, with or without the Free-tier envelope, and a request-rate limit stamp | **blocked**, the limit named | alert |
| A refusal: a redirect, a 4xx other than 408 without a decision (402 and 413 included), a JSON-RPC error other than `-32603` / `-32700` | **blocked** | alert |
| The check request could not be built | **blocked** | alert |
| **No usable answer**: unreachable, timeout, 408, 5xx, `-32603` / `-32700`, an empty or unreadable body, not exactly one JSON document, `jq` or `curl` missing, and Community SaaS with no credential because the registration did not complete (no request is sent and no stamp written) | **blocked** (the default). With `AXONFLOW_FAIL_MODE=open`: runs, with a notice on stderr only | alert. With `open`: passes, notice on stderr only |
| Hook input that is not a JSON object | **blocked** | alert |
| `scripts/lib/failure-posture.sh` missing (a broken install) | **blocked**, naming the file | alert, naming it |

- **On Cursor, an unreachable AxonFlow blocks by default.** Cursor's hook contract shows the person a message only when a call is denied ([Cursor Docs: Hooks](https://cursor.com/docs/hooks): `user_message` is "shown to user when denied"), so a call that ran ungoverned could not be shown to them at all. **`AXONFLOW_FAIL_MODE=open`** (any case) lets such calls run anyway; under it the call runs **silently to the person, by the host's design**: the notice goes to stderr, which Cursor does not document showing. Unset, empty, `closed` and any other value block. The switch never loosens a 401, a 429, a refusal or a policy deny. This default differs from the Claude Code and Codex plugins, where `open` is the default, because those hosts can show a notice for a call that runs.
- **What a broken hook does.** Cursor documents exit code 2 as a deny and any other non-zero exit as a non-blocking error: a pre hook that exits 2 before printing anything denies the call, and one that dies with any other exit (not executable, a missing interpreter, killed at the timeout) lets the call run. Cursor also blocks a permission hook whose output is invalid JSON or does not match its schema. This hook prints at most one JSON document, exits 2 on every block but the shell-write redaction (its deny JSON on exit 0), and keeps its work inside the timeout (a 13-second budget against the 15-second `hooks.json` timeout).
- **PostToolUse reads what Cursor documents:** `postToolUse`'s `tool_output` is a JSON-encoded string (parsed; a string that is not JSON is scanned as it came), `afterFileEdit`'s `edits[].new_string` is scanned, `afterShellExecution`'s `output` would be read if that event were registered (this plugin's `hooks/hooks.json` does not register it: shell output reaches the hook through `postToolUse`), and the legacy object `tool_response` (`{stdout, exitCode}`) is still read. Before this change the hook read only the legacy object, so documented `postToolUse` outputs and `afterFileEdit` edits went unscanned.
- **The shared back-off file** is `${XDG_CACHE_HOME:-$HOME/.cache}/axonflow/throttle-until`, one line, `<epoch> <limit_type>`. The Cursor, Claude Code and Codex hooks (and, on Linux, the OpenClaw plugin) read and write the same file, so a stamp written by one plugin can block another. This plugin honours an `auth_failure` stamp for its own 300-second cooldown after the file was written, whatever deadline the file carries, and a request-rate limit (`daily_quota`, `per_minute`) for at most 300 seconds after it was written (a stamp written more than 60 seconds in the future counts as past that); any other stamp blocks nothing here and is left on disk for the plugin that wrote it. The file is removed when its deadline passes. After fixing a credential, delete it to retry at once.
- **Nothing is skipped for lack of content.** A call whose input has nothing to check (an MCP call with no arguments, a NotebookEdit delete, an empty command) is checked as the tool's name plus the input's plain fields.
- **The audit record** a PostToolUse call sends carries `success` only when the tool's result says how it ended (a numeric `exitCode` or a boolean `success`).

---

## Free-tier limits and upgrade prompts

When the plugin's hooks hit a Free-tier cap (200 events/day, 2 active custom policies, 1 HITL approval per rolling 7d, or a Pro-only feature), the agent returns a structured upgrade envelope. The plugin parses it and prints a single-line nudge to stderr — for example:

```
[AxonFlow] Daily limit reached on Free tier (200 events). Pro raises this to 2,000/day. Resets at midnight UTC.
[AxonFlow] Upgrade: https://buy.stripe.com/bJe28qbztcdVchjdkw8k800
```

The plugin also stamps the shared back-off file ([below](#when-axonflow-cannot-decide)). A request-rate limit (`daily_quota`, `per_minute`) blocks governed calls locally, with no request sent, for at most 300 seconds after it was stamped; then the plugin asks the platform again, which answers the limit again if it still holds. A feature or object-count limit (`feature_pro_only`, `active_policies`, `hitl_approvals_window`, `decision_list_size`) shows its nudge and blocks nothing beyond the call it answered. The upgrade nudge is shown at most once per UTC day so it doesn't spam every hook.

---

## Skills and rules

The plugin ships skills (invocable explicitly) and `.mdc` rules (always-on context):

**Skills:** `check-governance`, `audit-search`, `policy-stats`, `pii-scan`, `governance-status`, `policy-list`, `axonflow-status`

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

Same governance platform, same 80+ policies, same 15 MCP tools — different agent hosts:

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
│   ├── pre-tool-check.sh    # Policy enforcement (PreToolUse)
│   ├── post-tool-audit.sh   # Audit + PII scan (PostToolUse)
│   ├── mcp-auth-headers.sh  # Basic-auth header generation for MCP
│   └── telemetry-ping.sh    # Anonymous heartbeat (at most once per 7 days)
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

Anonymous heartbeat at most once every 7 days per machine: plugin version, OS, architecture, bash version, AxonFlow platform version, the licence tier that platform reports about itself, deployment mode (`community_saas` / `self_hosted` / `unknown`), and endpoint type (`localhost` / `private_network` / `remote` / `unknown`). **Never** tool arguments, message contents, or policy data. The stamp file mtime advances only after the HTTP POST returns 2xx, so a transient network failure does not silence telemetry until the next window.

The licence tier sent is whatever the platform reported about itself, relayed verbatim. The plugin does not normalise, map, or restrict the value, so a transient state such as `starting`, or a tier name introduced after this plugin shipped, reaches the wire unchanged rather than being flattened into a fixed list. What is never read or sent: **no licence key, no expiry date, no seat count, and no customer or organisation name**. It is read from the `tier` field of the `/health` response the heartbeat already fetches to detect the platform version, so it costs no additional request, and it is omitted entirely whenever that probe does not answer with one.

Two further values are relayed on the same terms, from the same response: the platform's **edition** and the deployment mode the **platform reports about itself**. The second is deliberately separate from the `deployment_mode` above, which is this plugin's own classification of the endpoint it was pointed at — they answer different questions and routinely differ, so neither is written over the other. Both are omitted entirely whenever the platform does not report them, which is the case for every platform released before they existed. Any relayed value longer than 64 bytes — measured in bytes, not characters — is dropped whole rather than truncated, since a truncated value would be something the platform never said, and a value containing a NUL is dropped for the same reason.

The heartbeat does not follow HTTP redirects on either leg, and only a **2xx** counts on either leg. A redirected or erroring `/health` teaches the plugin nothing — its body is not read at all, even when it carries one — rather than relaying values from a response your platform never meant as an answer. A redirected or rejected checkpoint POST is not treated as a delivery: the 7-day stamp advances only on a 2xx, so neither can silence telemetry for a week on a ping that was never received.

Opt out: set `AXONFLOW_TELEMETRY=off` in the environment Cursor runs in.

### Scope of `AXONFLOW_TELEMETRY=off`

`AXONFLOW_TELEMETRY=off` disables the anonymous heartbeat described above. On **self-hosted** and **in-VPC** deployments, that heartbeat is the only data the plugin sends to AxonFlow, so setting `=off` means we receive nothing. On **Community SaaS** (`try.getaxonflow.com`) the hosted service also processes operational data — registrations, audit logs, policy enforcement records, workflow state, plan data, and request-header metadata aggregated for usage analytics — as part of running the platform; that operational data flow is governed by the [Privacy Policy](https://getaxonflow.com/privacy/), not by `AXONFLOW_TELEMETRY`.

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
