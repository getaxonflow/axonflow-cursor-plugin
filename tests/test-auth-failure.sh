#!/usr/bin/env bash
# Unit tests for scripts/upgrade-prompt.sh — HTTP 401 auth-failure throttle.
#
# Regression coverage for axonflow-enterprise#2275: 716 retries against
# /api/v1/audit/tool-call from a single source IP in 24h pre-fix.
#
# Symptom: when AXONFLOW_AUTH is invalid/expired, every pre-tool-check.sh
# and post-tool-audit.sh hook fires a 401, the envelope handler returns 1
# (it only fires on 429/403), and the script falls through and re-issues
# the same 401 on the next tool call. Tight retry loop.
#
# Fix: axonflow_handle_auth_failure stamps a 5-minute throttle on 401 so
# subsequent hook fires short-circuit via axonflow_throttle_active.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$PLUGIN_DIR/scripts/upgrade-prompt.sh"

if [ ! -f "$HELPER" ]; then
  echo "FAIL: $HELPER not found"
  exit 1
fi

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to find '$needle' in:)"
    echo "$haystack" | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

# Each test runs in a subshell with a fresh XDG_CACHE_HOME so the throttle
# stamp + once-per-day stamp don't bleed across tests. Same subshell pattern
# as tests/test-upgrade-prompt.sh.
run_test() {
  local name="$1"
  shift
  echo
  echo "=== $name ==="
  local out
  out=$(
    (
      PASS=0
      FAIL=0
      "$@"
      echo "TEST_RESULT_PASS=$PASS"
      echo "TEST_RESULT_FAIL=$FAIL"
    )
  )
  echo "$out" | grep -v '^TEST_RESULT_'
  local sub_pass sub_fail
  sub_pass=$(echo "$out" | awk -F= '/^TEST_RESULT_PASS=/{print $2}')
  sub_fail=$(echo "$out" | awk -F= '/^TEST_RESULT_FAIL=/{print $2}')
  PASS=$((PASS + ${sub_pass:-0}))
  FAIL=$((FAIL + ${sub_fail:-0}))
}

mk_tmp_cache() {
  mktemp -d -t axonflow-authfail.XXXXXX
}

# Captured 401 body from a real agent rejection (Authorization header
# present but invalid). The body is best-effort plain text; the helper
# intentionally does not parse it — 401 is detected by status code alone.
mk_body_401() {
  cat <<'EOF'
{"error": "unauthorized: invalid credentials"}
EOF
}

mk_headers_401() {
  cat <<'EOF'
HTTP/2 401
content-type: application/json
www-authenticate: Basic realm="axonflow"
date: Tue, 20 May 2026 12:00:00 GMT
EOF
}

# ---------------------------------------------------------------------------
# T1: HTTP 401 stamps throttle, returns 0, deadline is now + ~300s.
# ---------------------------------------------------------------------------
test_401_stamps_throttle() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stderr_out
  body=$(mktemp); mk_body_401 >"$body"
  headers=$(mktemp); mk_headers_401 >"$headers"
  stderr_out=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  local before_now
  before_now=$(date -u +%s)
  axonflow_handle_auth_failure "401" "$body" "$headers" 2>"$stderr_out"
  local rc=$?
  local after_now
  after_now=$(date -u +%s)

  assert_eq "rc == 0 (401 detected)" "0" "$rc"

  local tf="$cache/axonflow/throttle-until"
  assert_eq "throttle file exists" "yes" "$([ -f "$tf" ] && echo yes || echo no)"
  if [ -f "$tf" ]; then
    local epoch limit_type
    epoch=$(awk 'NR==1 {print $1}' "$tf")
    limit_type=$(awk 'NR==1 {print $2}' "$tf")
    assert_eq "limit_type is auth_failure" "auth_failure" "$limit_type"

    # Deadline should be in [before + 300 - 10, after + 300 + 10] for clock skew.
    local lo=$((before_now + 300 - 10))
    local hi=$((after_now + 300 + 10))
    if [ "$epoch" -ge "$lo" ] && [ "$epoch" -le "$hi" ]; then
      assert_eq "deadline ≈ now + 300s (±10 skew)" "ok" "ok"
    else
      assert_eq "deadline ≈ now + 300s (±10 skew)" "ok" \
        "bad (epoch=$epoch lo=$lo hi=$hi)"
    fi
  fi

  # User-visible nudge surfaces the AXONFLOW_AUTH instruction on stderr.
  assert_contains "stderr identifies HTTP 401" "$(cat "$stderr_out")" \
    "Authentication failed (HTTP 401)"
  assert_contains "stderr names the 5-minute pause" "$(cat "$stderr_out")" \
    "paused for 5 minutes"
  assert_contains "stderr links the dashboard" "$(cat "$stderr_out")" \
    "https://getaxonflow.com/dashboard"

  rm -f "$body" "$headers" "$stderr_out"
}

