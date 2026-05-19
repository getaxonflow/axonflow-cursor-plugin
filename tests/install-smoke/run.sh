#!/usr/bin/env bash
# Install-to-use smoke gate harness.
#
# Stages the plugin to a clean tmp dir (mirroring what `claude plugin
# install` would copy), validates the file list and hooks.json paths
# resolve, spawns a stub MCP server on a random port, and exercises the
# pre-tool-check.sh hook against it for both deny (SQLi) and allow
# (benign) paths. Asserts:
#
#   - Required files present in the staged install
#   - hooks.json hooks point to scripts that exist post-install
#   - Wire-shape Plugin Batch 1 fields surface in the deny output
#     (decision_id / risk_level / override_available)
#   - Allow path returns silent (no output)
#
# Catches the class of regressions the existing test-hooks.sh misses
# because it runs against the source tree:
#   - hooks.json paths broken after install (wrong relative path)
#   - Required files missing from the install payload
#   - Scripts referencing files relative to source tree that don't
#     exist in the installed location
#
# No external network or live AxonFlow stack required.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t install-smoke)
LOG_DIR="${STAGE_DIR}/.logs"
mkdir -p "$LOG_DIR"

cleanup() {
  if [ -n "${STUB_PID:-}" ]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }

# 1. Stage the plugin's install payload.
echo "stage to $STAGE_DIR"
mkdir -p "$STAGE_DIR/.cursor-plugin" "$STAGE_DIR/hooks" "$STAGE_DIR/scripts"
cp -p "$PLUGIN_DIR/.cursor-plugin/plugin.json" "$STAGE_DIR/.cursor-plugin/" \
  || fail "missing .cursor-plugin/plugin.json"
cp -p "$PLUGIN_DIR/mcp.json" "$STAGE_DIR/" \
  || fail "missing mcp.json"
cp -p "$PLUGIN_DIR/hooks/hooks.json" "$STAGE_DIR/hooks/" \
  || fail "missing hooks/hooks.json"
cp -p "$PLUGIN_DIR/scripts/"*.sh "$STAGE_DIR/scripts/" \
  || fail "missing scripts/*.sh"
chmod +x "$STAGE_DIR/scripts/"*.sh

# 2. Validate file list.
for f in .cursor-plugin/plugin.json mcp.json hooks/hooks.json \
         scripts/pre-tool-check.sh scripts/post-tool-audit.sh \
         scripts/telemetry-ping.sh scripts/mcp-auth-headers.sh \
         scripts/recover-credentials.sh scripts/status.sh; do
  if [ -f "$STAGE_DIR/$f" ]; then pass "staged $f"
  else fail "missing $f after stage"
  fi
done

# 2b. Status-script smoke. Drives status.sh against an isolated $HOME so it
# never touches the developer's real ~/.config/axonflow. Asserts:
#   - tenant_id from try-registration.json renders into output
#   - "tier Free (no Pro license configured)" when no AXONFLOW_LICENSE_TOKEN
#     env is set
#   - "tier Pro (expires YYYY-MM-DD, N days remaining)" when a Pro-active
#     token is set (V1 SaaS Plugin Pro tier-expiry surface parity)
#   - "tier Free (Pro expired YYYY-MM-DD — visit ... to renew)" when the
#     token is on disk but its `exp` is in the past
#   - the FULL token never appears in stdout (the codex#41 regression)
#   - recovery hint surfaces when the registration file is missing
STATUS_HOME=$(mktemp -d 2>/dev/null || mktemp -d -t status-home)
mkdir -p "$STATUS_HOME/.config/axonflow"
chmod 0700 "$STATUS_HOME/.config/axonflow"
cat > "$STATUS_HOME/.config/axonflow/try-registration.json" <<'EOJ'
{"tenant_id":"cs_smoke-tenant-xyz","secret":"REDACTED","endpoint":"https://try.getaxonflow.com","email":"smoke@example.com"}
EOJ
chmod 0600 "$STATUS_HOME/.config/axonflow/try-registration.json"

