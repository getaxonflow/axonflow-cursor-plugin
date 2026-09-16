#!/usr/bin/env bash
# Unit tests for scripts/upgrade-prompt.sh — V1 Plugin Pro envelope handling.
#
# Exercises every branch of axonflow_handle_envelope_response +
# axonflow_throttle_active using captured envelope shapes that match the
# locked wire contract from
# axonflow-enterprise/platform/agent/community_saas_ratelimit_response.go.
#
# Each fixture body is a verbatim copy of what the agent emits — generated
# from `runtime-e2e/v1_pro_envelope_surface/EVIDENCE/<utc-ts>/envelope_body.json`
# (real wire) and the `community_saas_ratelimit_response_test.go` golden
# files. Edits to the locked envelope shape MUST flow through both that Go
# test and these fixtures.
#
# These run on every PR (`./tests/test-hooks.sh` companion). The runtime-e2e
# harness runs against try.getaxonflow.com but requires AWS access for the
# DB-seed path, so this unit suite is the always-on safety net.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$PLUGIN_DIR/scripts/upgrade-prompt.sh"

if [ ! -f "$HELPER" ]; then
  echo "FAIL: $HELPER not found"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH"
  exit 0
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
  if echo "$haystack" | grep -F "$needle" >/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to find '$needle' in:)"
    echo "$haystack" | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -F "$needle" >/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected NOT to find '$needle' in:)"
    echo "$haystack" | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

# Each test runs in a subshell that emits "PASS_INC=N FAIL_INC=N" on its
# last line; the parent reads that line and increments the running totals.
# Subshell isolation is required because:
#   - upgrade-prompt.sh's _AXONFLOW_UPGRADE_PROMPT_LOADED guard would
#     otherwise short-circuit re-sourcing (functions defined once, never
#     re-bound to a fresh XDG_CACHE_HOME).
#   - Once-per-day stamps live in $XDG_CACHE_HOME and bleed across tests
#     unless each test gets a fresh cache.
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
  # Print everything except the magic trailers so the human sees the
  # PASS/FAIL lines in real-time order.
  echo "$out" | grep -v '^TEST_RESULT_'
  local sub_pass sub_fail
  sub_pass=$(echo "$out" | awk -F= '/^TEST_RESULT_PASS=/{print $2}')
  sub_fail=$(echo "$out" | awk -F= '/^TEST_RESULT_FAIL=/{print $2}')
  PASS=$((PASS + ${sub_pass:-0}))
  FAIL=$((FAIL + ${sub_fail:-0}))
}

mk_tmp_cache() {
  local d
  d=$(mktemp -d -t axonflow-upprompt.XXXXXX)
  echo "$d"
}

mk_body_429_daily_quota() {
  cat <<'EOF'
{
  "error": "Daily request limit reached. Resets at midnight UTC.",
  "limit_type": "daily_quota",
  "tier": "Free",
  "limit": 200,
  "remaining": 0,
  "window": "daily_utc",
  "resets_at": "2099-12-31T23:59:59Z",
  "upgrade": {
    "tier": "Pro",
    "wording": "Daily limit reached on Free tier (200 events). Pro raises this to 2,000/day. Resets at midnight UTC.",
    "compare_url": "https://getaxonflow.com/pricing/",
    "buy_url": "https://buy.stripe.com/bJe28qbztcdVchjdkw8k800"
  }
}
EOF
}

mk_body_403_active_policies() {
  cat <<'EOF'
{
  "error": "Free tier supports 2 active custom policies. Delete one to make room, or Pro removes the cap.",
  "limit_type": "active_policies",
  "tier": "Free",
  "limit": 2,
  "remaining": 0,
  "upgrade": {
    "tier": "Pro",
    "wording": "Free tier supports 2 active custom policies. Delete one to make room, or Pro removes the cap.",
    "compare_url": "https://getaxonflow.com/pricing/",
    "buy_url": "https://buy.stripe.com/bJe28qbztcdVchjdkw8k800"
  }
}
EOF
}

