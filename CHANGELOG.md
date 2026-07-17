# Changelog

## [Unreleased]

## [1.6.0] - 2026-07-17 — per-user authorization token (X-User-Token) on every governed request

### Added

- **The plugin now sends the admin-minted per-user token as `X-User-Token` on every governed request** (Cursor port of the Claude Code plugin's 1.10.0 capability; epic per-user identity + role on the fleet plane). The platform's fleet plane authenticates the *tenant* with the shared Basic credential; the per-user token additionally yields a **validated, non-forgeable `{identity, role}`** for the developer behind the session, which per-user read scoping and audit attribution key on. Covered send surfaces — all four header-assembly paths:
  - `mcp.json` static `headers` (the MCP connection Cursor opens; env-expanded `${AXONFLOW_USER_TOKEN}`),
  - `scripts/mcp-auth-headers.sh` (the readable reference impl, kept in sync),
  - `scripts/pre-tool-check.sh` (`check_policy` + the blocked-audit `audit_tool_call` POST + the shell-write `check_output` scan),
  - `scripts/post-tool-audit.sh` (`audit_tool_call` + `check_output`).
- **Resolution order** (new `scripts/user-token.sh`, mirrors the license-token discipline): `AXONFLOW_USER_TOKEN` env var (managed settings / MDM env block — wins) → `~/.config/axonflow/user-token.json` (`{"token": "<minted token>"}`). The file is **0600-guarded**: non-0600 permissions are rejected with a stderr warning, never loaded silently. Tokens are minted by an org admin via the platform admin user-tokens API.
- **Strictly additive and conditional**: when no token is configured, the header is omitted entirely on the hook surfaces (never empty) and every request is byte-identical to a 1.5.x plugin — the platform keeps its existing least-privilege attribution path.
- **Cursor-specific MCP-plane limitation (documented in README):** the MCP connection uses Cursor's *static* env expansion — no headersHelper — so that plane reads `AXONFLOW_USER_TOKEN` from the environment only (no 0600-file fallback, no local wire-safety check). Unset expands to an empty header value, which the platform treats as absent; a malformed env value is sent raw and the platform fails closed with 401 until it is fixed or removed.
- **Wire-safety guard, never logged**: on the hook surfaces, a candidate token containing whitespace, control bytes, quotes, or backslashes is dropped locally with a diagnostic that never prints the value — the platform fails closed on a presented-but-invalid token, so sending a mangled credential would turn every governed call into an auth denial. For the same reason, the hooks' `-32001` fail-closed block message now names a configured per-user token as a likely cause (expired / revoked / wrong org) instead of only pointing at `AXONFLOW_AUTH`.
- Tests: `tests/test-user-token.sh` (resolver unit + reference-impl wire shape), `tests/test-user-token-header-wire.sh` (drives the ACTUAL hooks against a header-capturing agent, asserting present-when-configured / absent-when-not on all five governed curls), `tests/test-mcp-json-alignment.sh` (NEW CI gate: `mcp.json`'s `X-Axonflow-Client` version must equal `plugin.json`'s + the `X-User-Token` template must exist), `runtime-e2e/user-token/` (live-stack, no mocks), and an X-User-Token leg in `runtime-e2e/mcp-enterprise-auth/`.

### Fixed

- **`mcp.json` reported a stale client version on the wire.** The static `X-Axonflow-Client` header was hardcoded at `cursor-plugin/1.3.0` while the plugin was at 1.5.3 — every MCP-connection request misreported the plugin version to the platform's per-client version telemetry. Now `cursor-plugin/1.6.0`, and the new `tests/test-mcp-json-alignment.sh` CI gate keeps it locked to `plugin.json` so the drift cannot recur. (Same class as the Claude Code plugin's on-wire version fix.)

## [1.5.3] - 2026-06-08 — Authenticate the MCP server connection on self-hosted / Enterprise agents

### Fixed

