# AxonFlow Plugin for Cursor IDE

Policy enforcement, PII detection, and audit trails for Cursor. Automatically governs tool execution via PreToolUse/PostToolUse hooks and provides 6 MCP tools for explicit governance queries.

## How It Works

```
Cursor selects a tool (Bash, Write, MCP, etc.)
    │
    ▼
PreToolUse hook fires automatically
    │ → check_policy("cursor.Bash", "rm -rf /")
    │
    ├─ BLOCKED (exit 2) → Cursor receives denial, tool never runs
    │
    └─ ALLOWED (exit 0) → Tool executes normally
                      │
                      ▼
                 PostToolUse hook fires automatically
                      │ → audit_tool_call(tool, input, output)
                      │ → check_output(tool result for PII/secrets)
                      │
                      ├─ PII found → Cursor instructed to use redacted version
                      └─ Clean → Silent, no interruption
```

## Prerequisites

- [AxonFlow](https://github.com/getaxonflow/axonflow) v6.0.0+ running locally (`docker compose up -d`)
- [Cursor IDE](https://cursor.com)
- `jq` and `curl` installed

## Install

```bash
git clone https://github.com/getaxonflow/axonflow-cursor-plugin.git
```

## Configure

```bash
export AXONFLOW_ENDPOINT=http://localhost:8080
export AXONFLOW_AUTH=""  # empty for community mode
export CURSOR_PLUGIN_ROOT=/path/to/axonflow-cursor-plugin
```

Load the plugin in Cursor via the plugin settings or `--plugin-dir` flag.

In community mode (`DEPLOYMENT_MODE=community`), no auth is needed.

## What Happens Automatically

| Event | Hook | Action |
|-------|------|--------|
| Before governed tool call | PreToolUse | `check_policy` evaluates inputs against 80+ governance policies |
| After governed tool call | PostToolUse | `audit_tool_call` records execution in compliance audit trail |
| After governed tool call | PostToolUse | `check_output` scans output for PII/secrets |

**Governed tools:** `Bash`, `Write`, `Edit`, `NotebookEdit`, and all MCP tools (`mcp__*`).

**Fail behavior:**
- AxonFlow unreachable (network failure) → fail-open, tool execution continues
- AxonFlow auth/config error → fail-closed, tool call blocked until configuration is fixed
- PostToolUse failures → never block (audit and PII scan are best-effort)

## MCP Tools (Also Available for Explicit Use)

| Tool | Purpose |
|------|---------|
| `check_policy` | Evaluate specific inputs against policies |
| `check_output` | Scan specific content for PII/secrets |
| `audit_tool_call` | Record additional audit entries |
| `list_policies` | List active governance policies |
| `get_policy_stats` | Get governance activity summary |
| `search_audit_events` | Search individual audit records |

## What Gets Checked

AxonFlow ships with 80+ built-in system policies:

- **Dangerous commands** — destructive filesystem operations, remote code execution, credential access, cloud metadata SSRF, path traversal
- **SQL injection** — 30+ patterns including UNION injection, stacked queries, auth bypass
- **PII detection** — SSN, credit card, email, phone, Aadhaar, PAN, NRIC/FIN
- **Code security** — API keys, connection strings, hardcoded secrets
- **Prompt injection** — instruction override and context manipulation

## Plugin Structure

```
axonflow-cursor-plugin/
├── .cursor-plugin/
│   └── plugin.json         # Plugin metadata
├── mcp.json                 # MCP server connection (6 governance tools)
├── hooks/
│   └── hooks.json           # PreToolUse + PostToolUse hook definitions
├── skills/
│   ├── check-governance/    # Check if an action is allowed
│   ├── audit-search/        # Search audit trail
│   └── policy-stats/        # Governance activity summary
├── rules/
│   └── axonflow-governance.mdc  # Always-on governance context
├── scripts/
│   ├── pre-tool-check.sh    # Policy evaluation (PreToolUse)
│   ├── post-tool-audit.sh   # Audit + PII scan (PostToolUse)
│   └── mcp-auth-headers.sh  # MCP auth header generation
├── tests/
│   ├── test-hooks.sh        # Regression tests (mock + live)
│   └── E2E_TESTING_PLAYBOOK.md
└── .github/workflows/test.yml
```

## Links

- [AxonFlow Documentation](https://docs.getaxonflow.com)
- [Cursor Integration Guide](https://docs.getaxonflow.com/docs/integration/cursor/)
- [Claude Code Plugin](https://github.com/getaxonflow/axonflow-claude-plugin) — sister plugin
- [OpenClaw Plugin](https://github.com/getaxonflow/axonflow-openclaw-plugin)
- [Policy Enforcement](https://docs.getaxonflow.com/docs/mcp/policy-enforcement/)
- [Self-Hosted Deployment](https://docs.getaxonflow.com/docs/deployment/self-hosted/)
- [Security Best Practices](https://docs.getaxonflow.com/docs/security/best-practices/)

## License

MIT