# JSON-RPC wrapped envelope (returned by /api/v1/mcp-server tools/call when
# enforceMCPToolGate fires writeMCPGateError — see mcp_v1_pro_tools.go).
mk_body_jsonrpc_wrapped_envelope() {
  cat <<'EOF'
{
  "jsonrpc": "2.0",
  "id": "call-1",
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\n  \"error\": \"Free tier supports 2 active custom policies. Delete one to make room, or Pro removes the cap.\",\n  \"limit_type\": \"active_policies\",\n  \"tier\": \"Free\",\n  \"limit\": 2,\n  \"remaining\": 0,\n  \"upgrade\": {\n    \"tier\": \"Pro\",\n    \"wording\": \"Free tier supports 2 active custom policies. Delete one to make room, or Pro removes the cap.\",\n    \"compare_url\": \"https://getaxonflow.com/pricing/\",\n    \"buy_url\": \"https://buy.stripe.com/bJe28qbztcdVchjdkw8k800\"\n  }\n}"
      }
    ],
    "isError": true
  }
}
EOF
}

mk_headers_429_with_retry_after() {
  cat <<'EOF'
HTTP/2 429
content-type: application/json
x-axonflow-tier-limit: daily_quota
x-axonflow-upgrade-url: https://getaxonflow.com/pricing/
retry-after: 3600
date: Thu, 07 May 2026 00:25:10 GMT
EOF
}

mk_headers_403_no_retry_after() {
  cat <<'EOF'
HTTP/2 403
content-type: application/json
x-axonflow-tier-limit: active_policies
x-axonflow-upgrade-url: https://getaxonflow.com/pricing/
date: Thu, 07 May 2026 00:25:10 GMT
EOF
}

mk_body_legacy_429_no_envelope() {
  # Legacy / older self-hosted stacks that haven't been updated to the
  # V1 envelope shape — body is a bare error string.
  cat <<'EOF'
{"error": "Rate limit exceeded (20 req/min). Try again shortly."}
EOF
}

# ---------------------------------------------------------------------------
# Test 1: 429 daily-quota envelope is detected, wording surfaced, throttle
# stamped from resets_at.
# ---------------------------------------------------------------------------
test_429_daily_quota() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stderr_out
  body=$(mktemp); mk_body_429_daily_quota >"$body"
  headers=$(mktemp); mk_headers_429_with_retry_after >"$headers"
  stderr_out=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_envelope_response "429" "$body" "$headers" 2>"$stderr_out"
  local rc=$?

  assert_eq "rc == 0 (envelope detected)" "0" "$rc"
  assert_contains "stderr carries locked wording" "$(cat "$stderr_out")" "Pro raises this to 2,000/day"
  assert_contains "stderr carries Pro upgrade pointer" "$(cat "$stderr_out")" "https://buy.stripe.com/bJe28qbztcdVchjdkw8k800"

  # Throttle file stamped, deadline in the future.
  local tf="$cache/axonflow/throttle-until"
  assert_eq "throttle file exists" "yes" "$([ -f "$tf" ] && echo yes || echo no)"
  if [ -f "$tf" ]; then
    local epoch; epoch=$(awk 'NR==1 {print $1}' "$tf")
    local now; now=$(date -u +%s)
    if [ -n "$epoch" ] && [ "$epoch" -gt "$now" ]; then
      assert_eq "deadline in the future" "yes" "yes"
    else
      assert_eq "deadline in the future" "yes" "no (epoch=$epoch now=$now)"
    fi
  fi

  rm -f "$body" "$headers" "$stderr_out"
}

