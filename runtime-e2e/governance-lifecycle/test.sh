#!/usr/bin/env bash
# Cursor runtime E2E gate: governance-lifecycle (W2 — rule #1)
#
# See ../_lib/cursor-gate.sh for the gate logic and runtime-e2e/audit-search/
# for the canonical Cursor-product-limitation explanation. The gate
# delegates to the shared lib; per-feature MANUAL_RUNBOOK.md + EVIDENCE.md
# in this folder carry the human-driven runtime-path proof.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../_lib/cursor-gate.sh
source "$SCRIPT_DIR/../_lib/cursor-gate.sh"
# The lifecycle this directory covers is create -> list -> revoke, and that
# is what MANUAL_RUNBOOK.md drives and EVIDENCE.md records (list_overrides
# three times, create_override, delete_override). The gate previously named
# search_audit_events (#87), so it stayed green if any override tool stopped
# being advertised: exactly the wiring regression it exists to catch.
cursor_gate "$SCRIPT_DIR" "create_override" "list_overrides" "delete_override"
