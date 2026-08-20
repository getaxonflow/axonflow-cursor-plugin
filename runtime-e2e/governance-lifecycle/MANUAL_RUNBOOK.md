# Manual runbook - Cursor `governance-lifecycle` runtime verification

Cursor's agent runs only inside the IDE. This runbook is the rule-#1
runtime verification for the governance-lifecycle feature. Run it once before tagging
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

4. **Send the prompt verbatim** (substitute today's date into the
   override_reason):

   > Run a 5-step W2 governance lifecycle smoke test using the axonflow MCP server. Step 1: call list_overrides with no arguments and note count. Step 2: call create_override with policy_id="sys_pii_email", policy_type="static", override_reason="cursor-lifecycle-YYYY-MM-DD". Capture the returned id. Step 3: call list_overrides again, note new count. Step 4: call delete_override with that id. Step 5: call list_overrides again. Output exactly SMOKE_RESULT: followed by single-line JSON like SMOKE_RESULT: {"baseline":N,"after_create":N,"after_revoke":N,"created_id":"..."}.

5. **Wait for the agent to invoke the tools.** Cursor surfaces tool
   calls inline in the chat with "Ran List Overrides in axonflow" style
   annotations; expect five of them (list, create, list, delete, list).

6. **Capture the run into `EVIDENCE.md` using this template:**

```markdown
# Cursor governance-lifecycle runtime evidence

**Run date (UTC):** YYYY-MM-DD HH:MM
**Cursor version:** (from Cursor → About)
**Stack endpoint:** http://localhost:8080
**Operator:** (your name + email)

## Prompt

<paste the prompt you sent>

## Tool calls (Cursor's annotations)

```
Ran List Overrides    in axonflow
Ran Create Override   in axonflow
Ran List Overrides    in axonflow
Ran Delete Override   in axonflow
Ran List Overrides    in axonflow
```

## Tool results (Cursor's annotations)

<paste the raw tool results>

## Agent reply

SMOKE_RESULT: { ... }

## Pass/fail

- [ ] Cursor invoked list_overrides (three times), create_override and
      delete_override through its MCP runtime
- [ ] Override count went UP after create and back DOWN after revoke
- [ ] Tool results returned without is_error: true (or returned a
      structured negative for fabricated/non-applicable inputs)
- [ ] Agent emitted the SMOKE_RESULT marker
```

7. **Commit `EVIDENCE.md`** in the same PR that bumps the plugin
   version. The `test.sh` gate checks both presence and freshness;
   without recent EVIDENCE.md the release-prep gate fails.
