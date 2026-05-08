#!/usr/bin/env bash
# Cursor runtime-e2e: list-recent-decisions (V1.1, #1982).
#
# Cursor's CLI is window-management-only — there is no headless agent
# mode. So Cursor "runtime tests" are a manual runbook + this gate that
# refuses to pass unless someone actually ran the runbook and checked
# in EVIDENCE.md alongside it. The gate uses the same shared cursor_gate
# helper as the other features (explain-decision, audit-search, etc.).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../_lib/cursor-gate.sh
source "$SCRIPT_DIR/../_lib/cursor-gate.sh"
cursor_gate "$SCRIPT_DIR" "list_recent_decisions"
