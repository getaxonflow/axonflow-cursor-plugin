---
name: recover-credentials
description: Recover lost AxonFlow plugin credentials by email magic link (W3 free-tier recovery)
---

Use this skill when the user has lost their AxonFlow plugin credentials —
typically because `~/.config/axonflow/try-registration.json` is missing,
unreadable, or bound to an account they no longer want to use — and needs
to recover access via the email the tenant was originally registered with.

The flow is implemented in `scripts/recover-credentials.sh` (a shell helper
the user invokes from a terminal). Cursor itself does not run plugin code
in a long-lived process and cannot prompt the user for an email + magic-link
token from its chat UI — running the script in the integrated terminal is
the right surface.

## What to do

1. Tell the user what's about to happen: "I'll run `scripts/recover-credentials.sh`
   in your terminal. It will ask for the email you registered with, send a
   magic link, then ask you to paste the token from the link."
2. Invoke the script via the Shell tool: `bash scripts/recover-credentials.sh`
   (run from the plugin's install directory, typically
   `~/.cursor/plugins/local/axonflow-cursor-plugin`).
3. The script writes the recovered credentials to
   `~/.config/axonflow/try-registration.json` (mode 0600). The community-saas
   bootstrap picks them up on the next governed tool call — no shell
   re-export, no Cursor reload required.

## What this skill does NOT do

- It does not create a new account from scratch — that path is automatic
  via the community-saas bootstrap when neither `AXONFLOW_ENDPOINT` nor
  `AXONFLOW_AUTH` is set.
- It does not move credentials between machines — recovery is per-email,
  not per-host. To set up a new machine for the same tenant, run recovery
  there too.
- It does not recover Pro license tokens (`AXONFLOW_LICENSE_TOKEN`) — those
  are the buyer's responsibility, delivered to the email at Stripe checkout.
  If the Pro user lost their license token, they recover it from the
  original `from=billing@getaxonflow.com` email rather than this flow.

## When to suggest it

Suggest this skill when the user reports any of:

- "I'm getting AxonFlow auth errors and I don't know my credentials"
- "I deleted ~/.config/axonflow"
- "I switched to a new laptop and the plugin won't auth"
- "The plugin says my credentials file has unsafe permissions"

Do NOT suggest it for:

- "What is my AxonFlow tenant ID?" — point them at
  `cat ~/.config/axonflow/try-registration.json | jq .tenant_id` instead.
- "I want to upgrade to Pro" — point them at the Stripe checkout surface;
  recovery is for free-tier credential loss only.
