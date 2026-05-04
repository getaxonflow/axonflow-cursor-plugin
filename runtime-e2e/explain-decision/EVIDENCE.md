# Cursor explain-decision runtime evidence

**Run date (UTC):** 2026-05-04 00:27
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** Saurabh (saurabh.jain@getaxonflow.com)

## Prompt

> Use the explain_decision MCP tool from the axonflow MCP server with decision_id="runtime-e2e-fabricated-id-12345". The platform will return a not-found / no-explanation response. Output exactly the literal text SMOKE_RESULT: followed by a one-line JSON summary like SMOKE_RESULT: {"dispatched":true,"not_found":true}.

## Cursor's annotations

```
Thought for 1s
  Locating the explain_decision tool schema and invoking it with the given decision_id.
  Explored 1 file, 1 search

  Ran  Explain Decision  in axonflow
  decision_id  runtime-e2e-fabricated-id-12345

  explain decision failed: orchestrator returned 404:
  {"request_id":"","success":false,"error":"Decision not found or past retention window","redacted":false,"policy_info":null,"provider_info":null,"processing_time":""}

Use Allowlist >
```

## Agent reply

```
SMOKE_RESULT: {"dispatched":true,"not_found":true}
```

## Pass/fail

- [x] Cursor invoked `explain_decision` through its MCP runtime ("Ran Explain Decision in axonflow")
- [x] Platform answered with a structured 404 carrying "Decision not found or past retention window" — proves dispatch reached the orchestrator
- [x] Agent emitted the SMOKE_RESULT marker with `not_found: true`

## Screenshot

`EVIDENCE.png` in this folder.
