# Manual runbook — Cursor `list-recent-decisions` runtime verification

V1.1 (axonflow-enterprise#1982). Cursor's agent runs only inside the IDE. This runbook is the rule-#0 runtime verification for `list_recent_decisions`. Run it once before tagging each release; capture the output into `EVIDENCE.md` in this folder.

The accompanying `test.sh` enforces the gate: it refuses to pass if `EVIDENCE.md` is missing or is more than 60 days old. That keeps the manual verification from rotting silently.

## Prereqs

- AxonFlow stack reachable at `http://localhost:8080` (or set the URL you'll point Cursor's MCP at).
- The stack is running platform code that includes the V1.1 `list_recent_decisions` MCP tool registration (axonflow-enterprise#1985 or its successor).
- Cursor IDE (any 3.x).
- This plugin's `mcp.json` already configured at the project root or in Cursor's MCP servers settings.

## Steps

1. **Open Cursor in the plugin repo:**

   ```bash
   /Applications/Cursor.app/Contents/Resources/app/bin/cursor /Users/saurabhjain/Development/axonflow-cursor-plugin
   ```

2. **Verify the MCP server is connected.** In Cursor settings → MCP, the `axonflow` server should show as connected (green dot) and `list_recent_decisions` should appear in the tool list.

3. **Open a chat panel in Composer / Agent mode** (the agent surface).

4. **Send the prompt verbatim — happy path:**

   > Use the `list_recent_decisions` MCP tool from the axonflow MCP server with arguments: `{"limit": 3}`. Output exactly `SMOKE_RESULT: ` followed by a one-line JSON: `SMOKE_RESULT: {"shape":"decisions","count": N}` if the tool returned a `decisions` array, OR `SMOKE_RESULT: {"shape":"upgrade","tier":"...","limit":N,"buy_url":"..."}` if the tool returned the upgrade envelope.

5. **Send a second prompt — over-cap envelope:**

   > Use the `list_recent_decisions` MCP tool with `{"limit": 10}`. The Community tier max page is 5; this should return the V1 upgrade envelope. Confirm the response includes `upgrade_required: true` and the `upgrade.buy_url`. Output exactly `SMOKE_RESULT: {"envelope_present":true,"limit_type":"decision_list_size","buy_url":"<the buy URL>"}` to confirm.

6. **Capture both runs into `EVIDENCE.md`** using the template below.

## EVIDENCE.md template

```markdown
# Cursor list-recent-decisions runtime evidence

**Run date (UTC):** YYYY-MM-DD HH:MM
**Cursor version:** (from Cursor → About)
**Stack endpoint:** http://localhost:8080
**Operator:** (your name + email)

## Happy path

### Prompt
<paste the limit:3 prompt>

### Cursor's annotations
```
Tool: list_recent_decisions
Arguments: {"limit": 3}
```

### Tool result (paste raw)
<...>

### Agent reply
SMOKE_RESULT: {"shape":"decisions","count":N}

## Over-cap (V1 envelope passthrough)

### Prompt
<paste the limit:10 prompt>

### Cursor's annotations
```
Tool: list_recent_decisions
Arguments: {"limit": 10}
```

### Tool result (paste raw — must show upgrade_required + envelope)
<...>

### Agent reply
SMOKE_RESULT: {"envelope_present":true,"limit_type":"decision_list_size","buy_url":"https://buy.stripe.com/..."}

## Pass/fail

- [ ] Cursor invoked `list_recent_decisions` through its MCP runtime in both runs
- [ ] Happy-path tool result was a `decisions` array (possibly empty)
- [ ] Over-cap tool result carried `upgrade_required: true` + `envelope.upgrade.buy_url`
- [ ] Agent emitted SMOKE_RESULT markers for both runs
```

7. **Commit `EVIDENCE.md`** in the same PR that bumps the plugin version. The `test.sh` gate checks both presence and freshness; without recent EVIDENCE.md the release-prep gate fails.
