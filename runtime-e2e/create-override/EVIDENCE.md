# Cursor create-override runtime evidence

**Run date (UTC):** 2026-05-04 08:32
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080 (post-migration-076)
**Operator:** automated AppleScript drive (Cursor free-tier session)
**Note:** Cursor's "Use Allowlist >" UI element appears alongside MCP tool output; the agent dispatched the call and surfaced the platform's response without operator intervention this run.

## Prompt

> Use the create_override MCP tool from the axonflow MCP server with policy_id="sys_sqli_admin_bypass", policy_type="static", and override_reason="runtime-e2e rejection verification 2026-05-04". The platform should reject this with HTTP 403 because sys_sqli_admin_bypass is severity=critical post-migration-076. After receiving the tool result, output exactly the literal text SMOKE_RESULT: followed by a single-line JSON like SMOKE_RESULT: {"dispatched":true,"server_rejected":true,"http_status":403} or SMOKE_RESULT: {"dispatched":true,"server_rejected":false} if it unexpectedly succeeded.

## Cursor's annotations

```
Verifying the create_override tool schema, then attempting to create the
override and reporting whether the server rejected it with HTTP 403.

Read create_override.json | 1-15
Ran Create Override in axonflow

Use Allowlist >
```

## Agent reply

```
SMOKE_RESULT: {"dispatched":true,"server_rejected":true,"http_status":403}
```

## Pass/fail

- [x] Cursor invoked `create_override` through its MCP runtime ("Ran Create Override in axonflow")
- [x] Server returned the expected HTTP 403 (post-migration-076 enforcement of `allow_override=FALSE` on severity=critical system policies)
- [x] Agent surfaced the rejection structurally via `SMOKE_RESULT: {"server_rejected":true,"http_status":403}`
- [x] Outcome verified: this is the new W2 rejection path, end-to-end through the Cursor runtime

## Server-side cross-check

```
$ curl -X POST -H "Authorization: Basic $(printf 'demo-client:demo-secret' | base64)" \
       -H "X-Tenant-ID: local-dev-org" -H "X-User-Email: dev@getaxonflow.com" \
       -H "Content-Type: application/json" \
       -d '{"policy_id":"sys_sqli_admin_bypass","policy_type":"static","override_reason":"verify-w2-fix"}' \
       http://localhost:8080/api/v1/overrides
HTTP 403
{"success":false,"error":"Critical-risk policies cannot be overridden"}
```

Direct API and Cursor runtime path agree on the rejection.

## Screenshot

`EVIDENCE.png` in this folder — agent panel showing the schema lookup, the `Ran Create Override in axonflow` invocation log, and the structured `SMOKE_RESULT: {"dispatched":true,"server_rejected":true,"http_status":403}` reply.