- **MCP server connection now authenticates to self-hosted / Enterprise
  (in-VPC) agents.** `mcp.json` set `X-Axonflow-Client` and `X-License-Token`
  static headers but **no `Authorization` header**, so against an agent that
  requires HTTP Basic auth the MCP connection arrived unauthenticated → the
  agent 401'd → Cursor fell into OAuth discovery and died on the agent's
  plaintext `404 page not found`, and governed tool calls were blocked. Added
  `"Authorization": "Basic ${AXONFLOW_AUTH}"` to the static headers (Cursor
  expands `${AXONFLOW_AUTH}` from the launching environment, same as the
  existing `${AXONFLOW_ENDPOINT}` / `${AXONFLOW_LICENSE_TOKEN}`). For an
  Enterprise/in-VPC agent set `AXONFLOW_AUTH=base64(org_id:license_key)` (bare
  base64 — the header adds the `Basic ` prefix). Verified at the wire level:
  the resulting header set returns HTTP 200 + `initialize` from a live
  in-vpc-enterprise agent. (Distinct from Cursor's lack of a dynamic header
  helper for per-session token refresh; `X-License-Token` is still forwarded
  statically via env expansion.)

## [1.5.2] - 2026-05-22 — 401 throttle follow-up: separate stamp file + JSON-RPC auth-error fail-closed carve-out + `org_id` in telemetry heartbeat

### Added

- **`org_id` field in the telemetry heartbeat body.** Brings the Cursor
  plugin's telemetry up to parity with the platform — every heartbeat
  now identifies which deployment-organization emitted it. Three
  sources in precedence order:
  1. The `ORG_ID` env var when set.
  2. The `tenant_id` from `~/.config/axonflow/try-registration.json`
     (the `cs_<uuid>` Community SaaS tenant identifier).
  3. The `local-dev-org` sentinel when neither is configured.

  Always emitted on the wire; older receivers ignore the field cleanly
  for backward compat. Honors `AXONFLOW_TELEMETRY=off` like every other
  heartbeat field. See
  [getaxonflow.com/privacy/](https://getaxonflow.com/privacy/) for the
  customer-facing commitment that covers this field.

### Fixed

- **The HTTP 401 stderr nudge is no longer silently suppressed by an
  earlier tier-limit envelope.** v1.5.1's auth-failure handler reused
  the upgrade-prompt's shared per-UTC-day stamp file
  (`~/.cache/axonflow/upgrade-prompt-last-shown`). If a 429 daily-quota
  envelope or 403 active-policies envelope fired earlier the same day,
  the 401 path's user-visible "credential failed → refresh at
  https://getaxonflow.com/dashboard" message was suppressed even
  though `throttle-until` was correctly written. Net effect: a user
  with a broken `AXONFLOW_AUTH` would see their tool calls quietly
  fall open with no diagnostic for up to 24h. Fix introduces a
  separate `~/.cache/axonflow/auth-failure-prompt-last-shown` stamp
  file used exclusively by the 401 path, so the two prompts are
  independent operator concerns and do not cross-suppress.

- **`-32001` (Authentication failed) fail-closed contract restored for
  HTTP 401 responses.** v1.5.1's auth-failure throttle fired
  unconditionally on HTTP 401 (before the JSON-RPC error-code parser).
  When the agent returned 401 with a JSON-RPC body of
  `{"error": {"code": -32001, "message": "..."}}` — its "your
  credential maps to no tenant" signal — the throttle short-circuited
  with `exit 0` (fail-open), regressing the previously documented
  `-32001` fail-closed semantics. The user's tool would proceed
  despite the agent explicitly saying "block." Fix: `pre-tool-check.sh`
  inspects the response body before invoking the auth-failure handler,
  and when HTTP 401 carries `error.code == -32001`, the JSON-RPC
  parser takes over (`exit 2`, fail-closed). Plain 401s (no JSON-RPC
  `-32001` body) still hit the throttle and the v1.5.1 storm-prevention
  fix holds. `post-tool-audit.sh` does not need the carve-out — the
  audit hook has no fail-closed path; failing-closed on a
  post-execution audit makes no sense.

### Changed

- **`scripts/telemetry-ping.sh` header comment** softened from "Anonymous
  telemetry heartbeat" to "Telemetry heartbeat" alongside the `org_id`
  addition — the operator-supplied `ORG_ID` is not anonymized.

## [1.5.1] - 2026-05-20 — Throttle on HTTP 401 to prevent auth-storm

### Fixed

- **HTTP 401 from the AxonFlow agent now stamps a 5-minute throttle.**
  When `AXONFLOW_AUTH` is invalid or expired, every PreToolUse and
  PostToolUse hook used to fire a 401, the envelope handler returned
  non-zero (it only fires on 429/403), and the script fell through.
  The next tool call immediately re-fired another 401 — a tight retry
  loop. One customer observed 716 retries against the audit endpoint
  from a single source IP in 24h. Now, on 401 the plugin stamps
  `~/.cache/axonflow/throttle-until` with a 5-minute cooldown and
  `auth_failure` limit_type, so subsequent hook fires short-circuit
  locally. The user sees a one-time-per-UTC-day nudge on stderr
  pointing at https://getaxonflow.com/dashboard. After 5 minutes the
  throttle clears automatically and the next hook retries — so a
  refreshed credential is picked up without further action. Wired into
  both pre- and post-tool hooks. Fail-open semantics preserved: the
  user's tool call is not blocked while the throttle is active.

## [1.5.0] - 2026-05-19 — Terminology: `tenant_id` → `client_id` in user-facing output

### Changed

- **`scripts/status.sh` output: `tenant_id:` label is now `client_id:`.**
  Same value, new user-facing term. Aligns Cursor plugin output with
  the rest of AxonFlow's v9 terminology (the `org_id` ↔ `client_id`
  ↔ deployment-license-identity three-identifier model). For this
  release, the output carries a parenthetical bridge note
  (`(formerly tenant_id)`) so existing users connect the old and new
  terms without surprise. The bridge note will be removed in v1.6.0.

  **Cosmetic only — no config change is required.** The on-disk
  registration file at `~/.config/axonflow/try-registration.json`
  continues to use the `tenant_id` JSON key (file-format compat with
  installed base); only the human-readable status output reads
  `client_id`. Wire-level `X-Axonflow-Client` header is unchanged. The
  agent-side MCP tool `axonflow_get_tenant_id` keeps its name
  (callable both as muscle-memory "what's my tenant ID?" and the new
  "what's my client ID?" — both return the same identifier).

  **Action required for users who scripted around the old output:** if
  your tooling greps for `tenant_id:` in `scripts/status.sh` stdout,
  update to grep for `client_id:` (or use the underlying
  `~/.config/axonflow/try-registration.json` file which still carries
  the legacy key).

