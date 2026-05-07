# Cursor skill-prefers-local-status runtime evidence — 2026-05-07T11:00:51Z

**Cursor version:** 3.2.21 (arm64, build 806df57e)
**Stack endpoint:** `https://try.getaxonflow.com`
**Operator:** automated AppleScript drive (Cursor 3.2.21 free-tier session)
**Tenant:** `cs_8d25ee3e-4d63-4348-98a6-56006dc11c9b` (registered fresh for this run; on-disk via `~/.config/axonflow/try-registration.json`)

## What this proves

The `axonflow-status` SKILL.md flip in
[axonflow-cursor-plugin#55](https://github.com/getaxonflow/axonflow-cursor-plugin/pull/55)
preferences the local `scripts/status.sh` path over the agent-side MCP
tool `axonflow_get_tenant_id` for tenant_id / tier queries. This run
proves the wording change actually changes downstream Cursor IDE
behaviour — the agent reads the skill, follows step 1, and invokes
the local script via Bash without calling the MCP tool.

## Driver pattern

`AppleScript via osascript` from the parent shell — same approach
documented in `runtime-e2e/AUTOMATION_ATTEMPT.md`. macOS Accessibility
+ Screen Recording permissions on Terminal grant the keystroke +
screencapture path.

```bash
# 1. Launch Cursor pointed at the plugin workspace, with
#    AXONFLOW_ENDPOINT + AXONFLOW_AUTH carrying working tenant creds.
AXONFLOW_ENDPOINT=https://try.getaxonflow.com \
  AXONFLOW_AUTH=$(printf '%s:%s' "$TENANT" "$SECRET" | base64) \
  /Applications/Cursor.app/Contents/Resources/app/bin/cursor "$WORKSPACE" &
sleep 12

# 2. Activate + open chat panel (Cmd+L), type prompt, submit (Enter).
osascript -e 'tell application "Cursor" to activate'
osascript -e 'tell application "System Events" to tell process "Cursor" to keystroke "l" using command down'
sleep 2
osascript -e 'tell application "System Events" to tell process "Cursor" to keystroke "<PROMPT>"'
osascript -e 'tell application "System Events" to tell process "Cursor" to key code 36'

# 3. Wait for agent + capture screenshot of chat panel.
sleep 90
screencapture -x -R 1450,30,1100,1300 cursor-evidence.png
```

## Prompt sent to Cursor

> Use the axonflow-status skill from this plugin to find my AxonFlow tenant ID. Follow exactly the steps in the skill — do not deviate. Print SMOKE_RESULT followed by the tool you invoked and a one-line summary.

## Cursor's annotations (verbatim from `cursor-evidence-skill-flip-PASS.png`)

```
Reading skill file  3s

Got it. I'm going to read the axonflow-status skill instructions and
then follow them exactly to retrieve your AxonFlow tenant ID, ending
with the requested SMOKE_RESULT line.

Used axonflow-status

I'll run scripts/status.sh in your terminal to print your tenant_id
and tier.

Ran Run AxonFlow plugin status script  bash

  • tenant_id: cs_8d25ee3e-4d63-4348-98a6-56006dc11c9b
  • tier:      Free (no Pro license configured)

SMOKE_RESULT  bash scripts/status.sh  Printed AxonFlow endpoint,
tenant_id, and tier (Free).
```

## Pass / fail — outcome verified

- [x] Cursor IDE loaded the plugin's `axonflow-status` skill ("Reading
      skill file 3s", "Used axonflow-status" annotations).
- [x] Cursor's first invoked tool was `bash` running
      `scripts/status.sh` — the LOCAL script path preferred by the
      flipped skill, NOT the MCP tool `axonflow_get_tenant_id`.
- [x] The local script returned `tenant_id` +
      `tier=Free (no Pro license configured)` — matching the locked
      tier-line shape from the SKILL.md "Tier line shape" section.
- [x] Agent self-reported `SMOKE_RESULT bash scripts/status.sh ...`
      — confirming the local script path was used, not the MCP tool.
- [x] No agent round-trip through `mcp__axonflow__axonflow_get_tenant_id`
      occurred at any point in the run (chat shows `bash` as the only
      tool invocation).

## Cross-references

- SKILL change: [axonflow-cursor-plugin#55](https://github.com/getaxonflow/axonflow-cursor-plugin/pull/55)
- Sister claude-plugin runtime-e2e (parallel proof on the
  programmatic-CLI side): [`runtime-e2e/skill-prefers-local-status/`](https://github.com/getaxonflow/axonflow-claude-plugin/tree/main/runtime-e2e/skill-prefers-local-status)
- AppleScript automation pattern: `runtime-e2e/AUTOMATION_ATTEMPT.md`
- Doctrine: `feedback_runtime_proof_is_definition_of_done.md` —
  HARD RULE #0 ("real plugin in real host CLI") — Cursor IDE 3.2.21
  is the real host CLI here, not cursor-agent CLI (which doesn't load
  IDE plugins per `feedback_cursor_agent_cli_is_not_cursor_ide.md`).
