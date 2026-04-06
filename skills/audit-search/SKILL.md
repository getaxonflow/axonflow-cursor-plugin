---
name: audit-search
description: Search AxonFlow audit trail for recent tool executions, policy decisions, and compliance evidence
---

Use this skill to inspect what happened recently — which tools were called, what was blocked, and what PII was detected.

Call the `search_audit_events` MCP tool. Optionally provide:
- `from`: start time (ISO 8601, defaults to last 15 minutes)
- `to`: end time (ISO 8601, defaults to now)
- `limit`: max events to return (default 20, max 100)
- `request_type`: filter by type (e.g., `tool_call_audit`, `llm_call`)

Present the results as a summary table showing timestamp, tool name, decision (allowed/blocked), and key details.