- **README install-flow examples** updated to use `client_id`
  terminology consistently. The "Activate Pro tier" walkthrough notes
  that Stripe Checkout's custom field is still labeled "AxonFlow
  tenant ID" until that form is updated separately.

## [1.4.0] - 2026-05-09 — Decision History API + policy_version recorded on every decision + telemetry simplification

### Added

- **`list-recent-decisions` skill** — surfaces the caller's recent governance decisions via the new `list_recent_decisions` MCP tool from Composer/Agent mode. Tier-throttled per the platform's Free/Pro window+limit; Free callers hitting the cap see the upgrade envelope rendered to the host.

### Telemetry

- **`AXONFLOW_TELEMETRY=off` is the sole opt-out** for the plugin heartbeat — same single-lever model as the SDKs.
- **Heartbeat payload v1 schema additions**: `telemetry_type: "plugin"`, `endpoint_type` (`localhost | private_network | remote | unknown`), `deployment_mode` (`self_hosted | community_saas | unknown`). Set `AXONFLOW_TRY=1` if your stack proxies a custom hostname into try.getaxonflow.com so heartbeats classify as `community_saas` correctly.

## [1.3.0] - 2026-05-07 — V1 Plugin Pro upgrade-prompt envelope + 5 new MCP tools surfaced

Companion plugin release to AxonFlow agent v7.7.0. Surfaces the V1
Plugin Pro structured upgrade envelope to the operator on Community
SaaS rate-limit hits and documents 5 new agent-callable MCP tools.

### Added

- **V1 Plugin Pro upgrade-prompt envelope handling** in both PreToolUse and
 PostToolUse hooks. When the agent returns a 429 (daily-quota) or 403
 (graduated / Pro-only) with the structured envelope shape, the plugin:
 - Parses `upgrade.wording` + `upgrade.buy_url` and prints a single-line
 nudge to stderr (e.g. `[AxonFlow] Daily limit reached on Free tier
 (200 events). Pro raises this to 2,000/day. Resets at midnight UTC.`).
 Surfaced at most once per UTC day so it doesn't spam every hook.
 - Honours `Retry-After` / `resets_at` by stamping a back-off file at
 `${XDG_CACHE_HOME:-~/.cache}/axonflow/throttle-until`. Subsequent hook
 fires fall open locally without re-hammering the agent until the
 deadline passes. Prevents the silent-retry pattern (581 retries in
 18h pre-envelope) that motivated this work.
