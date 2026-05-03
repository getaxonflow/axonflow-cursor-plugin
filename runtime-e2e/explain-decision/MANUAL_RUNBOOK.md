# Manual runbook — Cursor `explain-decision` runtime verification

Cursor's agent runs only inside the IDE. This runbook is the rule-#1
runtime verification for the explain-decision feature. Run it once before tagging
each release; capture the output into `EVIDENCE.md` in this folder.

The accompanying `test.sh` enforces the gate: it refuses to pass if
`EVIDENCE.md` is missing or is more than 60 days old. That keeps the
manual verification from rotting silently.

## Prereqs

- AxonFlow stack reachable at `http://localhost:8080` (or set the URL
  you'll point Cursor's MCP at).
- Cursor IDE (any 3.x).
- This plugin's `mcp.json` already configured at the project root or in
  Cursor's MCP servers settings.

## Steps

1. **Open Cursor in the plugin repo:**
   ```bash
   /Applications/Cursor.app/Contents/Resources/app/bin/cursor /Users/saurabhjain/Development/axonflow-cursor-plugin
   ```

2. **Verify the MCP server is connected.** In Cursor settings → MCP,
   the `axonflow` server should show as connected (green dot).

3. **Open a chat panel in Composer / Agent mode** (the agent surface).

4. **Send the prompt verbatim:**

   > Use the `explain_decision` MCP tool from the axonflow MCP server with arguments: decision_id="runtime-e2e-fabricated-id-12345". The platform will respond — expected outcome: not-found / "no explanation available" structured response. Output exactly `SMOKE_RESULT: ` followed by a one-line JSON summary of what happened.

5. **Wait for the agent to invoke the tool.** Cursor surfaces tool
   calls inline in the chat with a "Tool used: explain_decision" annotation.

6. **Capture the run into `EVIDENCE.md` using this template:**

```markdown
# Cursor explain-decision runtime evidence

**Run date (UTC):** YYYY-MM-DD HH:MM
**Cursor version:** (from Cursor → About)
**Stack endpoint:** http://localhost:8080
**Operator:** (your name + email)

## Prompt

<paste the prompt you sent>

## Tool call (Cursor's annotation)

```
Tool: explain_decision
Arguments: { ... }
```

## Tool result (Cursor's annotation)

<paste the raw tool result>

## Agent reply

SMOKE_RESULT: { ... }

## Pass/fail

- [ ] Cursor invoked explain_decision through its MCP runtime
- [ ] Tool result returned without is_error: true (or returned a
      structured negative for fabricated/non-applicable inputs)
- [ ] Agent emitted the SMOKE_RESULT marker
```

7. **Commit `EVIDENCE.md`** in the same PR that bumps the plugin
   version. The `test.sh` gate checks both presence and freshness;
   without recent EVIDENCE.md the release-prep gate fails.
