#!/usr/bin/env bash
# Plugin smoke E2E: install-and-use sanity check against a live AxonFlow
# stack. Feeds a destructive Shell tool invocation (the preToolUse shape
# Cursor documents: tool_name "Shell", tool_input.command) into
# pre-tool-check.sh and asserts the hook exits 2 with the policy violation
# and the decision id on stderr, and Cursor's documented deny JSON on stdout.
#
# The seed is `rm -rf / --no-preserve-root`, which AxonFlow v11.0.0 blocks
# (sys__dangerous__destructive__fs). The SQL injection string this smoke used
# to seed is ALLOWED by v11.0.0 everywhere but /api/request, and v11.0.0 sends
# no risk level, so the old `risk:` marker could never appear.
#
# Scope: smoke-only — install wiring + one local deny UX.
#
# Usage:
#   AXONFLOW_ENDPOINT=http://localhost:8080 \
#   AXONFLOW_CLIENT_ID=demo-client \
#   AXONFLOW_CLIENT_SECRET=demo-secret \
#     bash tests/e2e/smoke-block-context.sh
#
# CI trigger: workflow_dispatch only (GitHub-hosted runners have no
# local stack; PR gating needs a self-hosted runner).
# -uo pipefail (no -e) so the errors=$((errors+1)) accumulator + FAIL
# diagnostics always print.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_SCRIPT="$REPO_ROOT/scripts/pre-tool-check.sh"

: "${AXONFLOW_ENDPOINT:=http://localhost:8080}"
: "${AXONFLOW_CLIENT_ID:=demo-client}"
: "${AXONFLOW_CLIENT_SECRET:=demo-secret}"

export AXONFLOW_ENDPOINT
export AXONFLOW_AUTH="$(printf '%s:%s' "$AXONFLOW_CLIENT_ID" "$AXONFLOW_CLIENT_SECRET" | base64)"

if ! curl -sSf -o /dev/null --max-time 5 "$AXONFLOW_ENDPOINT/health"; then
  echo "SKIP: AxonFlow stack not reachable at $AXONFLOW_ENDPOINT/health"
  echo "      Start one via axonflow-enterprise scripts/setup-e2e-testing.sh"
  exit 0
fi

INPUT='{"hook_event_name":"preToolUse","tool_name":"Shell","tool_input":{"command":"rm -rf / --no-preserve-root","working_directory":"/home/user/project"},"tool_use_id":"smoke-1","cwd":"/home/user/project"}'

OUT_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT
printf '%s' "$INPUT" | bash "$HOOK_SCRIPT" >"$OUT_FILE" 2>"$ERR_FILE"
EXIT_CODE=$?
STDERR_OUT=$(cat "$ERR_FILE")
echo "--- exit code: $EXIT_CODE ---"
echo "--- stderr ---"
echo "$STDERR_OUT"
echo "--- stdout ---"
cat "$OUT_FILE"
echo "---"

errors=0
if [ "$EXIT_CODE" != "2" ]; then
  echo "FAIL: expected exit 2 (Cursor deny semantics), got $EXIT_CODE"
  errors=$((errors + 1))
fi
if ! grep -q "AxonFlow policy violation" <<<"$STDERR_OUT"; then
  echo "FAIL: stderr missing 'AxonFlow policy violation' prefix"
  errors=$((errors + 1))
fi
if ! grep -qE "decision: [0-9a-f-]{36}" <<<"$STDERR_OUT"; then
  echo "FAIL: stderr missing 'decision: <id>' marker (Plugin Batch 1 richer context)"
  errors=$((errors + 1))
fi
if [ "$(jq -r '.permission // empty' "$OUT_FILE" 2>/dev/null)" != "deny" ]; then
  echo "FAIL: stdout is not Cursor's deny JSON ({\"permission\":\"deny\", ...})"
  errors=$((errors + 1))
fi

if [ $errors -gt 0 ]; then
  echo "FAIL: smoke scenario failed with $errors error(s)"
  exit 1
fi
echo "PASS: smoke — Cursor hook denies a destructive Shell command with exit 2, the decision id and the deny JSON"
