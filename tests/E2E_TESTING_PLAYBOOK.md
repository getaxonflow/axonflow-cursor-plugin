# Cursor IDE Plugin — E2E Testing Playbook

Standard operating procedure for testing the AxonFlow Cursor IDE plugin.
Covers hook-based governance (enforced), advisory governance (skills), MCP tools, and known limitations.

---

## Prerequisites

1. **AxonFlow running** (community or enterprise mode)
2. **Plugin cloned** at `/Users/saurabhjain/Development/axonflow-cursor-plugin`
3. **Cursor IDE** installed (v1.7+)
4. `jq` and `curl` installed

## Setup

### Step 1: Start AxonFlow

```bash
cd /Users/saurabhjain/Development/axonflow-enterprise
COMMUNITY_REPO=/Users/saurabhjain/Development/axonflow-enterprise ./scripts/setup-e2e-testing.sh community
source /tmp/axonflow-e2e-env.sh
```

### Step 2: Install the plugin locally

Cursor loads local plugins from `~/.cursor/plugins/local/`. Copy the plugin there:

```bash
rm -rf ~/.cursor/plugins/local/axonflow-cursor-plugin
cp -r /Users/saurabhjain/Development/axonflow-cursor-plugin ~/.cursor/plugins/local/axonflow-cursor-plugin
```

**Note:** Symlinks do not work for Cursor local plugins — must be a real copy. After making changes to the plugin source, re-copy and reload Cursor.

### Step 3: Reload Cursor

Run `Developer: Reload Window` (Cmd+Shift+P) or quit and reopen Cursor.

### Step 4: Verify plugin loaded

Go to Settings (Cmd+Shift+J) → Plugins. You should see:

- **Axonflow Cursor Plugin** (Local)
- MCPs: 1 (Axonflow)
- Skills: 3 (audit-search, check-governance, policy-stats)
- Rules: 1 (axonflow-governance)

---

## Governance Model

| Type | Scope | Mechanism | Enforced? |
|------|-------|-----------|-----------|
| **Enforcement** | Shell commands | `preToolUse` hook (matcher: Shell) + `beforeShellExecution` hook | **Yes** — exit 2 blocks |
| **Enforcement** | All tools | `preToolUse` hook (fires for Shell, Read, Write, MCP, Task) | **Yes** — exit 2 blocks |
| **Audit** | Shell commands | `postToolUse` + `afterShellExecution` hooks | Automatic |
| **Audit** | File edits | `afterFileEdit` hook | Automatic |
| **Advisory** | All tools | Skills instruct agent to call check_policy/check_output | Agent decides |

**Key difference from Codex:** Cursor's `preToolUse` fires for ALL tools (Shell, Read, Write, MCP, Task, Delete), not just Bash. This means governance can enforce policy on file writes and reads too.

---

## Test Matrix

### 1. Shell command enforcement (hooks — enforced)

| # | What to ask Cursor | Expected behavior | Verified? |
|---|---|---|---|
| 1.1 | "Run `echo hello world` in the terminal" | Allowed. Hook fires, command executes, audit recorded. | Yes — executes normally |
| 1.2 | "Run `cat /etc/passwd` in the terminal" | Blocked by `sys_dangerous_path_traversal`. Hook returns exit 2. Cursor shows block reason. | Yes — blocked, 90 policies evaluated |
| 1.3 | "Run `cat ~/.ssh/id_rsa` in the terminal" | Blocked by credential access policy. Cursor shows "Block credential file and environment variable access". | Yes — blocked, 90 policies evaluated |
| 1.4 | "Run `curl http://169.254.169.254/latest/meta-data/` in the terminal" | Blocked by SSRF policy. Cursor may also self-block at model level. | Not yet tested |

### 2. File write governance (hooks — enforced via preToolUse)

| # | What to ask Cursor | Expected behavior | Verified? |
|---|---|---|---|
| 2.1 | "Write a file `/tmp/pii-test.txt` with content `Patient SSN is 123-45-6789`" | `preToolUse` fires for Write tool. Policy check runs. PII detected. `afterFileEdit` fires for audit. | Not yet tested |
| 2.2 | "Write a file `/tmp/clean-test.txt` with content `Hello world`" | Allowed. No violations. `afterFileEdit` fires for audit. | Not yet tested |

**Note:** Unlike Codex (which can only hook Bash), Cursor's `preToolUse` fires for Write/Read/Shell/MCP/Task tools. This means file write PII detection can be enforced, not just advisory.

