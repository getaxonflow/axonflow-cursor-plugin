# Cursor audit-search runtime evidence

**Run date (UTC):** 2026-05-04 08:39
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** automated AppleScript drive (Cursor free-tier session)

## Seed step (direct MCP, same tenant Cursor sees)

A SQLi block was triggered through the unauthenticated MCP path so the
audit row lands in the same `community` tenant the Cursor MCP client
sees. Marker tag embedded in the SQL comment so the agent can grep for it.

Marker: `cursor-w2-audit-marker-1777883872-26221`

Direct API confirms 1 audit row containing the marker:
```
$ curl ... /api/v1/audit/search ... | jq '{total, hits: ([.entries[] | select(.query | contains())] | length)}'
{"total": 11, "hits": 1}
```

## Prompt

> Use the search_audit_events MCP tool from the axonflow MCP server with limit=50. Look through the entries array and find any entry whose query field contains the substring 'cursor-w2-audit-marker-1777883872-26221'. Output exactly SMOKE_RESULT: {"marker_found":true,"audit_id":"audit_..."} if you found it, or SMOKE_RESULT: {"marker_found":false} otherwise.

## Cursor's annotations

```
Preparing to use MCP tool

Got it. I'm going to (1) read the MCP tool schema for search_audit_events,
(2) call it with limit=50, then (3) scan the returned entries for your
marker substring and print the exact SMOKE_RESULT: line you requested.

Explored 1 file, 2 searches

Ran Search Audit Events in axonflow
  { "entries": [ ... ], ... }
```

## Agent reply

```
SMOKE_RESULT: {"marker_found":true,"audit_id":"audit_b3383e3c-7ce8-4a5b-9f9b-30edbb93a77d"}
```

## Pass/fail — outcome verified

- [x] Cursor invoked `search_audit_events` through its MCP runtime
- [x] Server returned audit entries (real platform answer, not a stub)
- [x] Agent FOUND the marker we seeded — `marker_found:true`
- [x] Agent reported the exact `audit_id` of the seeded row — `audit_b3383e3c-7ce8-4a5b-9f9b-30edbb93a77d`
- [x] End-to-end outcome (seed → cursor agent → audit search → marker found) verified

## Screenshot

`EVIDENCE.png` — agent panel showing the schema lookup, search invocation, and SMOKE_RESULT line.
