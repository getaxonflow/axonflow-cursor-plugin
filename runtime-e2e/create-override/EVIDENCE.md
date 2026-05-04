# Cursor create-override runtime evidence

**Run date (UTC):** 2026-05-04 00:30
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** Saurabh (saurabh.jain@getaxonflow.com)
**Note:** Cursor surfaced an "Allowlist MCP Tool / Run / Skip" confirmation before invoking write tools — operator clicked Run. (See `../AUTOMATION_ATTEMPT.md` for details on how Cursor's mutation gate interacts with automation.)

## Prompt

> Use the create_override MCP tool from the axonflow MCP server with policy_id="sys_sqli_admin_bypass", policy_type="static", and override_reason="runtime-e2e dispatch verification (cursor)". Output exactly the literal text SMOKE_RESULT: followed by a one-line JSON summary like SMOKE_RESULT: {"dispatched":true,"created":true} or SMOKE_RESULT: {"dispatched":true,"server_rejected":true}.

## Cursor's annotations

```
Ran  Create Override  in axonflow
  policy_id        sys_sqli_admin_bypass
  policy_type      static
  override_reason  runtime-e2e dispatch verification (cursor)

  {
    "created_at":  "2026-05-03T22:30:26.84592962962",
    "expires_at":  "2026-05-03T23:30:26.84592962962",
    "id":          "332ddb73b-f876-4b73-9927-c4bd5077c7144",
    "policy_id":   "sys_sqli_admin_bypass",
    "policy_type": "static",
    "ttl_seconds": 3600
  }

Use Allowlist >
```

## Agent reply

```
SMOKE_RESULT: {"dispatched":true,"created":true}
```

## Pass/fail

- [x] Cursor invoked `create_override` through its MCP runtime ("Ran Create Override in axonflow")
- [x] Server returned a structured success with override id, expiration, and TTL
- [x] Agent emitted the SMOKE_RESULT marker

## Important finding (resolved 2026-05-04)

This evidence was captured against a stack BEFORE the platform fix that promotes severity='critical' system policies to risk_level='critical'/allow_override=FALSE. At capture time the override was created successfully even though `sys_sqli_admin_bypass` is severity=critical — that was a real platform-side bug.

The fix is now shipped on the running stack. A fresh invocation of the same prompt against the post-fix stack returns HTTP 403 ("Critical-risk policies cannot be overridden") through the same Cursor MCP runtime path. Server-side verification on the post-fix stack:

```
$ curl -X POST -H "Authorization: Basic …" -H "X-Tenant-ID: local-dev-org" -H "X-User-Email: dev@getaxonflow.com" \
       -d '{"policy_id":"sys_sqli_admin_bypass","policy_type":"static","override_reason":"verify-w2-fix"}' \
       http://localhost:8080/api/v1/overrides
HTTP 403
{"success":false,"error":"Critical-risk policies cannot be overridden"}
```

The runtime path itself (Cursor → MCP server → orchestrator) is unchanged — only the orchestrator's response on the rejection path is new. The screenshot and dispatch evidence above remain valid for the runtime path; the "create succeeded" outcome it documents has been corrected by the platform fix.

## Screenshot

`EVIDENCE.png` in this folder.
