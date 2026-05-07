# Runtime E2E — Cursor can invoke each V1 Plugin Pro MCP tool

Drives the **same MCP wire path Cursor IDE uses** (the plugin's
`mcp.json` pointed at the agent's `/api/v1/mcp-server` endpoint, with
the same `X-Axonflow-Client` header Cursor sends — verified live in
the sister `mcp-session-headers/EVIDENCE.md` test) against the
**real hosted AxonFlow agent** at `https://try.getaxonflow.com`. Per
HARD RULE #0 — every byte through the test came from the real
plugin's MCP wire shape, real agent on prod (Community SaaS), real
registered tenant. No fixtures.

## What this test exercises

For each tool in the V1 PRD §V1 differentiator table, the test sends
a real JSON-RPC `tools/call` over the same MCP transport Cursor IDE
uses, and asserts the response shape against the locked V1 contract:

| # | Tool                              | Free-tier expectation                                                                              |
|---|-----------------------------------|----------------------------------------------------------------------------------------------------|
| 1 | `axonflow_list_pro_features`      | Returns 5 differentiators + `9.99` price + locked V1 buy URL                                       |
| 2 | `axonflow_get_cost_estimate`      | **Hidden** from `tools/list` (Pro-only per ADR-049 §5); when forced by-name returns `isError:true` + locked envelope (`limit_type=feature_pro_only` + `buy.stripe.com/...8k800`) |
| 3 | `axonflow_request_approval`       | Returns `approval_id` non-empty on first Free call (1/7d quota)                                    |
| 4 | `axonflow_create_tenant_policy`   | Returns `policy_id` non-empty (uses benign `pattern` to dodge static gate)                         |
| 5 | `axonflow_get_tenant_id`          | Returns matching `tenant_id` + `upgrade_url` to `getaxonflow.com/pricing`                          |

## Why wire-level + not raw IDE drive

Cursor IDE 3.2.x runs every MCP tool call through a **per-call
approval prompt** in the chat panel (the ⚠️ "Allow once / Allow
always" surface). For unattended automation, you'd need to either:

1. Pre-allowlist the 5 tools in Cursor's chat preferences before
   driving the prompt (see `MANUAL_RUNBOOK.md` for the operator-driven
   companion that does this), or
2. Click "Allow" 5 times during the prompt's run (defeats automation).

The mcp-session-headers test
([axonflow-cursor-plugin#46](https://github.com/getaxonflow/axonflow-cursor-plugin/pull/46))
already proved Cursor IDE sends the plugin's `mcp.json` headers
verbatim on every MCP-server request — `X-Axonflow-Client`,
`Authorization`, `X-License-Token`, all present on every wire hit.
Combined with this test's assertion on the same wire shape, the
runtime claim "Cursor IDE can invoke each V1 Pro MCP tool" is fully
proven by composition:

- mcp-session-headers test → Cursor sends correct headers
- this test → those headers + tools/call shape produce the locked V1
  responses for all 5 tools

The companion `MANUAL_RUNBOOK.md` is the GUI-side check an operator
runs once before any cursor-plugin release; the screenshots under
`EVIDENCE/<utc-ts>/cursor-ide-companion-drive/` are the captured
GUI-drive output from 2026-05-07.

## Tool allowlisting (when running the IDE companion)

When driving Cursor IDE directly (per `MANUAL_RUNBOOK.md`, NOT this
script), pre-allowlist the 5 V1 Pro tools so the chat session doesn't
prompt per-tool. Two paths:

1. **Per-conversation (recommended for one-off proof runs).** In
   Cursor's chat panel, click the ⚙️ icon next to the tool dropdown,
   choose **Auto-run for this conversation**, and tick:
   - `axonflow_list_pro_features`
   - `axonflow_get_cost_estimate`
   - `axonflow_request_approval`
   - `axonflow_create_tenant_policy`
   - `axonflow_get_tenant_id`
2. **Workspace settings (for repeated dev runs).** Add to
   `.cursor/settings.json`:
   ```json
   {
     "chat.allowedTools": [
       "mcp__axonflow__axonflow_list_pro_features",
       "mcp__axonflow__axonflow_get_cost_estimate",
       "mcp__axonflow__axonflow_request_approval",
       "mcp__axonflow__axonflow_create_tenant_policy",
       "mcp__axonflow__axonflow_get_tenant_id"
     ]
   }
   ```

**Without this step, Cursor will prompt per-tool and the operator
must approve each one manually.** That's fine for one-off runs but
breaks any expectation of unattended capture. Confirm one trivial
tool fires without a prompt before sending the full 5-tool prompt —
that's the "is the allowlist live?" check.

## Pre-conditions

The wire-level test handles all of these automatically and SKIPs
cleanly when unavailable:

- `jq` and `curl` on `PATH`.
- `${AGENT_URL}/health` reachable (defaults to `https://try.getaxonflow.com`).
- Either `TENANT=` and `SECRET=` env vars (re-use an existing tenant)
  or `/api/v1/register` lets us register a fresh one. The endpoint
  has a per-IP 5/hour rate limit; reuse env if you're iterating.
- Optional: AWS credentials + `db_helpers.sh` from
  `axonflow-enterprise/runtime-e2e/v1_paid_tier_staging/lib/`. When
  available, the test cleans the tenant's `hitl_approval_queue` +
  `dynamic_policies` rows before the run so the Free-tier 1/7d HITL
  window and 2-active-policy max don't trip spuriously on re-runs.

## Usage

```bash
# Default — register a fresh tenant against try.getaxonflow.com:
bash runtime-e2e/v1_pro_mcp_tools_invocable/test.sh

# Re-use an existing tenant (avoids the per-IP /register rate limit):
TENANT=cs_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  bash runtime-e2e/v1_pro_mcp_tools_invocable/test.sh

# Self-hosted:
AGENT_URL=http://localhost:8080 \
  TENANT=demo-client SECRET=demo-secret \
  bash runtime-e2e/v1_pro_mcp_tools_invocable/test.sh
```

## Evidence layout

`EVIDENCE/<utc-ts>/`:

- `tools_list.json` — agent's response to `tools/list` for this Free
  tenant (proves what's advertised vs gated)
- `<tool>.json` — full JSON-RPC response for each `tools/call`
- `cursor-ide-companion-drive/*.png` — GUI screenshots from a
  one-time IDE drive on 2026-05-07 (kept as a record of how Cursor
  IDE renders the 5 tool calls in its chat panel)
- `summary.txt` — top-line PASS/FAIL with tenant ID + client header

The evidence dir contains tenant_id values (public identifiers) but
**never** the bcrypt-validated `secret` Basic-auth credential or any
license token — both are scrubbed by the assertion paths and only ever
flow on the wire as `Authorization: Basic <base64>` headers.
