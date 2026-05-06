---
name: axonflow-status
description: Show AxonFlow plugin status — tenant_id (needed for Stripe Pro upgrade), tier (Free/Pro), Pro license expiry date, endpoint, and config file paths
---

Use this skill when the user asks any of:

- "What is my AxonFlow tenant_id?" — needed to paste into the custom field at
  Stripe Checkout (`https://www.getaxonflow.com/pricing/`) when buying Pro.
- "Am I on Pro or Free tier?"
- "When does my Pro license expire?" / "How many days do I have left?"
- "Is my Pro license token loaded?"
- "Where does the plugin think AxonFlow is?" / "What endpoint am I hitting?"
- "How do I upgrade to Pro?" / "How do I renew?"

## What to do

1. Tell the user what you're about to do: "I'll run `scripts/status.sh` in
   your terminal to print your tenant_id, tier, and Pro license expiry."
2. Invoke the script via the Shell tool:
   `bash scripts/status.sh`
   Run it from the plugin's install directory, typically
   `~/.cursor/plugins/local/axonflow-cursor-plugin`.
3. Surface the `tenant_id:` line and the `tier` line back to the user. If they
   asked about upgrading, point them at the `upgrade` URL printed in the
   output and remind them they need to paste the `tenant_id` into the Stripe
   Checkout custom field.

## Tier line shape

The script's `tier` line takes one of three shapes — surface whichever one
the user got and act on it:

- `tier   Pro (expires 2026-08-03, 90 days remaining)` — paid Pro tier
  active. Pro-tier daily quotas + retention + governance hold for the
  remaining window.
- `tier   Pro (expires UNKNOWN — could not parse token)` — token configured
  but its JWT body did not parse. Treat as Pro for display; the platform
  is the source of truth on validity.
- `tier   Free (Pro expired 2026-02-04 — visit https://www.getaxonflow.com/pricing/ to renew)`
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