# ---------------------------------------------------------------------------
# Test 2: 403 active_policies envelope (no resets_at, no Retry-After) still
# stamps a short throttle deadline so the next call backs off briefly.
# ---------------------------------------------------------------------------
test_403_active_policies() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stderr_out
  body=$(mktemp); mk_body_403_active_policies >"$body"
  headers=$(mktemp); mk_headers_403_no_retry_after >"$headers"
  stderr_out=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_envelope_response "403" "$body" "$headers" 2>"$stderr_out"
  local rc=$?

  assert_eq "rc == 0 (envelope detected)" "0" "$rc"
  assert_contains "stderr carries active_policies wording" "$(cat "$stderr_out")" "Free tier supports 2 active custom policies"

  local tf="$cache/axonflow/throttle-until"
  assert_eq "throttle file exists despite no resets_at" "yes" "$([ -f "$tf" ] && echo yes || echo no)"

  rm -f "$body" "$headers" "$stderr_out"
}

# ---------------------------------------------------------------------------
# Test 3: JSON-RPC wrapped envelope (the shape returned on the MCP path
# by writeMCPGateError) is parsed via the dual-shape branch.
# ---------------------------------------------------------------------------
test_jsonrpc_wrapped_envelope() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stderr_out
  body=$(mktemp); mk_body_jsonrpc_wrapped_envelope >"$body"
  # MCP path returns 200 OK with the gate result inside JSON-RPC; the
  # helper still treats it as envelope-bearing because limit_type is
  # present in the wrapped text. Documented behaviour.
  headers=$(mktemp); mk_headers_403_no_retry_after >"$headers"
  stderr_out=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_envelope_response "403" "$body" "$headers" 2>"$stderr_out"
  local rc=$?

  assert_eq "rc == 0 (wrapped envelope detected)" "0" "$rc"
  assert_contains "stderr carries wrapped wording" "$(cat "$stderr_out")" "Free tier supports 2 active custom policies"

  rm -f "$body" "$headers" "$stderr_out"
}

# ---------------------------------------------------------------------------
# Test 4: legacy 429 (no envelope, just bare error) — helper returns
# non-zero so the caller's own 429 handling runs (the hooks block a 429 with
# or without an envelope; tests/test-hooks.sh). The helper must not stamp.
# ---------------------------------------------------------------------------
test_legacy_429_no_envelope_preserves_behaviour() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stderr_out
  body=$(mktemp); mk_body_legacy_429_no_envelope >"$body"
  headers=$(mktemp); echo "" >"$headers"
  stderr_out=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_envelope_response "429" "$body" "$headers" 2>"$stderr_out"
  local rc=$?

  assert_eq "rc != 0 (no envelope; caller falls through)" "1" "$rc"

  # Throttle file MUST NOT be stamped — caller's normal path runs.
  local tf="$cache/axonflow/throttle-until"
  assert_eq "throttle file NOT stamped on legacy 429" "no" "$([ -f "$tf" ] && echo yes || echo no)"

  rm -f "$body" "$headers" "$stderr_out"
}

# ---------------------------------------------------------------------------
# Test 5: non-429/403 status (e.g. 200) is rejected immediately — even
# if the body were envelope-shaped, we don't fire on success codes.
# ---------------------------------------------------------------------------
test_non_4xx_status_ignored() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers
  body=$(mktemp); mk_body_429_daily_quota >"$body"
  headers=$(mktemp); mk_headers_429_with_retry_after >"$headers"

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_envelope_response "200" "$body" "$headers" 2>/dev/null
  local rc=$?
  assert_eq "rc != 0 for HTTP 200" "1" "$rc"

  axonflow_handle_envelope_response "500" "$body" "$headers" 2>/dev/null
  rc=$?
  assert_eq "rc != 0 for HTTP 500" "1" "$rc"

  rm -f "$body" "$headers"
}

# ---------------------------------------------------------------------------
# Test 6: once-per-UTC-day stamp suppresses the wording on the second
# invocation against the same envelope.
# ---------------------------------------------------------------------------
test_once_per_day_stamp() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stderr1 stderr2
  body=$(mktemp); mk_body_429_daily_quota >"$body"
  headers=$(mktemp); mk_headers_429_with_retry_after >"$headers"
  stderr1=$(mktemp)
  stderr2=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_envelope_response "429" "$body" "$headers" 2>"$stderr1"
  axonflow_handle_envelope_response "429" "$body" "$headers" 2>"$stderr2"

  assert_contains "first invocation prints wording" "$(cat "$stderr1")" "Pro raises this to 2,000/day"
  assert_not_contains "second invocation suppresses wording (once-per-day)" \
    "$(cat "$stderr2")" "Pro raises this to 2,000/day"

  rm -f "$body" "$headers" "$stderr1" "$stderr2"
}

