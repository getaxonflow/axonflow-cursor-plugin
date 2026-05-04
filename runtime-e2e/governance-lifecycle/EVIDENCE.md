# Cursor governance-lifecycle runtime evidence (full mutation lifecycle)

**Run date (UTC):** 2026-05-04 08:34
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080 (post-migration-076 — sys_pii_email is overridable, sys_sqli_admin_bypass is not)
**Operator:** automated AppleScript drive (Cursor free-tier session)

## Prompt

> Run a 5-step W2 governance lifecycle smoke test using the axonflow MCP server. Step 1: call list_overrides with no arguments and note count. Step 2: call create_override with policy_id="sys_pii_email", policy_type="static", override_reason="cursor-lifecycle-2026-05-04". Capture the returned id. Step 3: call list_overrides again, note new count. Step 4: call delete_override with that id. Step 5: call list_overrides again. Output exactly SMOKE_RESULT: followed by single-line JSON like SMOKE_RESULT: {"baseline":N,"after_create":N,"after_revoke":N,"created_id":"..."}.

## Cursor's annotations

```
Running the 5 calls in order and tracking the override counts plus the
created override id.

Ran List Overrides    in axonflow
Ran Create Override   in axonflow
Ran List Overrides    in axonflow
Ran Delete Override   in axonflow
Ran List Overrides    in axonflow

Use Allowlist >
```

## Agent reply

```
SMOKE_RESULT: {"baseline":1,"after_create":2,"after_revoke":1,"created_id":"63b3935-2842-4496-8275-080d8336553c"}
```

## Pass/fail — full mutation lifecycle verified

- [x] Cursor invoked `list_overrides` THREE times in one session (steps 1, 3, 5) — read-side coherence
- [x] Cursor invoked `create_override` (step 2) — write-side dispatch
- [x] Cursor invoked `delete_override` (step 4) — revoke dispatch
- [x] Override count went UP after create (`baseline=1 → after_create=2`)
- [x] Override count went DOWN after revoke (`after_create=2 → after_revoke=1`)
- [x] State transitions match the expected lifecycle — outcome verified end-to-end through the Cursor runtime
- [x] No human dialog-clicking required — fully autonomous AppleScript drive on the Cursor free tier

## Note on prior "license required" claim

A previous version of this EVIDENCE.md said the full mutation lifecycle was gated on `AXONFLOW_LICENSE` and could only be exercised on an evaluation-license stack. That was true pre-migration-076 because community-mode seed policies all had `allow_override=FALSE`. Migration 076 corrected the seed-vs-runtime gap (severity=critical → risk_level=critical/allow_override=FALSE; everything else stayed `TRUE` per category mapping in migration 070), so `sys_pii_email` (severity=medium, risk_level=medium, allow_override=TRUE) is now overridable in pure community mode — no license required.

## Screenshot

`EVIDENCE.png` — agent panel showing all 5 tool dispatches in sequence and the final SMOKE_RESULT line with the captured state transitions.
