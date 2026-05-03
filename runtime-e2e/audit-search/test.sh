#!/usr/bin/env bash
# Cursor runtime E2E gate: audit-search (W2 — rule #1)
#
# Cursor product limitation: the `cursor` CLI is window-management only —
# no `cursor exec "prompt"` equivalent of `claude -p` / `codex exec` /
# `openclaw agent --local --message`. So Cursor's agent surface cannot
# be fully automated today.
#
# This script enforces a release-prep gate at runtime-e2e time:
# Cursor IDE present, live stack reachable, MCP server advertises the
# tool the runbook exercises, plugin's mcp.json well-formed, AND
# EVIDENCE.md from the last manual run exists + is no more than 60
# days old. The gate refuses to pass without recent evidence — that's
# the rule-#1-in-action behavior.
#
# When Cursor ships a headless agent mode, replace the per-feature
# test.sh files in this directory with the automated equivalent of the
# Claude/Codex/OpenClaw runtime tests in the sibling plugins.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../_lib/cursor-gate.sh
source "$SCRIPT_DIR/../_lib/cursor-gate.sh"
cursor_gate "$SCRIPT_DIR" "search_audit_events"
