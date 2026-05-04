# Cursor list-overrides runtime evidence

**Run date (UTC):** 2026-05-04 00:29
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** Saurabh (saurabh.jain@getaxonflow.com)

## Prompt

> Use the list_overrides MCP tool from the axonflow MCP server with no arguments. Output exactly the literal text SMOKE_RESULT: followed by a one-line JSON summary like SMOKE_RESULT: {"count":N}.

## Cursor's annotations

```
Thought briefly
  Locating the list_overrides tool schema and invoking it.
  Explored 1 file, 1 search

  Ran  List Overrides  in axonflow
Use Allowlist >
```

## Agent reply

```
SMOKE_RESULT: {"count":2}
```

## Pass/fail

- [x] Cursor invoked `list_overrides` through its MCP runtime ("Ran List Overrides in axonflow")
- [x] Tool result returned successfully (count=2 — two overrides created during prior tests in this session)
- [x] Agent emitted the SMOKE_RESULT marker

## Screenshot

`EVIDENCE.png` in this folder.
