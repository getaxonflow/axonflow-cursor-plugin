# Changelog

## [0.6.0] - 2026-04-29 — Production, quality, and security hardening — upgrade encouraged

**Upgrade strongly recommended.** Over the past month we've shipped substantial production, quality, and security hardening across the AxonFlow plugin and platform — upgrade to the latest version for a more secure, reliable, and bug-free experience.

**Security highlights from this release cycle:**
- **Plugin cache and credential-file permission hardening** (this release). `~/.config/axonflow/` and `~/.cache/axonflow/` are tightened to mode `0700` on every invocation (was: only set on creation, leaving pre-existing world-readable directories unchanged); `try-registration.json` is written with mode `0600`. Pre-existing world-readable credential files are detected and refused on first load. Documented in [`GHSA-qc7h-rq59-m293`](https://github.com/getaxonflow/axonflow-cursor-plugin/security/advisories/GHSA-qc7h-rq59-m293).
- **Cross-platform bootstrap reliability** (this release). macOS Community-SaaS bootstrap was silently no-op'ing because `flock(1)` is Linux-only; now uses a portable `mkdir`-based atomic lock with stale-lock reclamation, so first-install registration runs on macOS too.
- **Telemetry opt-out reliability** (this release). `DO_NOT_TRACK` was unreliable because host CLIs commonly inject `DO_NOT_TRACK=1` into hook subprocesses regardless of user intent; the canonical opt-out is now `AXONFLOW_TELEMETRY=off`, an AxonFlow-scoped signal hosts can't unilaterally set.

The full set of platform-side security fixes shipped alongside this release — including multi-tenant isolation in MAP execution, cross-tenant audit-log isolation, and SQLi enforcement on the Community SaaS endpoint — is documented in the consolidated platform advisory [`GHSA-9h64-2846-7x7f`](https://github.com/getaxonflow/axonflow/security/advisories/GHSA-9h64-2846-7x7f).

**Reliability and bug-fix highlights:**
- **7-day delivered-heartbeat with stamp-on-success** (this release). Telemetry stamp advances only after the POST returns 2xx, so a transient network failure no longer silences telemetry until the next 7-day window. Concurrent invocations are de-duplicated by an in-flight gate.
- **Mode-clarity canary log line** on every hook init (this release). Stderr emits `[AxonFlow] Connected to AxonFlow at <URL> (mode=...)` and a PR-blocking CI gate asserts the canary matches the actual outbound destination, guarding against silent endpoint drift.
- **PR-blocking install-to-use smoke against the live community stack** (this release). Catches plugin-side regressions against `try.getaxonflow.com` before they reach a user's terminal.

### BREAKING

- **`DO_NOT_TRACK` is no longer honored as an AxonFlow telemetry opt-out.** Use `AXONFLOW_TELEMETRY=off` instead. Host tools and CLIs commonly inject `DO_NOT_TRACK=1` regardless of user intent, which makes it unreliable as a signal.

### Added

- **First-run Community-SaaS bootstrap** — plugin connects to AxonFlow Community SaaS at `https://try.getaxonflow.com` when neither `AXONFLOW_ENDPOINT` nor `AXONFLOW_AUTH` is set. Registers via `/api/v1/register` on first run and persists `{tenant_id, secret, expires_at, endpoint}` to `~/.config/axonflow/try-registration.json` (mode 0600 inside a 0700 directory). Refuses to load a registration file with non-0600 permissions. HTTP 429 → 1-hour backoff. Existing self-hosted installs (`AXONFLOW_ENDPOINT` or `AXONFLOW_AUTH` set) are honoured untouched.
- **Mode-clarity canary** on every hook init: `[AxonFlow] Connected to AxonFlow at <URL> (mode=community-saas|self-hosted)` on stderr. A CI gate parses this canary and asserts it matches the actual outbound destination.
- **One-time setup disclosure** on first Community-SaaS connection. Stamped at `~/.cache/axonflow/cursor-plugin-disclosure-shown` so it fires exactly once per install.
- **Plugin/platform version compatibility check** (`scripts/version-check.sh`). Queries the agent's `/health` endpoint and warns if the plugin runtime is below the platform's expected floor. Skippable via `AXONFLOW_PLUGIN_VERSION_CHECK=off`.

### Changed

- **Telemetry switched to a 7-day delivered-heartbeat.** At most one anonymous ping per environment every 7 days, with the stamp advanced only after the POST returns 2xx — a transient network failure doesn't silence telemetry until the next window. Concurrent invocations are de-duplicated by an in-flight gate.

### Fixed

- The `DO_NOT_TRACK=1 is deprecated...` warning is no longer emitted on every hook invocation when `DO_NOT_TRACK=1` is set.
- Telemetry heartbeat now correctly classifies Community-SaaS sessions (was tagged `production` because the bootstrap-injected `AXONFLOW_AUTH` shadowed the resolver, sending `/health` probes to localhost and `platform_version=null` with the wrong `deployment_mode`).
- Bootstrap and heartbeat now run on macOS — `flock(1)` isn't on stock macOS, so the in-flight lock falls back to a `mkdir`-based atomic lock with stale-lock reclamation when `flock` is unavailable.

### Security

- `~/.config/axonflow/` and `~/.cache/axonflow/` permissions tightened to `0700` on every invocation (was: only set on creation via `mkdir -m 0700`, which left existing 0755 dirs unchanged).


## [0.5.2] - 2026-04-22

### Deprecated

- `DO_NOT_TRACK=1` as an AxonFlow telemetry opt-out — scheduled for removal after 2026-05-05 in the next major release. Use `AXONFLOW_TELEMETRY=off` instead. The plugin's `telemetry-ping.sh` emits a one-time stderr warning when `DO_NOT_TRACK=1` is the active control and `AXONFLOW_TELEMETRY=off` is not also set.

## [0.5.1] - 2026-04-19

### Added

- **Smoke E2E scenario** at `tests/e2e/smoke-block-context.sh` — runs
  `pre-tool-check.sh` against a reachable AxonFlow stack and asserts the
  hook exits 2 with `AxonFlow policy violation` + Plugin Batch 1
  richer-context markers on stderr. Exits 0 (`SKIP:`) when no stack is
  reachable.
- **`.github/workflows/smoke-e2e.yml`** — `workflow_dispatch` triggered job running the smoke scenario.
  Requires an operator-supplied endpoint (GitHub-hosted runners have no
  local stack), so not wired to PR events — PR smoke gating needs a
  self-hosted runner with a live stack.

Full install-and-use matrix lives in `axonflow-enterprise/tests/e2e/plugin-batch-1/cursor-install/`.

## [0.5.0] - 2026-04-18

### Added

- **Richer block reason surfaced to Cursor on policy blocks.** When the
  AxonFlow platform is v7.1.0+, the stderr message accompanying the
  `exit 2` block now includes `[decision: <id>, risk: <level>, active
  override: <ov>]` or a pointer to the `explain_decision` MCP tool so
  the user knows how to unblock themselves. Older platforms see the
  prior v0.4.0 message — fields are omitted when not returned.
- **Access to platform MCP tools** `explain_decision`, `create_override`,
  `delete_override`, `list_overrides` — available via the agent's MCP
  server when connected to a v7.1.0+ platform. Cursor's MCP client can
  invoke them directly.

### Compatibility

Companion to platform v7.1.0 and SDKs v5.4.0 / v6.4.0. Back-compatible.

## [0.4.0] - 2026-04-16

### Added

- **Anonymous telemetry ping** on first hook invocation. Sends plugin version, OS, architecture, bash version, and AxonFlow platform version to `checkpoint.getaxonflow.com`. No PII, no tool arguments, no policy data. Fires once per install (stamp file guard at `$HOME/.cache/axonflow/cursor-plugin-telemetry-sent`). Opt out with `DO_NOT_TRACK=1` or `AXONFLOW_TELEMETRY=off`.
- **3 new governance skills:** `pii-scan`, `governance-status`, `policy-list` — brings Cursor to parity with Codex plugin's 6-skill advisory governance model.

### Fixed

- **UTF-8 safe content truncation.** Write and Edit content extraction now uses character-level `cut -c1-2000` instead of byte-level `head -c 2000`. Prevents splitting multi-byte UTF-8 sequences (emoji, accented characters) at the truncation boundary.
- **Consistent curl error reporting.** `post-tool-audit.sh` now uses `-sS` (silent + show errors) matching `pre-tool-check.sh`.
- **Removed unused `PII_ALLOWED` variable** from shell write PII scanning block — the `REDACTED` check is sufficient.
- **Improved shell write content extraction regex.** Better handling of single-quoted strings and heredoc markers. Added documentation of known limitations.

### Changed

- **Hook timeout increased from 10s to 15s** across all 4 hook types (preToolUse, postToolUse, beforeShellExecution, afterFileEdit). Provides sufficient buffer above the 8s default curl timeout.

### Security

- Updated SECURITY.md timestamp to April 2026.

## [0.3.1] - 2026-04-10

### Added

- **Decision-matrix regression tests** for the v0.3.0 hook fail-open/fail-closed behavior. The v0.3.0 release only added a single stderr-string assertion update; the new branches (JSON-RPC -32601 method-not-found, -32602 invalid-params, -32603 internal, -32700 parse, and unknown error codes) were completely untested. This release adds mock-server cases for every branch so the decision matrix is now covered end-to-end.

## [0.3.0] - 2026-04-08

### Changed

- **Hook fail-open/fail-closed hardening.** `scripts/pre-tool-check.sh` now distinguishes curl exit code (network failure) from HTTP success with an error body. Fail-closed (exit 2, block tool) only on operator-fixable JSON-RPC errors: auth failures (-32001), method-not-found (-32601), and invalid-params (-32602). Fail-open (exit 0, allow) on everything else: curl timeouts/DNS failures/connection refused, empty response, server-internal errors (-32603), parse errors (-32700), and unknown error codes. Prevents transient governance infrastructure issues from blocking legitimate dev workflows while still catching broken configurations.

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
