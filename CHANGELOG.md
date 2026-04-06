# Changelog

## [0.2.0] - 2026-04-06

### Added

- `AXONFLOW_TIMEOUT_SECONDS` environment variable to tune Cursor hook HTTP timeouts for remote or high-latency AxonFlow deployments.
- Plugin logo for marketplace and directory listings.
- `SECURITY.md` with plugin-specific vulnerability reporting guidance.

### Changed

- README now removes the old `CURSOR_PLUGIN_ROOT` setup step and clarifies that the Cursor plugin itself does not send direct telemetry pings.

## [0.1.0] - 2026-04-06

### Added

- PreToolUse hook: evaluates tool inputs against AxonFlow policies before execution. Blocks dangerous commands, reverse shells, SSRF, credential access, path traversal via exit code 2.
- PostToolUse hook: records tool execution in AxonFlow audit trail and scans output for PII/secrets.
- MCP server integration with 6 governance tools: `check_policy`, `check_output`, `audit_tool_call`, `list_policies`, `get_policy_stats`, `search_audit_events`
- 3 governance skills: check-governance, audit-search, policy-stats
- `.mdc` governance rules for always-on policy context
- Audit logging for blocked attempts
- Fail-open on network failure, fail-closed on auth/config errors
- Governed tools: `Bash`, `Write`, `Edit`, `NotebookEdit`, and all MCP tools (`mcp__*`)
- Regression tests with mock MCP server (`tests/test-hooks.sh`)
- CI workflow: shellcheck, syntax check, regression tests, plugin structure validation

### Configuration

- `AXONFLOW_ENDPOINT` — AxonFlow Agent URL (default: `http://localhost:8080`)
- `AXONFLOW_AUTH` — Base64-encoded `clientId:clientSecret` for Basic auth
- `AXONFLOW_TIMEOUT_SECONDS` — optional override for hook HTTP timeouts
