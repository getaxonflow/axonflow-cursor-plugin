# Changelog

## [0.3.0] - 2026-04-09

### Changed

- **Hook fail-open/fail-closed hardening (issue #1545 Direction 3).** `scripts/pre-tool-check.sh` now distinguishes curl exit code (network failure) from HTTP success with an error body. Fail-closed (exit 2, block tool) only on operator-fixable JSON-RPC errors: auth failures (-32001), method-not-found (-32601), and invalid-params (-32602). Fail-open (exit 0, allow) on everything else: curl timeouts/DNS failures/connection refused, empty response, server-internal errors (-32603), parse errors (-32700), and unknown error codes. Prevents transient governance infrastructure issues from blocking legitimate dev workflows while still catching broken configurations.

### Security

- Pinned all GitHub Actions to immutable commit SHAs to prevent supply chain attacks.
- Added Dependabot configuration for weekly GitHub Actions updates.

## [0.2.0] - 2026-04-06

Initial public release.

### Added

- `preToolUse` hook: evaluates tool inputs against AxonFlow policies before execution. Blocks dangerous commands, reverse shells, SSRF, credential access, path traversal via exit code 2.
- `postToolUse` hook: records tool execution in AxonFlow audit trail and scans output for PII/secrets.
- `beforeShellExecution` hook: additional shell command enforcement layer.
- `afterFileEdit` hook: audit trail for file modifications.
- PII detection in file writes via `check_output` scan on shell redirect commands. Configurable via `PII_ACTION` env var: `block`, `redact` (default — denies and instructs agent to rewrite with redacted content), `warn`, `log`.
- MCP server integration with 6 governance tools: `check_policy`, `check_output`, `audit_tool_call`, `list_policies`, `get_policy_stats`, `search_audit_events`.
- 3 governance skills: `check-governance`, `audit-search`, `policy-stats`.
- `.mdc` governance rules for always-on policy context.
- Audit logging for blocked attempts.
- Fail-open on network failure, fail-closed on auth/config errors.
- Governed tools: `Shell`, `Write`, `Edit`, `Read`, `Task`, `NotebookEdit`, and MCP tools (`mcp__*`).
- `AXONFLOW_TIMEOUT_SECONDS` environment variable to tune Cursor hook HTTP timeouts for remote or high-latency AxonFlow deployments.
- Plugin logo for marketplace and directory listings.
- `SECURITY.md` with plugin-specific vulnerability reporting guidance.
- Regression tests with mock MCP server (`tests/test-hooks.sh`, 20 tests).
- CI workflow: shellcheck, syntax check, regression tests, plugin structure validation.
- E2E testing playbook with 17 verified tests.

### Configuration

- `AXONFLOW_ENDPOINT` — AxonFlow Agent URL (default: `http://localhost:8080`).
- `AXONFLOW_AUTH` — Base64-encoded `clientId:clientSecret` for Basic auth.
- `AXONFLOW_TIMEOUT_SECONDS` — optional override for hook HTTP timeouts.
- `PII_ACTION` — PII enforcement mode: `block`, `redact` (default), `warn`, `log`.
- Plugin installed at `~/.cursor/plugins/local/axonflow-cursor-plugin` (copy, not symlink).
- `hooks.json` requires `"version": 1` for Cursor compatibility.