# ---------------------------------------------------------------------------
# T2: HTTP 200 / 4xx-not-401 / 5xx are ignored. Critical guard — without
# this, every successful response would stamp a throttle and break
# governance entirely.
# ---------------------------------------------------------------------------
test_non_401_status_ignored() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers
  body=$(mktemp); mk_body_401 >"$body"
  headers=$(mktemp); mk_headers_401 >"$headers"

  # shellcheck disable=SC1090
  . "$HELPER"

  local rc
  for code in 200 403 404 429 500 ""; do
    axonflow_handle_auth_failure "$code" "$body" "$headers" 2>/dev/null
    rc=$?
    assert_eq "rc != 0 for HTTP '${code}'" "1" "$rc"
  done

  # Throttle file MUST NOT have been stamped by any of the above.
  local tf="$cache/axonflow/throttle-until"
  assert_eq "throttle file not stamped on non-401 statuses" "no" \
    "$([ -f "$tf" ] && echo yes || echo no)"

  rm -f "$body" "$headers"
}

# ---------------------------------------------------------------------------
# T3: after axonflow_handle_auth_failure stamps the throttle,
# axonflow_throttle_active reports active immediately on next hook fire —
# the storm-prevention contract. Without this, the fix is meaningless.
# ---------------------------------------------------------------------------
test_throttle_active_after_401() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers
  body=$(mktemp); mk_body_401 >"$body"
  headers=$(mktemp); mk_headers_401 >"$headers"

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_auth_failure "401" "$body" "$headers" 2>/dev/null

  axonflow_throttle_active
  assert_eq "throttle active right after 401" "0" "$?"

  rm -f "$body" "$headers"
}

# ---------------------------------------------------------------------------
# T4: helper writes nothing to stdout (stdout is reserved for the hook
# protocol; any byte breaks the parser). Mirrors test-upgrade-prompt T8.
# ---------------------------------------------------------------------------
test_no_stdout_bytes() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stdout_out
  body=$(mktemp); mk_body_401 >"$body"
  headers=$(mktemp); mk_headers_401 >"$headers"
  stdout_out=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_auth_failure "401" "$body" "$headers" >"$stdout_out" 2>/dev/null
  local size; size=$(wc -c <"$stdout_out" | tr -d ' ')
  assert_eq "stdout is empty" "0" "$size"

  rm -f "$body" "$headers" "$stdout_out"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
run_test "T1: HTTP 401 stamps throttle (5-min cooldown, auth_failure limit_type, stderr nudge)" test_401_stamps_throttle
run_test "T2: non-401 statuses ignored (200/403/404/429/500/empty)" test_non_401_status_ignored
run_test "T3: throttle_active reports active right after 401" test_throttle_active_after_401
run_test "T4: no stdout bytes (hook-protocol guard)" test_no_stdout_bytes

echo
echo "==============================="
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
echo "==============================="
[ "$FAIL" -eq 0 ]
