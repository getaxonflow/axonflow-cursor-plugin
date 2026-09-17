# Manual runbook — Cursor `list-overrides` runtime verification

Cursor's agent runs only inside the IDE. This runbook is the rule-#1
runtime verification for the list-overrides feature. Run it once before tagging
each release; capture the output into `EVIDENCE.md` in this folder.

The accompanying `test.sh` enforces the gate: it refuses to pass if
`EVIDENCE.md` is missing or is more than 60 days old. That keeps the
manual verification from rotting silently.

> **AxonFlow v11.0.0: session overrides are retired.** `create_override` and `delete_override` no longer write: with a per-user identity they answer a tool error whose text begins `LEGACY_POLICY_WRITE_FROZEN: `, and on a session with no per-user identity `create_override` is refused for that reason first (this plugin's `mcp.json` sends no `X-User-Email`, so a Cursor session usually gets the identity refusal). `list_overrides` is an unchanged read. The steps below expect those answers. The `EVIDENCE.md` beside this runbook predates v11.0.0: no new capture exists, because no headless Cursor exists and no supervised IDE launch was permitted for the change that retargeted this runbook, so what changed is this runbook, not the evidence.

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

   > Use the `list_overrides` MCP tool from the axonflow MCP server with no arguments. Output exactly `SMOKE_RESULT: ` followed by a one-line JSON object with "count" set to the count in the tool answer.

5. **Wait for the agent to invoke the tool.** Cursor surfaces tool
   calls inline in the chat with a "Tool used: list_overrides" annotation.

6. **Capture the run into `EVIDENCE.md` using this template:**

```markdown
# Cursor list-overrides runtime evidence

**Run date (UTC):** YYYY-MM-DD HH:MM
**Cursor version:** (from Cursor → About)
**Stack endpoint:** http://localhost:8080
**Operator:** (your name + email)

## Prompt

<paste the prompt you sent>

## Tool call (Cursor's annotation)

```
Tool: list_overrides
Arguments: { ... }
```

## Tool result (Cursor's annotation)

<paste the raw tool result>

## Agent reply

SMOKE_RESULT: { ... }

## Pass/fail

- [ ] Cursor invoked list_overrides through its MCP runtime
- [ ] Tool result returned without is_error: true, carrying a count
- [ ] The count equals `GET /api/v1/overrides` on the same stack (none can be
      created from v11.0.0, so it does not grow)
- [ ] Agent emitted the SMOKE_RESULT marker
```

7. **Commit `EVIDENCE.md`** in the same PR that bumps the plugin
   version. The `test.sh` gate checks both presence and freshness;
   without recent EVIDENCE.md the release-prep gate fails.
