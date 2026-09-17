# Manual runbook - Cursor `governance-lifecycle` runtime verification

Cursor's agent runs only inside the IDE. This runbook is the rule-#1
runtime verification for the governance-lifecycle feature. Run it once before tagging
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

4. **Send the prompt verbatim** (substitute today's date into the
   override_reason):

   > Run a 5-step governance smoke test using the axonflow MCP server. Step 1: call list_overrides with no arguments and note count. Step 2: call create_override with policy_id="sys_pii_email", policy_type="static", override_reason="cursor-lifecycle-YYYY-MM-DD". Step 3: call list_overrides again and note count. Step 4: call delete_override with override_id="runtime-e2e-fabricated-override-id-12345". Step 5: call search_audit_events with limit=5. Output exactly SMOKE_RESULT: followed by single-line JSON like SMOKE_RESULT: {"count_before":N,"count_after":N,"create_refused":true,"delete_frozen":true,"audit_answered":true}, where create_refused is true when step 2 answered LEGACY_POLICY_WRITE_FROZEN or the per-user identity refusal.

5. **Wait for the agent to invoke the tools.** Cursor surfaces tool
   calls inline in the chat with "Ran List Overrides in axonflow" style
   annotations; expect five of them (list, create, list, delete, search).

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

- [ ] Cursor invoked list_overrides (twice), create_override, delete_override
      and search_audit_events through its MCP runtime
- [ ] create_override answered `LEGACY_POLICY_WRITE_FROZEN: ` or the per-user
      identity refusal; delete_override answered `LEGACY_POLICY_WRITE_FROZEN: `
- [ ] The override count did NOT move (count_before == count_after)
- [ ] search_audit_events answered without is_error: true
- [ ] Agent emitted the SMOKE_RESULT marker
```

7. **Commit `EVIDENCE.md`** in the same PR that bumps the plugin
   version. The `test.sh` gate checks both presence and freshness;
   without recent EVIDENCE.md the release-prep gate fails.
