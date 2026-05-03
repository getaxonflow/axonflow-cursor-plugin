#!/usr/bin/env bash
# Cursor runtime E2E gate: explain-decision (W2 — rule #1)
#
# See ../_lib/cursor-gate.sh for the gate logic and runtime-e2e/audit-search/
# for the canonical Cursor-product-limitation explanation. The gate
# delegates to the shared lib; per-feature MANUAL_RUNBOOK.md + EVIDENCE.md
# in this folder carry the human-driven runtime-path proof.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../_lib/cursor-gate.sh
source "$SCRIPT_DIR/../_lib/cursor-gate.sh"
cursor_gate "$SCRIPT_DIR" "explain_decision"
