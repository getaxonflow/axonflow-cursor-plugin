# Cursor revoke-override runtime evidence

**Run date (UTC):** 2026-05-04 08:47
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** automated AppleScript drive (Cursor free-tier session)

## Seed step (real override in same tenant Cursor sees)

A real override was created via the unauthenticated MCP path so it
lands in the `community` tenant the Cursor MCP client sees. The
agent is then asked to revoke that exact id.

Seeded id: `82c48a22-3aae-42e1-bf1d-bdd3afdf3bbb` (sys_pii_email, ttl=300s)

## Prompt

> Use the delete_override MCP tool from the axonflow MCP server with override_id="82c48a22-3aae-42e1-bf1d-bdd3afdf3bbb". Output exactly SMOKE_RESULT: {"dispatched":true,"revoked":true} on success or SMOKE_RESULT: {"dispatched":true,"revoked":false} on error.

## Cursor's annotations

```
Creating the schema and calling the tool

I'm going to read the delete_override tool schema, call it with your
override_id, then report whether revocation succeeded based on the MCP
response (or error).

Read delete_override.json | 1-17
Ran Delete Override in axonflow
```

## Agent reply

```
SMOKE_RESULT: {"dispatched":true,"revoked":true}
```

## Server-side verification

```
$ curl ... list_overrides include_revoked=true | jq '... | select(.id == "82c48a22-3aae-42e1-bf1d-bdd3afdf3bbb")'
{
  "id": "82c48a22-3aae-42e1-bf1d-bdd3afdf3bbb",
  "revoked_at": "2026-05-04T08:47:07.778043Z"
}
```

## Pass/fail — outcome verified

- [x] Cursor invoked `delete_override` through its MCP runtime
- [x] Server returned success and the agent surfaced `revoked:true`
- [x] Server-side state confirms the override is in fact revoked (`revoked_at` populated)
- [x] End-to-end outcome (seed → cursor agent → revoke → server-side state changed) verified

## Screenshot

`EVIDENCE.png` — agent panel showing schema lookup, delete_override invocation, and SMOKE_RESULT with revoked:true.
