# Manual runbook — Cursor IDE 5-tool drive

Used for one-time GUI-side verification when releasing a new
cursor-plugin version that touches the V1 Pro MCP tool surface.
Captured screenshots land under
`EVIDENCE/<utc-ts>/cursor-ide-companion-drive/`. The
automated wire-level test (`test.sh`) is the canonical CI gate; this
runbook is the operator companion that proves Cursor IDE's chat agent
actually surfaces and dispatches the 5 tools.

## Pre-flight (5 minutes)

1. **Get tenant credentials.** Either reuse existing
   (`~/.config/axonflow/try-registration.json`) or register fresh:
   ```bash
   curl -sS -X POST https://try.getaxonflow.com/api/v1/register \
     -H 'Content-Type: application/json' \
     -d '{"label":"cursor-runtime","email":"e2e+cursor@getaxonflow.com"}'
   ```
   Save `tenant_id` + `secret`.

2. **Patch Cursor's installed plugin `mcp.json`** to point at prod
   with real auth:
   ```bash
   AUTH="Basic $(printf '%s:%s' "$TENANT" "$SECRET" | base64 | tr -d '\n')"
   cat > ~/.cursor/plugins/local/axonflow-cursor-plugin/mcp.json <<JSON
   {
     "mcpServers": {
       "axonflow": {
         "type": "http",
         "url": "https://try.getaxonflow.com/api/v1/mcp-server",
         "headers": {
           "Authorization": "$AUTH",
           "X-Axonflow-Client": "cursor-plugin/1.3.0"
         }
       }
     }
   }
   JSON
   ```

3. **Quit Cursor** so it picks up the patched config on relaunch:
   ```bash
   osascript -e 'tell application "Cursor" to quit'
   ```

4. **Move any stale Pro-tier license token aside.** A token with a
   different tenant_id from the current Basic-auth tenant will be
   rejected by the agent's PluginClaimMiddleware:
   ```bash
   mv ~/.config/axonflow/license-token.json /tmp/license-token-bak.json 2>/dev/null
   ```

## Drive (5 minutes)

5. **Launch Cursor pointed at the plugin workspace:**
   ```bash
   /Applications/Cursor.app/Contents/Resources/app/bin/cursor \
     /Users/<you>/Development/axonflow-cursor-plugin
   ```

6. **Open chat panel** (⌘L) and start a new conversation (⌘N).

7. **Pre-allowlist the 5 tools** — IMPORTANT, otherwise Cursor
   prompts per-tool and the run becomes "click 5 dialogs":
   - In the chat input, click the ⚙️ icon, choose
     **Auto-run for this conversation**, and tick all 5 axonflow
     tools (`axonflow_list_pro_features`,
     `axonflow_get_cost_estimate`, `axonflow_request_approval`,
     `axonflow_create_tenant_policy`, `axonflow_get_tenant_id`).
   - Confirm the allowlist by sending one trivial probe (e.g. ask
     for `axonflow_list_pro_features`) and observe NO approval
     dialog appears.

8. **Send the 5-tool prompt:**
   ```
   Use the AxonFlow MCP server (axonflow) to call EXACTLY these 5 tools, one at a time. Do not call any other tools, do not run any bash commands. After each tool call, print one line "TOOL_OK <name>" or "TOOL_FAIL <name>".

   1. axonflow_list_pro_features with arguments {}
   2. axonflow_get_cost_estimate with arguments {"plan":"runtime-e2e probe"}
   3. axonflow_request_approval with arguments {"original_query":"runtime-e2e probe","request_type":"shell_command","trigger_reason":"runtime_e2e_test","severity":"low"}
   4. axonflow_create_tenant_policy with arguments {"name":"runtime-e2e-cursor","description":"runtime-e2e probe","connector_type":"cursor.Bash","pattern":"axonflow-runtime-e2e-marker","action":"warn"}
   5. axonflow_get_tenant_id with arguments {}

   End your final message with the exact line: SMOKE_RESULT_DONE
   ```

9. **Wait for completion** (~2-3 min for all 5 tools).

10. **Screenshot the chat panel** showing all 5 "Ran AxonFlow X in
    axonflow" rows:
    ```bash
    screencapture -x cursor-ide-5tools-evidence.png
    ```

## Post-flight (2 minutes)

11. **Restore Cursor's mcp.json** + license-token.json:
    ```bash
    # restore from .runtime-e2e-bak.* files you backed up earlier, or
    # delete the patched copy and let the plugin re-bootstrap.
    ```

12. **Commit screenshots to EVIDENCE/<utc-ts>/cursor-ide-companion-drive/**.

## What the screenshots prove

The chat panel must show 5 "Ran AxonFlow X in axonflow" rows — one
per tool. Each row is the host CLI's record that Cursor's chat agent
actually invoked that MCP tool. The `TOOL_OK` / `TOOL_FAIL` lines
that follow are the **model's** judgment of the response body, not
the wire success/failure:

- `TOOL_OK axonflow_list_pro_features` — model saw a structured
  feature list, judged success.
- `TOOL_FAIL axonflow_get_cost_estimate` — model saw `isError:true`
  on the V1 paywall envelope, judged failure. **Expected** —
  matches the locked Pro-only contract.
- `TOOL_FAIL axonflow_request_approval` (sometimes) — model can
  judge `status:pending` as failure even though the tool itself
  succeeded with a non-empty `approval_id`. The wire-level test in
  `test.sh` asserts on the wire shape directly to disambiguate.
- `TOOL_FAIL axonflow_create_tenant_policy` (sometimes) — model can
  misread the success body. Same disambiguation by `test.sh`.
- `TOOL_OK axonflow_get_tenant_id` — model sees its own tenant_id
  echoed back, judges success.

The key claim this runbook proves is **dispatch** — Cursor IDE's
chat agent saw all 5 tools in its tool palette, picked them by name,
and the host CLI emitted the dispatch markers. The semantic claim
("the response body matches the V1 contract") belongs to `test.sh`
which calls each tool directly and asserts on the wire response.