### 3. MCP tools (explicit)

| # | What to ask Cursor | Expected result | Verified? |
|---|---|---|---|
| 3.1 | "Use the axonflow check_policy tool to check if `cat /etc/shadow` is allowed for connector_type `cursor.Shell`" | `allowed: false`, `blocked_by: "sys_dangerous_path_traversal"` | Not yet tested |
| 3.2 | "Use axonflow check_policy to check if `echo hello` is allowed for connector_type `cursor.Shell`" | `allowed: true` | Not yet tested |
| 3.3 | "Use axonflow check_output to scan this text for PII: `Patient SSN is 123-45-6789` with connector_type `cursor.Shell`" | `redacted_message: "Patient SSN is 1*********9"` | Not yet tested |
| 3.4 | "Use axonflow list_policies to show active governance policies" | Returns 80+ active policies | Not yet tested |
| 3.5 | "Use axonflow get_policy_stats" | Returns governance summary with total_events, compliance_score | Not yet tested |
| 3.6 | "Use axonflow search_audit_events to show recent audit events" | Returns audit entries with tool names, inputs, outputs, timestamps | Not yet tested |

### 4. Skills and rules

| # | How to test | Expected result | Verified? |
|---|---|---|---|
| 4.1 | Check Settings → Plugins → Axonflow → Rules | `axonflow-governance` rule visible and active | Yes — shows in plugin details |
| 4.2 | Type `/check-governance` in chat | Skill activates and guides policy checking | Not yet tested |
| 4.3 | Type `/audit-search` in chat | Skill activates and guides audit search | Not yet tested |
| 4.4 | Type `/policy-stats` in chat | Skill activates and shows governance summary | Not yet tested |

### 5. Edge cases

| # | Scenario | Expected | Verified? |
|---|---|---|---|
| 5.1 | Kill AxonFlow while plugin is connected | Hooks fail-open (commands execute). MCP tools return errors. | Not yet tested |
| 5.2 | Invalid auth in enterprise mode | Hooks fail-closed (exit 2). MCP tools unavailable. | Not yet tested |

---

## Cursor Hook Reference (from docs)

### Input formats

**`preToolUse` input:**
```json
{
  "tool_name": "Shell",
  "tool_input": { "command": "cat /etc/passwd", "working_directory": "/project" },
  "tool_use_id": "abc123",
  "cwd": "/project",
  "model": "claude-sonnet-4-20250514"
}
```

**`beforeShellExecution` input:**
```json
{
  "command": "cat /etc/passwd",
  "cwd": "/project",
  "sandbox": false
}
```

**`afterShellExecution` input:**
```json
{
  "command": "echo hello",
  "output": "hello",
  "duration": 1234,
  "sandbox": false
}
```

### Exit codes
- **Exit 0**: Hook succeeded, use JSON output
- **Exit 2**: Block the action (equivalent to `permission: "deny"`)
- **Other**: Hook failed, action proceeds (fail-open)

### Output format (preToolUse)
```json
{
  "permission": "allow" | "deny",
  "user_message": "Message shown to user when denied",
  "agent_message": "Message sent to agent when denied"
}
```

---

## Automated tests (no Cursor IDE needed)

```bash
cd /Users/saurabhjain/Development/axonflow-cursor-plugin
./tests/test-hooks.sh           # Mock server (offline, fast)
./tests/test-hooks.sh --live    # Live AxonFlow (requires running instance)
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Plugin not in Settings → Plugins | Plugin not at `~/.cursor/plugins/local/` | `cp -r` the plugin (not symlink) and reload Cursor |
| Hooks not firing | Missing `"version": 1` in hooks.json | Check `hooks/hooks.json` has `"version": 1` at top level |
| Hooks fire but don't match Shell | Wrong matcher or tool name | Cursor uses `Shell` (not `Bash`). Matcher should be `"Shell"` for preToolUse |
| MCP server not connected | AxonFlow not running or wrong URL | Check `curl -s http://localhost:8080/health` returns healthy |
| Changes not taking effect | Plugin was copied, not symlinked | Re-copy from source and reload: `rm -rf ~/.cursor/plugins/local/axonflow-cursor-plugin && cp -r ...` |
| Exit 2 on everything | AxonFlow auth/config error (fail-closed) | Check AxonFlow logs: `docker logs axonflow-agent` |
