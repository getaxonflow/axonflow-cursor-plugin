# Cursor explain-decision runtime evidence

**Run date (UTC):** 2026-05-04 08:43
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** automated AppleScript drive (Cursor free-tier session)

## Seed step (real platform block in same tenant Cursor sees)

A SQLi pattern was sent through the unauthenticated MCP path so the
block decision lands in the `community` tenant the Cursor MCP client
sees. The seed produced decision_id `b3383e3c-7ce8-4a5b-9f9b-30edbb93a77d` with policy
`sys_sqli_admin_bypass` (Authentication Bypass, severity=critical,
risk_level=critical post-migration-076).

## Prompt

> Use the explain_decision MCP tool from the axonflow MCP server with decision_id="b3383e3c-7ce8-4a5b-9f9b-30edbb93a77d". From the result, extract the policy name. Output exactly SMOKE_RESULT: {"explanation_present":true,"policy_name":"..."} or SMOKE_RESULT: {"explanation_present":false}.

## Cursor's annotations

```
I'll read the explain_decision tool schema, call it with the decision_id,
then extract the matched policy name from the returned explanation
payload and print the exact SMOKE_RESULT: line you requested.

Read explain_decision.json | 1-17
Ran Explain Decision in axonflow

Quick fix: I'll retry the MCP call, passing decision_id explicitly as
arguments (the tool requires it), then I'll extract the policy name
from the returned explanation.

Ran Explain Decision in axonflow
```

## Agent reply

```
SMOKE_RESULT: {"explanation_present":true,"policy_name":"Authentication Bypass"}
```

## Pass/fail — outcome verified

- [x] Cursor invoked `explain_decision` through its MCP runtime (twice — first call needed argument-shape correction; second call succeeded)
- [x] Server returned a real explanation payload for a real decision_id
- [x] Agent extracted and surfaced the actual policy name: `Authentication Bypass` — matches the policy that fired on the seeded SQLi block
- [x] End-to-end outcome (real block → real decision_id → cursor agent → real explanation → policy name surfaced) verified

## Screenshot

`EVIDENCE.png` — agent panel showing schema lookup, two explain_decision invocations, and the final SMOKE_RESULT with the policy name.
