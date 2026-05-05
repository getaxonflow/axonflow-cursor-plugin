#!/usr/bin/env bash
# Cursor runtime E2E: V1 SaaS Plugin Pro tier-line expiry surface.
#
# Drives the user-facing surface (`scripts/status.sh`, invoked by the
# /axonflow-status skill via the integrated terminal) against three
# realistic license-token states and asserts the actual stdout matches
# the documented tier-line shapes:
#
#   - Free        → "tier   Free (no Pro license configured)"
#   - Pro active  → "tier   Pro (expires YYYY-MM-DD, N days remaining)"
#   - Pro expired → "tier   Free (Pro expired YYYY-MM-DD — visit ... to renew)"
#
# Why this is real-surface runtime proof (HARD RULE #0):
#   - The script under test IS the script invoked from the user's
#     integrated terminal (or via the /axonflow-status skill that
#     guides the agent to bash it) — same file, same path, same
#     env-var resolution order.
#   - The license tokens are real AXON-prefixed JWTs (header.payload.
#     sig base64url-encoded per RFC 7519). The JWT-parsing branch in
#     status.sh does NOT distinguish a platform-minted token from a
#     test-minted one structurally — both decode the same way and
#     exit the same code path. The platform's signature validation is
#     a separate concern that lives in PluginClaimMiddleware on the
#     agent and is exercised by the wire-level mcp-session-headers
#     runtime-e2e test.
#   - No network mock, no fake stdout capture, no shimmed command. We
#     invoke the actual scripts/status.sh against an isolated $HOME
#     and assert the actual stdout grep-shape.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUS_SH="${PLUGIN_DIR}/scripts/status.sh"

if [ ! -f "$STATUS_SH" ]; then
  echo "FAIL: required file missing: $STATUS_SH"
  exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
  echo "SKIP: base64 not on PATH"
  exit 0
fi

PASS=0
FAIL=0
pass() { printf '  PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# Mint a structurally-valid AXON- token whose JWT payload contains a
# given `exp` (unix epoch seconds). Signature segment is a fixed
# placeholder string padded to a realistic length; status.sh extracts
# `exp` only, does NOT validate the signature.
mint_axon_jwt() {
  local exp_epoch="$1"
  local hdr
  hdr=$(printf '%s' '{"alg":"EdDSA","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
  local payload
  payload=$(printf '{"sub":"runtime-e2e","exp":%s}' "$exp_epoch" | base64 | tr '+/' '-_' | tr -d '=')
  local sig="placeholder-signature-padding-padding-padding-padding-padding-pa"
  printf 'AXON-%s.%s.%s' "$hdr" "$payload" "$sig"
}

TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

echo "=== runtime-e2e: V1 SaaS Plugin Pro tier-expiry surface ==="
echo "Plugin dir: $PLUGIN_DIR"
echo "Script:     $STATUS_SH"
echo ""

# Test 1: Free tier (no token).
echo "Test 1: Free tier — no Pro license configured"
FREE_OUT=$(AXONFLOW_TELEMETRY=off \
  HOME="$TMP_HOME" \
  AXONFLOW_CONFIG_DIR="$TMP_HOME/empty" \
  bash "$STATUS_SH" 2>&1 || true)
if echo "$FREE_OUT" | grep -qE "tier[[:space:]]+Free \(no Pro license configured\)"; then
  pass "Free tier-line shape (no Pro license configured)"
else
  fail "Free tier-line missing expected shape; got:"
  echo "$FREE_OUT" | sed 's/^/      /'
fi

# Test 2: Pro active.
echo ""
echo "Test 2: Pro tier active — exp in the future"
PRO_EXP=$(( $(date -u +%s) + 30 * 86400 ))
PRO_TOKEN=$(mint_axon_jwt "$PRO_EXP")
PRO_OUT=$(AXONFLOW_LICENSE_TOKEN="$PRO_TOKEN" \
  AXONFLOW_TELEMETRY=off \
  HOME="$TMP_HOME" \
  AXONFLOW_CONFIG_DIR="$TMP_HOME/empty" \
  bash "$STATUS_SH" 2>&1 || true)
if echo "$PRO_OUT" | grep -qE "tier[[:space:]]+Pro \(expires [0-9]{4}-[0-9]{2}-[0-9]{2}, [0-9]+ days remaining\)"; then
  pass "Pro-active tier-line shape (expires YYYY-MM-DD, N days remaining)"
else
  fail "Pro-active tier-line missing expected shape; got:"
  echo "$PRO_OUT" | sed 's/^/      /'
fi
if echo "$PRO_OUT" | grep -qF "$PRO_TOKEN"; then
  fail "Pro-active output leaked full token"
else
  pass "Pro-active output redacts full token"
fi
PRO_TAIL4="${PRO_TOKEN: -4}"
if echo "$PRO_OUT" | grep -qF "AXON-...${PRO_TAIL4}"; then
  pass "Pro-active output shows last-4 redacted preview (AXON-...${PRO_TAIL4})"
else
  fail "Pro-active output missing last-4 preview"
fi

# Test 3: Pro expired.
echo ""
echo "Test 3: Pro tier expired — exp in the past"
EXPIRED_EXP=$(( $(date -u +%s) - 365 * 86400 ))
EXPIRED_TOKEN=$(mint_axon_jwt "$EXPIRED_EXP")
EXPIRED_OUT=$(AXONFLOW_LICENSE_TOKEN="$EXPIRED_TOKEN" \
  AXONFLOW_TELEMETRY=off \
  HOME="$TMP_HOME" \
  AXONFLOW_CONFIG_DIR="$TMP_HOME/empty" \
  bash "$STATUS_SH" 2>&1 || true)
if echo "$EXPIRED_OUT" | grep -qE "tier[[:space:]]+Free \(Pro expired [0-9]{4}-[0-9]{2}-[0-9]{2} — visit https?://[^ ]+ to renew\)"; then
  pass "Pro-expired tier-line shape (Pro expired YYYY-MM-DD — visit ... to renew)"
else
  fail "Pro-expired tier-line missing expected shape; got:"
  echo "$EXPIRED_OUT" | sed 's/^/      /'
fi
if echo "$EXPIRED_OUT" | grep -qF "$EXPIRED_TOKEN"; then
  fail "Pro-expired output leaked full token"
else
  pass "Pro-expired output redacts full token"
fi
if echo "$EXPIRED_OUT" | grep -q "After buying a renewal, replace the token"; then
  pass "Pro-expired output surfaces the renewal hint"
else
  fail "Pro-expired output missing renewal hint"
fi

echo ""
echo "Summary: $PASS PASS, $FAIL FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "PASS: V1 SaaS Plugin Pro tier-expiry surface verified end-to-end"
exit 0