# ---------------------------------------------------------------------------
# Test 7: axonflow_throttle_active reflects the stamped deadline.
#   - no stamp → returns 1 (no throttle)
#   - future-epoch stamp → returns 0 (active)
#   - past-epoch stamp → returns 1 + clears the file
# ---------------------------------------------------------------------------
test_throttle_active_states() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  # shellcheck disable=SC1090
  . "$HELPER"

  # Case A: no file
  axonflow_throttle_active
  assert_eq "no stamp → throttle inactive" "1" "$?"

  # Case B: future epoch
  mkdir -p "$cache/axonflow"
  echo "9999999999 daily_quota" >"$cache/axonflow/throttle-until"
  axonflow_throttle_active
  assert_eq "future epoch → throttle active" "0" "$?"

  # Case C: past epoch — should clear the file
  echo "1 daily_quota" >"$cache/axonflow/throttle-until"
  axonflow_throttle_active
  assert_eq "past epoch → throttle inactive" "1" "$?"
  assert_eq "past-epoch stamp file cleared" "no" \
    "$([ -f "$cache/axonflow/throttle-until" ] && echo yes || echo no)"
}

# ---------------------------------------------------------------------------
# Test 8: helper writes nothing to stdout (stdout is reserved for the
# hook protocol; any byte breaks the parser).
# ---------------------------------------------------------------------------
test_no_stdout_bytes() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"

  local body headers stdout_out
  body=$(mktemp); mk_body_429_daily_quota >"$body"
  headers=$(mktemp); mk_headers_429_with_retry_after >"$headers"
  stdout_out=$(mktemp)

  # shellcheck disable=SC1090
  . "$HELPER"

  axonflow_handle_envelope_response "429" "$body" "$headers" >"$stdout_out" 2>/dev/null
  local size; size=$(wc -c <"$stdout_out" | tr -d ' ')
  assert_eq "stdout is empty" "0" "$size"

  rm -f "$body" "$headers" "$stdout_out"
}

# assert_has <desc> <haystack> <fixed needle>: a here-string, never a pipe
# (under pipefail `echo | grep -q` can read a match as a miss).
assert_has() {
  if grep -qF -e "$3" <<<"$2"; then
    echo "  PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $1 (expected to find '$3' in: $(head -c 300 <<<"$2"))"
    FAIL=$((FAIL + 1))
  fi
}

# _pin_clock <epoch>: the helpers read the clock through `date -u +%s`. The
# pinned value lives in its own name: the helpers declare `local now`, and
# bash scoping is dynamic, so a function echoing "$now" would read theirs.
_pin_clock() {
  _PINNED_NOW="$1"
  date() { if [ "$*" = "-u +%s" ]; then echo "$_PINNED_NOW"; else command date "$@"; fi; }
}

# _set_mtime <file> <epoch>
_set_mtime() {
  python3 -c 'import os,sys; t=float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"
}

