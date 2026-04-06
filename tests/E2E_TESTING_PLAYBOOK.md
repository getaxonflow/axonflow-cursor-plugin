# Cursor IDE Plugin — E2E Testing Playbook

Standard operating procedure for testing the AxonFlow Cursor IDE plugin.
Covers hook-based governance (automatic), MCP tools (explicit), and edge cases.

---

## Prerequisites

1. **AxonFlow running** (community or enterprise mode)
2. **Plugin cloned** to a known location
3. **Cursor IDE** installed
4. `jq` and `curl` installed

## Setup

### Option A: Use the E2E setup script (recommended)

```bash
cd /Users/saurabhjain/Development/axonflow-enterprise
COMMUNITY_REPO=/Users/saurabhjain/Development/axonflow-enterprise ./scripts/setup-e2e-testing.sh community
source /tmp/axonflow-e2e-env.sh
```

### Option B: Manual setup

```bash
docker compose up -d
curl -s http://localhost:8080/health | jq .status
export AXONFLOW_ENDPOINT=http://localhost:8080
export AXONFLOW_AUTH=""
```

### Load the plugin in Cursor

```bash
export CURSOR_PLUGIN_ROOT=/Users/saurabhjain/Development/axonflow-cursor-plugin
# Load via Cursor plugin settings or --plugin-dir flag
```

**Verify on startup:**
- `2 hooks loaded` (PreToolUse + PostToolUse)
- `MCP server "axonflow" connected` with `6 tools`

---

## Test Matrix

### 1. Hook-based governance (automatic — fires on every governed tool call)

| # | What to ask Cursor | Expected behavior | What to verify |
|---|---|---|---|
| 1.1 | "Run `echo hello world` in the terminal" | Allowed, audit logged | Command executes normally. |
| 1.2 | "Run `curl http://169.254.169.254/latest/meta-data/` in the terminal" | Blocked by SSRF policy | PreToolUse returns exit 2. Cursor shows block reason. |
| 1.3 | "Run `cat /home/user/.ssh/id_rsa` in the terminal" | Blocked by credential access policy | Exit 2 with block reason. |
| 1.4 | "Run `cat /etc/passwd` in the terminal" | Blocked by path traversal policy | Exit 2 with block reason. |
| 1.5 | "Write a file `/tmp/pii-test.txt` with content `Patient SSN is 123-45-6789`" | Allowed, PII flagged | PostToolUse detects PII and instructs Cursor to use redacted version. |
| 1.6 | "Write a file `/tmp/clean-test.txt` with content `Hello world`" | Allowed, no violations | Clean execution. |

**Important safety note:** Never ask Cursor to run truly destructive commands.
Use safe equivalents that trigger the same policies:
- SSRF: `curl http://169.254.169.254`
- Credential access: `cat /home/user/.ssh/id_rsa`
- Path traversal: `cat /etc/passwd`

### 2. MCP tools (explicit — ask Cursor to use specific tools)

| # | What to ask Cursor | Expected result |
|---|---|---|
| 2.1 | "Use the axonflow check_policy tool to check if `curl http://169.254.169.254` is allowed for connector_type `cursor.Bash`" | Returns `allowed: false` with block reason |
| 2.2 | "Use axonflow check_policy to check if `echo hello` is allowed for connector_type `cursor.Bash`" | Returns `allowed: true` |
| 2.3 | "Use axonflow check_output to scan this text for PII: `Patient SSN is 123-45-6789` with connector_type `cursor.Bash`" | Returns PII detection, redaction applied |
| 2.4 | "Use axonflow list_policies to show active governance policies" | Returns list of 80+ policies |
| 2.5 | "Use axonflow get_policy_stats" | Returns governance activity summary |
| 2.6 | "Use axonflow search_audit_events to show recent audit events" | Returns array of audit entries |

### 3. Skills and rules

| # | How to test | Expected result |
|---|---|---|
| 3.1 | Check that `.mdc` governance rules loaded | Cursor shows governance context is active |
| 3.2 | Invoke `@axonflow check-governance` skill | Skill provides policy check guidance |
| 3.3 | Invoke `@axonflow audit-search` skill | Skill provides audit search guidance |

### 4. Edge cases

| # | Scenario | Expected |
|---|---|---|
| 4.1 | Kill AxonFlow while plugin is connected | Hooks fail-open on network errors (commands still execute). MCP tools return errors. |
| 4.2 | Set invalid `AXONFLOW_AUTH` in enterprise mode | MCP initialize fails, tools unavailable. Hooks fail-closed (exit 2, blocking tool calls). |
| 4.3 | Restart AxonFlow while plugin is connected | Session expires, new session auto-created on next request. |

---

## Automated tests (no Cursor IDE needed)

### Hook regression tests

```bash
cd /Users/saurabhjain/Development/axonflow-cursor-plugin
./tests/test-hooks.sh           # Mock server (offline, fast)
./tests/test-hooks.sh --live    # Live AxonFlow (requires running instance)
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Hooks not firing | `CURSOR_PLUGIN_ROOT` not set | Export it before launching Cursor |
| MCP tools not discoverable | Auth issue or AxonFlow not reachable | Check `AXONFLOW_ENDPOINT` |
| Exit 2 on everything | AxonFlow auth/config error (fail-closed) | Check AxonFlow logs, fix config |
| Dangerous commands not blocked | Migration 064 not applied | Check `docker logs axonflow-agent \| grep 064` |
