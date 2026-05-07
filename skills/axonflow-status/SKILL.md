---
name: axonflow-status
description: Show AxonFlow plugin status — tenant_id (needed for Stripe Pro upgrade), tier (Free/Pro), Pro license expiry date, endpoint, and config file paths
---

Use this skill when the user asks any of:

- "What is my AxonFlow tenant_id?" — needed to paste into the custom field at
  Stripe Checkout (`https://getaxonflow.com/pricing/`) when buying Pro.
- "Am I on Pro or Free tier?"
- "When does my Pro license expire?" / "How many days do I have left?"
- "Is my Pro license token loaded?"
- "Where does the plugin think AxonFlow is?" / "What endpoint am I hitting?"
- "How do I upgrade to Pro?" / "How do I renew?"

## What to do

1. **Prefer the local script — it answers without an agent round-trip.**
   `scripts/status.sh` reads `tenant_id` and tier directly from the
   plugin's persisted state (`~/.config/axonflow/try-registration.json`,
   the configured license token's JWT `exp` claim). No HTTP call to the
   agent. Faster, works offline, and works exactly when the user
   typically asks this question — while debugging the Stripe Checkout
   flow, when the agent isn't reachable yet, or when they just want a
   quick read on which tenant they're on. Tell the user: "I'll run
   `scripts/status.sh` to print your tenant_id, tier, and Pro license
   expiry locally — no agent round-trip." Invoke via the Shell tool:
   `bash scripts/status.sh` — run it from the plugin's install
   directory, typically `~/.cursor/plugins/local/axonflow-cursor-plugin`.
2. **Use the MCP tool only when the user explicitly wants server-truth.**
   The `axonflow_get_tenant_id` MCP tool returns the same shape but
   resolved server-side, which catches edge cases the local script
   can't: a Pro license revoked by the platform, clock skew on JWT
   `exp`, or a server-side tier override. Use it when the user asks
   something like "is my Pro license still valid on the server" or
   "the agent is rejecting me, what does the agent see for me?". In all
   other cases the local script is sufficient and cheaper.
3. Surface the `tenant_id:` line and the `tier` line back to the user. If
   they asked about upgrading, point them at the `upgrade_url` printed by
   the script, and remind them they need to paste the `tenant_id` into
   the Stripe Checkout custom field.

## Related agent-callable tools

When the AxonFlow MCP server is available the agent can answer related
questions directly via tool calls without spawning shell scripts:

- `axonflow_get_tenant_id` — tenant identity + tier + upgrade URLs.
- `axonflow_list_pro_features` — locked V1 Pro feature list (5
  differentiators + $9.99 / 90 days pricing). Useful when the user asks
  "what would I get if I upgraded?".
- `axonflow_request_approval` — file a HITL approval request before a
  risky operation (Free tier: 1 per rolling 7d; Pro: unlimited).
- `axonflow_create_tenant_policy` — create a custom tenant policy (Free
  tier: 2 active max; Pro: unlimited).
- `axonflow_get_cost_estimate` — pre-flight LLM cost for a multi-step
  plan. Pro-only — the tool isn't visible to Free callers.

Prefer these tools over equivalent shell scripts when both exist; they
are auth-context-aware on the server side and don't require local shell
state.

## Tier line shape

The script's `tier` line takes one of three shapes — surface whichever one
the user got and act on it:

- `tier   Pro (expires 2026-08-03, 90 days remaining)` — paid Pro tier
  active. Pro-tier daily quotas + retention + governance hold for the
  remaining window.
- `tier   Pro (expires UNKNOWN — could not parse token)` — token configured
  but its JWT body did not parse. Treat as Pro for display; the platform
  is the source of truth on validity.
- `tier   Free (Pro expired 2026-02-04 — visit https://getaxonflow.com/pricing/ to renew)`
  — token is on disk but its `exp` has passed. The plugin will not forward
  an expired token; user must buy a renewal and replace the token via
  `AXONFLOW_LICENSE_TOKEN=<new>` env or the on-disk file.
- `tier   Free (no Pro license configured)` — no token loaded.

When the user lands on `Free (Pro expired …)`, point them at the renew
URL embedded in the line and the `export AXONFLOW_LICENSE_TOKEN=AXON-...`
hint the script prints below.

## What this skill does NOT do

- It does NOT print the full Pro license token. Only the last 4 chars are
  shown (`AXON-...XXXX`) — the token is a bearer credential and the script
  output may be screen-shared or pasted into a support ticket. If the user
  asks for the full token, point them at the original Stripe / billing
  email rather than the script output.
- It does NOT call the agent to verify token validity — the platform is the
  source of truth. The script extracts the JWT `exp` for display only;
  signature validation is the platform's job. If the agent later rejects
  the token (revoked, malformed), the user will see that on their next
  governed tool call.
- It does NOT perform recovery. If `tenant_id` is `(not registered)` and
  the user expected one, suggest the `/recover-credentials` skill.

## When to suggest it

Suggest this skill when the user reports any of:

- "I'm trying to buy Pro and need my tenant_id"
- "How do I know if my Pro upgrade went through?"
- "When does my Pro license expire?"
- "Which AxonFlow am I connected to?"
- "Is my license token configured correctly?"

Do NOT suggest it for:

- Recovering lost credentials → use `/recover-credentials` instead.
- Listing active governance policies → use `/policy-list` instead.
- Querying recent governance activity → use `/policy-stats` instead.
