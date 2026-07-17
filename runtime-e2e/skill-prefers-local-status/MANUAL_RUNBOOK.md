# Manual runbook — Cursor `axonflow-status` skill-flip runtime verification

Cursor's chat agent runs only inside the IDE (cursor-agent CLI does
NOT load IDE plugins per
`feedback_cursor_agent_cli_is_not_cursor_ide.md`). This runbook is
the rule-#1 runtime verification for the `axonflow-status` SKILL flip
that prefers the local script over the MCP tool. Run it once before
tagging each release; capture the output into `EVIDENCE.md` in this
folder.

The accompanying `test.sh` enforces the gate: it refuses to pass if
`EVIDENCE.md` is missing or is more than 60 days old, AND it
verifies the skill content + plugin manifest are well-formed before
asking a human to run the manual test.

## What this verifies

The flipped SKILL.md tells the AI to **prefer `scripts/status.sh`
(local resolve, no agent round-trip) over `axonflow_get_tenant_id`
(MCP tool, agent round-trip)**. This runbook proves the wording flip
actually changes downstream Cursor IDE behaviour — that the AI reads
the skill, follows step 1 verbatim, and invokes the local script via
Bash without calling the MCP tool.

## Prereqs

- AxonFlow stack reachable at `https://try.getaxonflow.com`
  (or your own local stack — the test exercises the flip, not the
  agent's response).
- A working community-saas tenant on disk at
  `~/.config/axonflow/try-registration.json` so the plugin's
  pre-tool-check hook can authenticate. (Without this, the hook will
  block all tool calls including the Read of SKILL.md — see the
  earlier 2026-05-07 EVIDENCE-attempt commentary in this folder for
  a worked example of that failure mode.)
- Cursor IDE 3.x (verified on 3.2.21).
- This plugin's `mcp.json` already at the project root.

## Steps

1. **Verify the on-disk tenant authenticates.** Run:
   ```bash
   T=$(jq -r .tenant_id ~/.config/axonflow/try-registration.json)
   S=$(jq -r .secret ~/.config/axonflow/try-registration.json)
   curl -sS -o /dev/null -w 'HTTP=%{http_code}\n' \
     -X POST https://try.getaxonflow.com/api/v1/audit/tool-call \
     -u "$T:$S" -H 'Content-Type: application/json' \
     -d '{"tool_name":"probe","caller_name":"x","input":{},"success":true}'
   ```
   Expect `HTTP=200` or `HTTP=201`. If `HTTP=401`, register a fresh
   tenant via `POST /api/v1/register` and overwrite the on-disk
   registration.

2. **Launch Cursor with explicit AxonFlow auth env vars** so the
   plugin's hooks pick them up:
   ```bash
   AUTH=$(printf '%s:%s' "$T" "$S" | base64 | tr -d '\n')
   AXONFLOW_ENDPOINT=https://try.getaxonflow.com \
   AXONFLOW_AUTH="$AUTH" \
   /Applications/Cursor.app/Contents/Resources/app/bin/cursor \
     /Users/saurabhjain/Development/axonflow-cursor-plugin
   ```

3. **Verify the MCP server is connected.** In Cursor settings → MCP,
   the `axonflow` server should show as connected (green dot).

4. **Open a chat panel in Composer / Agent mode** (Cmd+L from a
   closed state opens it; the chat input should be focused). Start a
   new chat (the `+` button or Cmd+N inside the panel).

5. **Send the prompt verbatim:**
   ```
   Use the axonflow-status skill from this plugin to find my AxonFlow
   tenant ID. Follow exactly the steps in the skill — do not deviate.
   Print SMOKE_RESULT followed by the tool you invoked and a one-line
   summary.
   ```

6. **Wait for the agent to read the skill + invoke the tool.** Cursor
   surfaces tool calls inline in the chat with annotations like
   `Reading skill file 3s`, `Used axonflow-status`, and
   `Ran ... bash` for terminal commands.

7. **Verify the agent's response.** REQUIRED checks:
   - Cursor reads the skill file (`Reading skill file Ns` annotation
     OR `Used axonflow-status` annotation present).
   - The FIRST non-skill-read tool the agent invokes is `bash`
     running `scripts/status.sh` (NOT
     `mcp__axonflow__axonflow_get_tenant_id`).
   - The agent surfaces the `tenant_id` and `tier` lines from the
     script's stdout.
   - The agent prints a `SMOKE_RESULT bash scripts/status.sh ...`
     line confirming the local script was used.

8. **Capture the run into `EVIDENCE.md`** following the template in
   the existing capture:
   ```markdown
   # Cursor skill-prefers-local-status runtime evidence

   **Cursor version:** 3.x.x
   **Stack endpoint:** ...
   **Operator:** ...
   **Tenant:** ...

   ## Prompt sent to Cursor
   > [verbatim prompt]

   ## Cursor's annotations
   ```
   [verbatim chat output: Reading skill file Ns, Used axonflow-status,
    Ran ... bash, tenant_id + tier output, SMOKE_RESULT line]
   ```

   ## Pass / fail — outcome verified
   - [x] Cursor IDE loaded the plugin's axonflow-status skill
   - [x] First invoked tool was bash with scripts/status.sh — NOT MCP tool
   - [x] Local script returned tenant_id + tier
   - [x] No agent round-trip through axonflow_get_tenant_id
   ```

   Take a screenshot of the chat panel and save it as
   `cursor-evidence-skill-flip-PASS.png` in the EVIDENCE folder.

## Automation note

The 2026-05-07 capture under `EVIDENCE/20260507T110051Z/` was driven
end-to-end by `osascript` keystroke + `screencapture` from a parent
shell with macOS Accessibility + Screen Recording permissions
granted. That pattern works on Cursor 3.x — use it for repeat runs
to keep the EVIDENCE.md freshness window from rotting.