# ---------------------------------------------------------------------------
# Test 9: the stamp rules (axonflow_governed_stamp), with the clock pinned.
# axonflow-enterprise#4249 comment 5684124176: only a request-rate limit
# (daily_quota, per_minute) gates, for at most 300 s after the stamp file was
# written; a stamp written more than 60 s in the future is past the cap; a
# feature or object-count limit gates nothing; auth_failure gates for its
# configured length. A stamp that does not gate is left on disk unchanged.
# ---------------------------------------------------------------------------
test_governed_stamp_rules() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"
  # shellcheck disable=SC1090
  . "$HELPER"

  local now tf out rc t
  now=$(command date -u +%s)
  tf="$cache/axonflow/throttle-until"
  mkdir -p "$cache/axonflow"
  _pin_clock "$now"

  # stamp <line> <mtime offset from the pinned now, seconds>
  stamp() {
    echo "$1" >"$tf"
    _set_mtime "$tf" "$((_PINNED_NOW + $2))"
  }
  # check <desc> <expected output> <expected rc> [<file kept: yes|no>]
  check() {
    local before; before=$(cat "$tf" 2>/dev/null)
    out=$(axonflow_governed_stamp); rc=$?
    assert_eq "$1 → prints '$2'" "$2" "$out"
    assert_eq "$1 → rc $3" "$3" "$rc"
    if [ "${4:-yes}" = "yes" ]; then
      assert_eq "$1 → the stamp is left on disk unchanged" "$before" "$(cat "$tf" 2>/dev/null)"
    else
      assert_eq "$1 → the stamp is removed" "no" "$([ -f "$tf" ] && echo yes || echo no)"
    fi
  }

  rm -f "$tf"
  out=$(axonflow_governed_stamp); rc=$?
  assert_eq "no stamp → prints nothing" "" "$out"
  assert_eq "no stamp → rc 1" "1" "$rc"

  # Rules 1 and 3: a request-rate limit, honoured for at most 300 s after it
  # was written (the deadline itself is a day out).
  for t in daily_quota per_minute; do
    stamp "$((now + 86400)) $t" -299; check "$t written 299 s ago" limit 0
    stamp "$((now + 86400)) $t" -300; check "$t written 300 s ago" "" 1
    stamp "$((now + 86400)) $t" -301; check "$t written 301 s ago" "" 1
    stamp "$((now + 86400)) $t" 0;    check "$t written now" limit 0
  done

  # Rule 4: written in the future. Up to 60 s ahead counts as written now.
  stamp "$((now + 86400)) daily_quota" 59;    check "daily_quota written 59 s in the future" limit 0
  stamp "$((now + 86400)) daily_quota" 60;    check "daily_quota written 60 s in the future" limit 0
  stamp "$((now + 86400)) daily_quota" 61;    check "daily_quota written 61 s in the future" "" 1
  stamp "$((now + 86400)) per_minute" 61;     check "per_minute written 61 s in the future" "" 1
  stamp "$((now + 86400)) daily_quota" 86400; check "daily_quota written a day in the future" "" 1

  # Rule 2: a feature or object-count limit gates nothing, whatever its
  # deadline or age, and is left for the plugin that wrote it (rule 5).
  for t in feature_pro_only active_policies hitl_approvals_window decision_list_size; do
    stamp "$((now + 604800)) $t" 0;    check "$t written now, deadline a week out" "" 1
    stamp "$((now + 604800)) $t" -299; check "$t written 299 s ago" "" 1
  done
  stamp "$((now + 3600)) some_future_limit" 0; check "an unknown limit type" "" 1
  stamp "$((now + 3600))" 0;                   check "a stamp with no limit type" "" 1

  # Rule 6: the auth_failure cooldown gates for this hook's configured length
  # from when its file was written, with rule 4's skew; the deadline in the
  # file (a week out, a millisecond epoch) never extends it.
  stamp "$((now + 60)) auth_failure" -3600;  check "auth_failure written an hour ago, 60 s left" "" 1
  stamp "$((now + 60)) auth_failure" 3600;   check "auth_failure written an hour in the future, 60 s left" "" 1
  stamp "$((now + 1)) auth_failure" -301;    check "auth_failure written 301 s ago, 1 s left" "" 1
  stamp "$((now + 604800)) auth_failure" -299; check "auth_failure a week out, written 299 s ago" auth_failure 0
  stamp "$((now + 604800)) auth_failure" -300; check "auth_failure a week out, written 300 s ago" "" 1
  stamp "$((now + 604800)) auth_failure" -1200; check "auth_failure a week out, written 20 minutes ago" "" 1
  stamp "$((now * 1000)) auth_failure" 0;    check "auth_failure with a millisecond deadline, written now" auth_failure 0
  stamp "$((now * 1000)) auth_failure" -301; check "auth_failure with a millisecond deadline, written 301 s ago" "" 1
  stamp "$((now + 604800)) auth_failure" 60; check "auth_failure written 60 s in the future" auth_failure 0
  stamp "$((now + 604800)) auth_failure" 61; check "auth_failure written 61 s in the future" "" 1

  # The deadline passed, or the stamp is unreadable: cleared.
  stamp "$((now - 1)) daily_quota" 0;  check "daily_quota whose deadline passed" "" 1 no
  stamp "$now auth_failure" -10;       check "auth_failure whose deadline is now" "" 1 no
  stamp "$((now - 1)) feature_pro_only" 0; check "feature_pro_only whose deadline passed" "" 1 no
  stamp "not-a-number daily_quota" 0;  check "a malformed stamp" "" 1 no

  # The remaining seconds and the cooldown note name the file.
  stamp "$((now + 120)) auth_failure" 0
  assert_eq "remaining seconds for a 120 s cooldown" "120" "$(axonflow_throttle_remaining_seconds)"
  assert_has "the cooldown note names the seconds" "$(axonflow_auth_cooldown_note)" "blocked for another 120 seconds"
  assert_has "the cooldown note names the file" "$(axonflow_auth_cooldown_note)" "$tf"
  stamp "$((now + 604800)) auth_failure" -100
  assert_eq "remaining seconds for a week-out auth_failure written 100 s ago (cooldown 300 s)" "200" "$(axonflow_throttle_remaining_seconds)"
  # A deadline too long for bash arithmetic is malformed: cleared, no error.
  stamp "99999999999999999999 auth_failure" 0
  out=$(axonflow_governed_stamp 2>&1); rc=$?
  assert_eq "a 20-digit deadline → prints nothing (no arithmetic error)" "" "$out"
  assert_eq "a 20-digit deadline → rc 1" "1" "$rc"
  stamp "$((now * 1000)) auth_failure" 0
  assert_eq "a millisecond deadline (13 digits) is still read" "auth_failure" "$(axonflow_governed_stamp 2>&1)"
  # A cooldown that is not whole seconds reads as the default.
  local v
  for v in abc 1e3 -5 "300 x" 99999999; do
    assert_eq "_AXONFLOW_AUTH_FAILURE_COOLDOWN_SECONDS='$v' → 300" "300" "$(_AXONFLOW_AUTH_FAILURE_COOLDOWN_SECONDS="$v" bash -c '. "$1"; echo "$_AXONFLOW_AUTH_FAILURE_COOLDOWN_SECONDS"' _ "$HELPER")"
  done
  unset -f date stamp check
}

