# Cursor list-overrides runtime evidence

**Run date (UTC):** 2026-05-04 08:45
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** automated AppleScript drive (Cursor free-tier session)

## Seed step (real override in same tenant Cursor sees)

A real override was created via the unauthenticated MCP path so it
lands in the `community` tenant the Cursor MCP client sees. Reason
tag was unique per run so the agent could find this specific override.

Marker: `cursor-list-runtime-1777884342`
Seeded id: `37057efc-9bbd-418c-a4b0-81f6a993e04b`

## Prompt

> Use the list_overrides MCP tool from the axonflow MCP server with no arguments. Find the override whose override_reason field contains the substring 'cursor-list-runtime-1777884342'. Output exactly SMOKE_RESULT: {"found":true,"id":"..."} if you find it, or SMOKE_RESULT: {"found":false} otherwise.

## Cursor's annotations

```
Planning a schema read

I'm going to read the list_overrides tool schema, call it with no
arguments, then scan the returned overrides for an override_reason
containing your substring and print the exact SMOKE_RESULT line.

Read list_overrides.json | 1-19
Ran List Overrides in axonflow
```

## Agent reply

```
SMOKE_RESULT: {"found":true,"id":"37057efc-9bbd-418c-a4b0-81f6a993e04b"}
```

## Pass/fail — outcome verified

- [x] Cursor invoked `list_overrides` through its MCP runtime
- [x] Server returned the active overrides for tenant=`community`
- [x] Agent FOUND the override we seeded — `found:true`
- [x] Agent returned the EXACT seeded UUID — `37057efc-9bbd-418c-a4b0-81f6a993e04b` matches the seed
- [x] End-to-end outcome (seed → cursor agent → list → reason match → exact UUID returned) verified

## Screenshot

`EVIDENCE.png` — agent panel showing schema lookup, list invocation, and SMOKE_RESULT with exact UUID.
