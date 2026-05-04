# Manual runbook — Cursor `audit-search` runtime verification

Cursor's agent runs only inside the IDE. Until Cursor ships a headless mode,
this runbook is the rule-#1 runtime verification for the audit-search skill.
Run it once before tagging each release; capture the output into
`EVIDENCE.md` in this folder.

The accompanying `test.sh` enforces the gate: it refuses to pass if
`EVIDENCE.md` is missing or is more than 60 days old. That keeps the manual
verification from rotting silently.

## Prereqs

- AxonFlow stack reachable at `http://localhost:8080`
  (or set the URL you'll point Cursor's MCP at).
- Cursor IDE (any 3.x).
- This plugin's `mcp.json` already configured at the project root or in
  Cursor's MCP servers settings.

## Steps

1. **Open Cursor in the plugin repo:**
   ```bash
   /Applications/Cursor.app/Contents/Resources/app/bin/cursor /Users/saurabhjain/Development/axonflow-cursor-plugin
   ```

2. **Verify the MCP server is connected.** In Cursor settings → MCP, the
   `axonflow` server should show as connected (green dot). If it's not,
   confirm the URL in `mcp.json` matches your stack and re-launch Cursor.

3. **Open a chat panel in Composer / Agent mode** (the agent surface, not
   the inline edit surface).

4. **Send the prompt verbatim:**
   ```
   Use the search_audit_events MCP tool from the axonflow MCP server. Set
   limit=5. Then output exactly "SMOKE_RESULT: " followed by a one-line
   JSON summary of the result, like SMOKE_RESULT: {"total":N,"first_id":"..."}.
   ```

5. **Wait for the agent to invoke the tool.** Cursor surfaces tool calls
   inline in the chat with a "Tool used: search_audit_events" annotation
   and the JSON arguments. Confirm the call happened.

6. **Capture the run into `EVIDENCE.md`.** Replace the file with the new
   capture using this template:

```markdown
# Cursor audit-search runtime evidence

**Run date (UTC):** YYYY-MM-DD HH:MM
**Cursor version:** (from Cursor → About)
**Stack endpoint:** http://localhost:8080
**Operator:** (your name + email)

## Prompt

<paste the prompt you sent>

## Tool call (Cursor's annotation)

```
Tool: search_audit_events
Arguments: {"limit": 5}
```

## Tool result (Cursor's annotation)

<paste the raw JSON tool result Cursor showed>

## Agent reply

SMOKE_RESULT: {"total": N, "first_id": "..."}

## Pass/fail

- [x] Cursor invoked search_audit_events through its MCP runtime
- [x] Tool result returned without `is_error: true`
- [x] Agent emitted the SMOKE_RESULT marker
```

7. **Commit `EVIDENCE.md`** in the same PR that bumps the plugin version.
   The `test.sh` gate checks both presence and freshness; without a
   recent EVIDENCE.md the release-prep gate fails.

## What we're NOT doing here

- Not exercising the full lifecycle (create→list→explain→revoke). That
  belongs in its own runtime-e2e folder once Cursor headless lands; for
  now audit-search is the load-bearing manual check.
- Not asserting Cursor's tool descriptions are good enough that the
  agent picks the right tool from a vague hint. The prompt above is
  explicit; tool-discovery quality is a separate question that lives
  outside the runtime-path test.