# ---------------------------------------------------------------------------
# Test 10: the auth_failure cooldown's length is its configured length
# (_AXONFLOW_AUTH_FAILURE_COOLDOWN_SECONDS), clock pinned: a 1200 s cooldown
# stamped by a 401 still gates 1199 s later, past the 300 s limit cap, and
# is cleared at 1200 s.
# ---------------------------------------------------------------------------
test_auth_failure_cooldown_configured_length() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"
  export _AXONFLOW_AUTH_FAILURE_COOLDOWN_SECONDS=1200
  # shellcheck disable=SC1090
  . "$HELPER"

  local now tf body out rc
  now=$(command date -u +%s)
  tf="$cache/axonflow/throttle-until"
  body=$(mktemp)
  echo '{"error":"unauthorized"}' >"$body"
  _pin_clock "$now"

  axonflow_handle_auth_failure "401" "$body" "/dev/null" 2>/dev/null
  assert_eq "a 401 stamps now + the configured 1200 s" "$((now + 1200)) auth_failure" "$(cat "$tf" 2>/dev/null)"
  _set_mtime "$tf" "$now"

  _pin_clock "$((now + 1199))"
  out=$(axonflow_governed_stamp); rc=$?
  assert_eq "1199 s after the 401 → auth_failure still gates" "auth_failure" "$out"
  assert_eq "1199 s after the 401 → rc 0" "0" "$rc"
  assert_eq "1199 s after the 401 → 1 second left" "1" "$(axonflow_throttle_remaining_seconds)"

  _pin_clock "$((now + 1200))"
  out=$(axonflow_governed_stamp); rc=$?
  assert_eq "1200 s after the 401 → gates nothing" "" "$out"
  assert_eq "1200 s after the 401 → rc 1" "1" "$rc"
  assert_eq "1200 s after the 401 → the expired cooldown is cleared" "no" "$([ -f "$tf" ] && echo yes || echo no)"
  unset -f date
  rm -f "$body"
}