# Helper: mint a structurally-valid AXON- token whose JWT payload contains
# a given exp (unix epoch). Signature is a placeholder — status.sh only
# parses, never validates. base64url with padding stripped, per RFC 7515.
mint_axon_jwt() {
  local exp_epoch="$1"
  local hdr
  hdr=$(printf '%s' '{"alg":"EdDSA","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
  local payload
  payload=$(printf '{"sub":"smoke","exp":%s}' "$exp_epoch" | base64 | tr '+/' '-_' | tr -d '=')
  # Pad signature so the whole token is comfortably long; status doesn't
  # gate on length but readers expect ~real-token shape.
  local sig="placeholder-signature-padding-padding-padding-padding-padding-pa"
  printf 'AXON-%s.%s.%s' "$hdr" "$payload" "$sig"
}

# Free-tier path: no env token, expect "Free (no Pro license configured)"
# + client_id surfaced (v1.5.0: label is client_id, on-disk JSON key
# stays tenant_id for file-format compat — see CHANGELOG v1.5.0).
FREE_OUT=$(HOME="$STATUS_HOME" AXONFLOW_TELEMETRY=off bash "$STAGE_DIR/scripts/status.sh" 2>&1)
if echo "$FREE_OUT" | grep -q "client_id:[[:space:]]*cs_smoke-tenant-xyz"; then
  pass "status.sh surfaces client_id from try-registration.json"
else
  fail "status.sh missing client_id; output: $FREE_OUT"
fi
if echo "$FREE_OUT" | grep -qE "tier[[:space:]]+Free \(no Pro license configured\)"; then
  pass "status.sh Free-tier line shape (no Pro license configured)"
else
  fail "status.sh did not report Free tier; output: $FREE_OUT"
fi

# Pro-tier ACTIVE path: mint a token with exp ~30 days in the future.
# Expect "tier Pro (expires YYYY-MM-DD, N days remaining)" + redacted last-4.
PRO_EXP=$(( $(date -u +%s) + 30 * 86400 ))
PRO_TOKEN=$(mint_axon_jwt "$PRO_EXP")
PRO_OUT=$(HOME="$STATUS_HOME" AXONFLOW_TELEMETRY=off \
  AXONFLOW_LICENSE_TOKEN="$PRO_TOKEN" \
  bash "$STAGE_DIR/scripts/status.sh" 2>&1)
if echo "$PRO_OUT" | grep -qE "tier[[:space:]]+Pro \(expires [0-9]{4}-[0-9]{2}-[0-9]{2}, [0-9]+ days remaining\)"; then
  pass "status.sh Pro-active line shape (expires YYYY-MM-DD, N days remaining)"
else
  fail "status.sh did not report Pro-active line; output: $PRO_OUT"
fi
PRO_TAIL4="${PRO_TOKEN: -4}"
if echo "$PRO_OUT" | grep -qF "AXON-...${PRO_TAIL4}"; then
  pass "status.sh emits AXON-...XXXX redaction with last-4 chars"
else
  fail "status.sh missing last-4 redaction; output: $PRO_OUT"
fi
if echo "$PRO_OUT" | grep -qF "$PRO_TOKEN"; then
  fail "status.sh LEAKED full license token to stdout: $PRO_OUT"
else
  pass "status.sh does not leak full license token"
fi

# Pro-tier EXPIRED path: mint a token with exp ~365 days in the past.
# Expect "tier Free (Pro expired YYYY-MM-DD — visit ... to renew)".
EXPIRED_EXP=$(( $(date -u +%s) - 365 * 86400 ))
EXPIRED_TOKEN=$(mint_axon_jwt "$EXPIRED_EXP")
EXPIRED_OUT=$(HOME="$STATUS_HOME" AXONFLOW_TELEMETRY=off \
  AXONFLOW_LICENSE_TOKEN="$EXPIRED_TOKEN" \
  bash "$STAGE_DIR/scripts/status.sh" 2>&1)
if echo "$EXPIRED_OUT" | grep -qE "tier[[:space:]]+Free \(Pro expired [0-9]{4}-[0-9]{2}-[0-9]{2} — visit https?://[^ ]+ to renew\)"; then
  pass "status.sh Pro-expired line shape (Pro expired YYYY-MM-DD — visit ... to renew)"
else
  fail "status.sh did not report Pro-expired line; output: $EXPIRED_OUT"
fi
if echo "$EXPIRED_OUT" | grep -qF "$EXPIRED_TOKEN"; then
  fail "status.sh LEAKED expired token to stdout"
else
  pass "status.sh redacts expired token"
fi

# Missing-registration path: hint should reference the recovery script.
rm -f "$STATUS_HOME/.config/axonflow/try-registration.json"
NOREG_OUT=$(HOME="$STATUS_HOME" AXONFLOW_TELEMETRY=off bash "$STAGE_DIR/scripts/status.sh" 2>&1)
if echo "$NOREG_OUT" | grep -q "recover-credentials.sh"; then
  pass "status.sh surfaces recovery hint when registration file is missing"
else
  fail "status.sh missing recovery hint; output: $NOREG_OUT"
fi
rm -rf "$STATUS_HOME"

# 3. Validate hooks.json hook command paths resolve to staged scripts.
HOOKS_JSON="$STAGE_DIR/hooks/hooks.json"
if [ ! -f "$HOOKS_JSON" ]; then
  fail "hooks.json not present; bailing"; exit 1
fi
# Extract every command path referenced in hooks.json (heuristic:
# any "command" field referencing a *.sh script).
# Cursor uses relative `./scripts/...` paths in hooks.json; resolve relative
# to the stage root.
SCRIPTS_REFERENCED=$(jq -r '..|objects|select(.command)|.command' "$HOOKS_JSON" 2>/dev/null \
  | grep -oE '^\./[^ "]*\.sh' | sort -u || true)
for cmd in $SCRIPTS_REFERENCED; do
  rel=${cmd#'./'}
  if [ -f "$STAGE_DIR/$rel" ] && [ -x "$STAGE_DIR/$rel" ]; then
    pass "hooks.json -> $rel resolves and is executable"
  else
    fail "hooks.json references $rel which is missing or not executable in stage"
  fi
done

# 4. Spawn stub MCP server.
STUB_LOG="$LOG_DIR/stub.log"
python3 "$PLUGIN_DIR/tests/install-smoke/stub-server.py" 0 >"$STUB_LOG" 2>&1 &
STUB_PID=$!
# Wait up to 5s for the stub to print PORT=<n>. set -e doesn't play well
# with pipefail + grep returning 1 on no-match, so disable it briefly.
set +e
PORT=""
for _ in $(seq 1 50); do
  PORT=$(grep -oE 'PORT=[0-9]+' "$STUB_LOG" 2>/dev/null | head -1 | cut -d= -f2)
  if [ -n "$PORT" ]; then break; fi
  sleep 0.1
done
set -e
if [ -z "$PORT" ]; then fail "stub-server failed to start; log: $(cat "$STUB_LOG")"; exit 1; fi
pass "stub-server listening on 127.0.0.1:$PORT"

# 5. Run pre-tool-check.sh from STAGE_DIR (not source) against stub.
HOOK="$STAGE_DIR/scripts/pre-tool-check.sh"
ENDPOINT="http://127.0.0.1:$PORT"

# Cursor's deny convention: exit 2 + reason on stderr (NOT JSON on
# stdout like Claude Code). Allow: exit 0, no output.

# Deny case: SQLi statement.
DENY_INPUT='{"tool_name":"Bash","tool_input":{"command":"DROP TABLE users; --"}}'
set +e
DENY_STDERR=$(echo "$DENY_INPUT" | AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_TELEMETRY=off "$HOOK" 2>&1 1>/dev/null)
DENY_EXIT=$?
set -e
if [ "$DENY_EXIT" = "2" ]; then pass "deny path exits 2 (block)"
else fail "deny path exit=$DENY_EXIT (expected 2). stderr: $DENY_STDERR"
fi
if echo "$DENY_STDERR" | grep -q "policy violation"; then pass "deny path emits 'policy violation' on stderr"
else fail "deny path stderr missing 'policy violation': $DENY_STDERR"
fi
if echo "$DENY_STDERR" | grep -q "decision: dec_test_deny_001"; then pass "deny path stderr surfaces decision_id"
else fail "deny path stderr missing decision_id"
fi
if echo "$DENY_STDERR" | grep -q "risk: high"; then pass "deny path stderr surfaces risk_level"
else fail "deny path stderr missing risk_level"
fi
if echo "$DENY_STDERR" | grep -q "override available"; then pass "deny path stderr surfaces override_available"
else fail "deny path stderr missing override_available"
fi

# Allow case: benign statement.
ALLOW_INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
set +e
ALLOW_STDOUT=$(echo "$ALLOW_INPUT" | AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_TELEMETRY=off "$HOOK" 2>/dev/null)
ALLOW_EXIT=$?
set -e
if [ "$ALLOW_EXIT" = "0" ]; then pass "allow path exits 0"
else fail "allow path exit=$ALLOW_EXIT (expected 0)"
fi
if [ -z "$ALLOW_STDOUT" ]; then pass "allow path stdout empty"
else fail "allow path produced unexpected stdout: $ALLOW_STDOUT"
fi

# 6. Summary.
echo
echo "Pass: $PASS"
echo "Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
