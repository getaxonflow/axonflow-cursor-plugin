# Cursor audit-search runtime evidence

**Run date (UTC):** 2026-05-04 00:25
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** Saurabh (saurabh.jain@getaxonflow.com)
**Driven by:** AppleScript automation from Claude Code session (see `../AUTOMATION_ATTEMPT.md` for setup notes)

## Prompt

> Use the search_audit_events MCP tool from the axonflow MCP server with limit=5. Output exactly the literal text SMOKE_RESULT: followed by a one-line JSON summary like SMOKE_RESULT: {"total":N,"first_id":"..."}.

## Cursor's annotations (from `EVIDENCE.png`)

```
Thought briefly
  Locating the search_audit_events tool schema and invoking it with limit=5.
  Explored 1 file, 1 search

  Ran  Search Audit Events  to axonflow
  Use Allowlist >

Thought for 1s
```

## Agent reply

```
SMOKE_RESULT: {"total":5,"first_id":"audit_1777847089_cyd7vsi7"}
```

## Pass/fail

- [x] Cursor invoked `search_audit_events` through its MCP runtime ("Ran Search Audit Events to axonflow")
- [x] Tool result returned without `is_error: true` — agent consumed real audit data (total=5)
- [x] Agent emitted the SMOKE_RESULT marker with concrete data from the live stack
- [x] `audit_<id>` prefix on `first_id` confirms server-side execution against the live `audit_logs` table

## Screenshot

`EVIDENCE.png` in this folder — captured immediately after the agent finished, shows the full chat panel with prompt + tool annotation + reply.
