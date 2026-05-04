---
name: axonflow-status
description: Show AxonFlow plugin status — tenant_id (needed for Stripe Pro upgrade), tier (Free/Pro), endpoint, and config file paths
---

Use this skill when the user asks any of:

- "What is my AxonFlow tenant_id?" — needed to paste into the custom field at
  Stripe Checkout (`https://getaxonflow.com/pro`) when buying Pro.
- "Am I on Pro or Free tier?"
- "Is my Pro license token loaded?"
- "Where does the plugin think AxonFlow is?" / "What endpoint am I hitting?"
- "How do I upgrade to Pro?"

## What to do

1. Tell the user what you're about to do: "I'll run `scripts/status.sh` in
   your terminal to print your tenant_id and tier."
2. Invoke the script via the Shell tool:
   `bash scripts/status.sh`
   Run it from the plugin's install directory, typically
   `~/.cursor/plugins/local/axonflow-cursor-plugin`.
3. Surface the `tenant_id:` line and the `tier` line back to the user. If they
   asked about upgrading, point them at the `upgrade` URL printed in the
   output and remind them they need to paste the `tenant_id` into the Stripe
   Checkout custom field.

## What this skill does NOT do

- It does NOT print the full Pro license token. Only the last 4 chars are
  shown (`AXON-...XXXX`) — the token is a bearer credential and the script
  output may be screen-shared or pasted into a support ticket. If the user
  asks for the full token, point them at the original Stripe / billing
  email rather than the script output.
- It does NOT call the agent to verify token validity — the platform is the
  source of truth. The script reports "Pro" whenever a token is loaded; if
  the agent later rejects the token (revoked, malformed, expired), the
  user will see that on their next governed tool call.
- It does NOT perform recovery. If `tenant_id` is `(not registered)` and
  the user expected one, suggest the `/recover-credentials` skill.

## When to suggest it

Suggest this skill when the user reports any of:

- "I'm trying to buy Pro and need my tenant_id"
- "How do I know if my Pro upgrade went through?"
- "Which AxonFlow am I connected to?"
- "Is my license token configured correctly?"

Do NOT suggest it for:

- Recovering lost credentials → use `/recover-credentials` instead.
- Listing active governance policies → use `/policy-list` instead.
- Querying recent governance activity → use `/policy-stats` instead.
