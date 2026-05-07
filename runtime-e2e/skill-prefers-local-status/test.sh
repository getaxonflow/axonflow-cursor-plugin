#!/usr/bin/env bash
# Cursor runtime E2E gate: axonflow-status skill prefers local script
#
# Cursor's chat agent runs only inside the IDE — cursor-agent CLI does
# NOT load IDE plugins per feedback_cursor_agent_cli_is_not_cursor_ide.md.
# This script enforces the same release-prep gate the sister W2 tests
# in this repo use (see runtime-e2e/_lib/cursor-gate.sh):
#   - Cursor IDE present
#   - AxonFlow stack reachable
#   - MCP server advertises axonflow_get_tenant_id (the documented
#     fallback path the SKILL still references)
#   - Plugin's mcp.json well-formed
#   - MANUAL_RUNBOOK.md present
#   - EVIDENCE.md present + ≤ 60 days old
#
# Plus a content-level guard specific to this skill flip:
#   - skills/axonflow-status/SKILL.md step 1 references the local
#     scripts/status.sh path before any MCP tool reference (delegated
#     to tests/test-skill-status-prefers-local.sh which runs always-on
#     in CI; this gate just confirms the runbook + evidence pair is
#     fresh).
#
# When Cursor ships a structured agent-output mode (analogous to
# Claude's stream-json), replace the manual EVIDENCE pattern with
# automated assertion on the captured tool sequence.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../_lib/cursor-gate.sh
source "$SCRIPT_DIR/../_lib/cursor-gate.sh"
cursor_gate "$SCRIPT_DIR" "axonflow_get_tenant_id"