# ---------------------------------------------------------------------------
# Test 11: the shared file's WRITE and format are unchanged: one line,
# `<epoch> <limit_type>`, overwritten, a feature-limit envelope included and
# its resets_at uncapped (other plugins read the file and honour it their way).
# ---------------------------------------------------------------------------
test_stamp_write_format_unchanged() {
  local cache; cache=$(mk_tmp_cache)
  trap "rm -rf '$cache'" EXIT
  export XDG_CACHE_HOME="$cache"
  # shellcheck disable=SC1090
  . "$HELPER"
  local body headers tf resets
  tf="$cache/axonflow/throttle-until"
  resets=$(( $(date -u +%s) + 604800 ))
  body=$(mktemp); headers=$(mktemp)
  jq -nc --arg r "$(date -u -r "$resets" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$resets" +%Y-%m-%dT%H:%M:%SZ)" \
    '{error: "HITL approval window used", limit_type: "hitl_approvals_window", tier: "Free", resets_at: $r, upgrade: {wording: "HITL-WORDING", buy_url: "https://example.invalid/pricing"}}' >"$body"
  axonflow_handle_envelope_response "403" "$body" "$headers" 2>/dev/null
  assert_eq "a hitl_approvals_window envelope is still stamped, its resets_at uncapped" "$resets hitl_approvals_window" "$(cat "$tf")"
  assert_eq "the stamp is one line" "1" "$(wc -l <"$tf" | tr -d ' ')"
  out=$(axonflow_governed_stamp); rc=$?
  assert_eq "the week-long hitl_approvals_window stamp gates nothing" "1" "$rc"
  assert_eq "... and is left on disk" "$resets hitl_approvals_window" "$(cat "$tf")"
  axonflow_handle_auth_failure "401" "$body" "$headers" 2>/dev/null
  assert_has "a 401 overwrites the same file with auth_failure" "$(cat "$tf")" " auth_failure"
  assert_eq "still one line after the overwrite" "1" "$(wc -l <"$tf" | tr -d ' ')"
  rm -f "$body" "$headers"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
run_test "T1: 429 daily-quota envelope" test_429_daily_quota
run_test "T2: 403 active_policies envelope" test_403_active_policies
run_test "T3: JSON-RPC wrapped envelope" test_jsonrpc_wrapped_envelope
run_test "T4: legacy 429 no envelope (preserve behaviour)" test_legacy_429_no_envelope_preserves_behaviour
run_test "T5: non-4xx status ignored" test_non_4xx_status_ignored
run_test "T6: once-per-day stamp suppresses second wording" test_once_per_day_stamp
run_test "T7: axonflow_throttle_active state machine" test_throttle_active_states
run_test "T8: no stdout bytes" test_no_stdout_bytes
run_test "T9: the stamp rules (axonflow_governed_stamp, clock pinned)" test_governed_stamp_rules
run_test "T10: the auth_failure cooldown gates for its configured length (clock pinned)" test_auth_failure_cooldown_configured_length
run_test "T11: the shared stamp file's write and format are unchanged" test_stamp_write_format_unchanged

echo
echo "==============================="
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
echo "==============================="
[ "$FAIL" -eq 0 ]