- **References to the 5 new agent-callable MCP tools** in the README. The
 agent can answer `"what's my tenant ID?"`, `"what would I get on Pro?"`,
 and related questions directly via:
 - `axonflow_get_tenant_id` — Free + Pro, no gate.
 - `axonflow_list_pro_features` — Free + Pro, locked feature list.
 - `axonflow_request_approval` — Free 1/7d rolling, Pro unlimited.
 - `axonflow_create_tenant_policy` — Free 2 active max, Pro unlimited.
 - `axonflow_get_cost_estimate` — Pro-only, hidden from Free `tools/list`.

 Auto-discovered via the existing MCP HTTP transport — no client-side
 registration needed.

### Changed

- **README "Pro tier license token" section** corrected to the locked V1
 numbers: 2,000 events/day (was 1,000), unlimited custom policies,
 unlimited HITL approvals, and the LLM cost pre-flight feature added.
- **README MCP-tools section** renumbered from "10 MCP tools" to "15 MCP
 tools" to include the new V1 Pro tier-identity / tier-capability tools.
- **`axonflow-status` skill — prefer the local `scripts/status.sh` over
 the MCP tool** for tenant_id / tier queries. The local script reads
 state directly and answers without an agent round-trip. Faster, works
 offline, and works exactly when the user typically asks ("the agent
 isn't reachable, what's my tenant ID for Stripe Checkout?"). The MCP
 tool stays as a documented fallback for the rare cases where
 server-truth matters (revocation, clock skew, server-side overrides).
 Same flip applied to claude / codex sister plugins.

### Internal

- the runtime test bundle — drives a fresh Free-tier
 tenant past the 200/day cap on `try.getaxonflow.com`, asserts the
 plugin's envelope helper prints the locked V1 wording to stderr
 and stamps a throttle deadline.
- `tests/test-upgrade-prompt.sh` — 21 unit assertions across 8
 scenarios for every branch of the envelope handler.
- `tests/test-skill-status-prefers-local.sh` — 4 content assertions
 locking the local-first SKILL.md ordering in; wired into
 `.github/workflows/test.yml`. The cursor-agent CLI is a separate
 runtime from Cursor IDE and does not load IDE plugins, so the
 end-to-end runtime proof for the skill flip lives in the sister
 `axonflow-claude-plugin` test (the wording change is structurally
 identical across plugins).

## [1.2.0] - 2026-05-06 — V1 paid Pro tier wire-up + X-Axonflow-Client header

Companion plugin release to platform v7.7.0. Surfaces the V1 SaaS Plugin
Pro tier — `AXONFLOW_LICENSE_TOKEN` paste activates Pro features
immediately, plus the agent-side scope-validation header on every governed
request via `mcp.json`'s `headers` field.

### Added

- **`X-Axonflow-Client: cursor/<version>` header** on every governed
 agent request. Declared via `mcp.json`'s `headers` field with
 `${AXONFLOW_CLIENT_HEADER}` interpolation; `pre-tool-check.sh`
 exports the env var on every hook-invoke. Agents at v7.7.0+ derive
 request scope from this header and reject cross-quadrant token misuse
 (e.g. a SaaS Plugin Pro token paired with an SDK request) at the
 validator boundary. Older agents (pre-v7.7.0) ignore the header and
 continue to work unchanged.

- **`scripts/status.sh` tier line now surfaces Pro license expiry date.**
 The status output's `tier` line parses the JWT `exp` claim from the
 configured Pro license token and renders one of three shapes: `Pro
 (expires YYYY-MM-DD, N days remaining)` when active, `Free (Pro
 expired YYYY-MM-DD — visit https://getaxonflow.com/pricing/ to renew)`
 when the token is on disk but its `exp` has passed (plugin will not
 forward an expired token), or `Free (no Pro license configured)`
 when no token is loaded. Lets users see their renewal date without
 hitting the agent and catches the lapsed-token state before their
 next governed call. Display only — JWT signature validation remains
 the platform's job.
- **Status surface (`scripts/status.sh` + `/axonflow-status` skill).** Prints
 the `tenant_id` (which Pro buyers paste into the custom field at Stripe
 Checkout), the active tier (`Free` or `Pro`), the agent endpoint, the
 config / token file paths, and the upgrade URL. The license token is
 redacted to last-4 chars (`AXON-...XXXX`) so the output is safe to
 screen-share or paste into a support ticket. Resolution mirrors
 `pre-tool-check.sh`: env first, then `~/.config/axonflow/license-token`
 (mode `0600` only — looser permissions are reported but not consumed).
 Surfaces a recovery hint when `try-registration.json` is missing.
- **Pro tier license token wiring (`AXONFLOW_LICENSE_TOKEN`).** Buyers who
 completed Stripe Checkout for the Pro tier receive an `AXON-`-prefixed
 license token by email; the plugin now forwards it as the `X-License-Token`
 header on every governed agent call, so the request joins the Pro tier
 rather than the free tier. Resolution order: env var first, then
 `~/.config/axonflow/license-token` (mode `0600` only — files with looser
 permissions are refused with a stderr warning). When a token is loaded,
 the mode-clarity canary appends a `Pro tier active` suffix so the active
 tier is visible at a glance.
- **Email-recovery helper (`scripts/recover-credentials.sh` +
 `/recover-credentials` skill).** Drives the full
 `/api/v1/recover` → magic-link → `/api/v1/recover/verify` flow against
 a live agent, then writes the new credentials to
 `~/.config/axonflow/try-registration.json` with mode `0600`. Accepts
 either the bare hex token or the full magic-link URL from the email,
 and the community-saas bootstrap picks up the new credentials on the
 next governed tool call. The `/recover-credentials` skill instructs the
 agent to invoke the script via the Shell tool when the user reports
 lost free-tier credentials.

### Fixed

- **Upgrade-pointer URL aligned with the canonical pricing page.** `AXONFLOW_UPGRADE_URL` default (the URL surfaced by `scripts/status.sh` and the `axonflow-status` skill to free-tier users, plus embedded in the `tier Free (Pro expired ... — visit ... to renew)` line) is now `https://getaxonflow.com/pricing/`. The previous default `https://getaxonflow.com/pro` returned 404 — that page was referenced in PRDs but never built. The pricing page already resolves and carries the Plugin Pro $9.99 tier card with the Stripe buy button, so plugin status output now points free-tier users at a working URL. Override via `AXONFLOW_UPGRADE_URL` env var if needed. Same fix landed in companion plugin releases (openclaw-plugin v2.2.0, claude-plugin v1.2.0, codex-plugin v1.2.0).

## [1.1.0] - 2026-05-04 — 4 read-side governance skills

### Added

- **4 new agent-callable governance skills.** Cursor agents can use the
 AxonFlow read-side governance surface directly in conversation:
 `explain-decision`, `list-overrides`, `create-override`, and
 `revoke-override`. Joins the existing `audit-search` skill for full
 read-side parity.

## [1.0.0] - 2026-04-29 — Production, quality, and security hardening — upgrade encouraged

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

- The `DO_NOT_TRACK=1 is deprecated.` warning is no longer emitted on every hook invocation when `DO_NOT_TRACK=1` is set.
- Telemetry heartbeat now correctly classifies Community-SaaS sessions (was tagged `production` because the bootstrap-injected `AXONFLOW_AUTH` shadowed the resolver, sending `/health` probes to localhost and `platform_version=null` with the wrong `deployment_mode`).
- Bootstrap and heartbeat now run on macOS — `flock(1)` isn't on stock macOS, so the in-flight lock falls back to a `mkdir`-based atomic lock with stale-lock reclamation when `flock` is unavailable.

### Security

- `~/.config/axonflow/` and `~/.cache/axonflow/` permissions tightened to `0700` on every invocation (was: only set on creation via `mkdir -m 0700`, which left existing 0755 dirs unchanged).

## [0.5.2] - 2026-04-22

### Deprecated

- `DO_NOT_TRACK=1` as an AxonFlow telemetry opt-out — scheduled for removal after 2026-05-05 in the next major release. Use `AXONFLOW_TELEMETRY=off` instead. The plugin's `telemetry-ping.sh` emits a one-time stderr warning when `DO_NOT_TRACK=1` is the active control and `AXONFLOW_TELEMETRY=off` is not also set.

## [0.5.1] - 2026-04-19

### Added

- **Smoke E2E scenario** at the e2e test suite — runs
 `pre-tool-check.sh` against a reachable AxonFlow stack and asserts the
 hook exits 2 with `AxonFlow policy violation` + Plugin Batch 1
 richer-context markers on stderr. Exits 0 (`SKIP:`) when no stack is
 reachable.
- **`.github/workflows/smoke-e2e.yml`** — `workflow_dispatch` triggered job running the smoke scenario.
 Requires an operator-supplied endpoint (GitHub-hosted runners have no
 local stack), so not wired to PR events — PR smoke gating needs a
 self-hosted runner with a live stack.

Install-and-use matrix is exercised in the platform integration tests.

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
