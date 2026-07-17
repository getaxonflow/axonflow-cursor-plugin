#!/usr/bin/env bash
# Wire test for X-User-Token on the HOOK surfaces (axonflow-enterprise#2943,
# Cursor port of claude-plugin#107; epic #2919: per-user identity + role on
# the fleet/MCP-server plane).
#
# Unlike tests/test-user-token.sh (resolver unit + mcp-auth-headers.sh
# reference impl) and tests/test-mcp-json-alignment.sh (the static mcp.json
# template), this drives the ACTUAL hook scripts against a header-capturing
# mock agent and asserts the outbound requests carry X-User-Token when a
# per-user token is configured (env var AND 0600 file legs) — and DON'T when
# it is not (the common fleet state today), in which case the emitted header
# key set must be exactly what an unconfigured 1.5.x plugin sends. Covers
# both hook surfaces and ALL FIVE governed request classes (each keyed by its
# JSON-RPC id in the capture, so every curl is pinned individually):
#   - pre-tool-check.sh  → check_policy (hook-pre) + the blocked-audit POST
#     (hook-audit-blocked) + the shell-write check_output scan (hook-pii)
#   - post-tool-audit.sh → audit_tool_call (hook-audit) + check_output
#     (hook-scan)
#
# Also pins that the hooks NEVER leak the token value to stdout (the hook
# protocol) or stderr (operator-visible diagnostics).
#
# Stdlib-only (bash + python3 + jq).

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRE_HOOK="$PLUGIN_DIR/scripts/pre-tool-check.sh"
POST_HOOK="$PLUGIN_DIR/scripts/post-tool-audit.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }

if ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: python3/jq not on PATH"
  exit 0
fi

WORK="$(mktemp -d)"
CAP="$WORK/headers.log"    # one {"rpc_id":…,"headers":{…}} JSON object per line
: > "$CAP"
cleanup() { [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null; wait 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# Header-capturing mock agent. Returns a BLOCK decision when MOCK_BLOCK=1 so
# pre-tool-check.sh also fires its backgrounded audit_tool_call POST —
# proving the token rides AUTH_HEADER onto EVERY governed curl, not just the
# first one. Each capture line is {"rpc_id": <JSON-RPC id>, "headers": {...}}
# so per-curl assertions (e.g. the hook-pii shell-write scan) can key on the
# specific request class, not just the aggregate.
cat > "$WORK/server.py" <<'PY'
import http.server, json, os, sys
CAP = os.environ["CAP_FILE"]
BLOCK = os.environ.get("MOCK_BLOCK", "") == "1"
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(n) if n else b''
        try:
            rpc_id = json.loads(raw).get("id", "")
        except Exception:
            rpc_id = ""
        with open(CAP, 'a') as f:
            f.write(json.dumps({"rpc_id": rpc_id, "headers": {k: v for k, v in self.headers.items()}}) + "\n")
        if BLOCK:
            result = {"allowed": False, "block_reason": "wire-test block", "policies_evaluated": 1}
        else:
            result = {"allowed": True, "policies_evaluated": 0}
        body = {"jsonrpc":"2.0","id":"x","result":{"content":[{"type":"text","text":json.dumps(result)}]}}
        out = json.dumps(body).encode()
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length', str(len(out)))
        self.end_headers()
        self.wfile.write(out)
server = http.server.HTTPServer(('127.0.0.1', 0), H)
sys.stdout.write(str(server.server_address[1]) + "\n"); sys.stdout.flush()
server.serve_forever()
PY

start_server() { # <block-flag>
  [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null && wait 2>/dev/null
  : > "$WORK/port"
  CAP_FILE="$CAP" MOCK_BLOCK="$1" python3 "$WORK/server.py" > "$WORK/port" 2>/dev/null &
  SRV_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port" 2>/dev/null)"
  [ -n "$PORT" ] || { echo "FAIL: mock server did not start"; exit 1; }
  ENDPOINT="http://127.0.0.1:$PORT"
}

TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJlbWFpbCI6ImRldkB4LmNvIiwicm9sZSI6ImRldmVsb3BlciJ9.wire-sig'

# run_hook <hook> <mode> — invokes a hook with a Write tool payload. mode:
#   env    — AXONFLOW_USER_TOKEN exported
#   file   — 0600 ~/.config/axonflow/user-token.json in a fresh HOME
#   none   — no token anywhere (the common fleet state)
# Fresh HOME per run (hermetic: no host credentials/stamps leak in; the file
# leg's HOME carries ONLY the token file). Hook stdout/stderr captured for
# the no-leak assertions.
HOOK_STDOUT="$WORK/hook-stdout.log"
HOOK_STDERR="$WORK/hook-stderr.log"
RUN_N=0
run_hook() {
  local hook="$1" mode="$2" kind="${3:-write}"
  RUN_N=$((RUN_N+1))
  local run_home="$WORK/home-$RUN_N"
  mkdir -p "$run_home"
  local input
  if [ "$kind" = "bash-redirect" ]; then
    # A shell write: the ONLY payload class that reaches the pre-tool hook-pii
    # check_output scan (the 5th governed curl) — Shell/Bash + a redirect with
    # >5 chars of extractable content.
    input='{"tool_name":"Bash","tool_input":{"command":"echo hello world from wire > /tmp/wire-out.txt"},"tool_response":{"success":true}}'
  else
    input='{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.txt","content":"hello world"},"tool_response":{"success":true}}'
  fi
  local -a extra_env=()
  case "$mode" in
    env)
      extra_env=(AXONFLOW_USER_TOKEN="$TOKEN")
      ;;
    file)
      mkdir -p "$run_home/.config/axonflow"
      printf '{"token":"%s"}' "$TOKEN" > "$run_home/.config/axonflow/user-token.json"
      chmod 600 "$run_home/.config/axonflow/user-token.json"
      ;;
    none)
      ;;
  esac
  # ${extra_env[@]+...} guards the empty-array expansion under set -u on
  # bash < 4.4 (macOS ships 3.2).
  ( cd "$WORK" && echo "$input" | env -u AXONFLOW_USER_TOKEN HOME="$run_home" AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_AUTH="" \
      AXONFLOW_TELEMETRY=off ${extra_env[@]+"${extra_env[@]}"} "$hook" >"$HOOK_STDOUT" 2>"$HOOK_STDERR" )
  sleep 0.4  # let any backgrounded audit curl flush to the capture log
}

captured_count() { wc -l < "$CAP" | tr -d ' '; }
# every_captured_has_token — ALL captured requests carry X-User-Token == $TOKEN.
every_captured_has_token() {
  local total with_token
  total="$(captured_count)"
  with_token="$(jq -s --arg w "$TOKEN" '[.[] | select((.headers."X-User-Token" // .headers."x-user-token") == $w)] | length' "$CAP")"
  [ "$total" -gt 0 ] && [ "$with_token" = "$total" ]
}
any_captured_has_token_key() {
  jq -e 'select(.headers | (has("X-User-Token") or has("x-user-token")))' "$CAP" >/dev/null 2>&1
}
# rpc_captured_with_token <rpc-id> — that specific request class was captured
# AND carried the token. rpc_captured_tokenless <rpc-id> — captured and did NOT.
rpc_captured_with_token() {
  [ "$(jq -s --arg id "$1" --arg w "$TOKEN" '[.[] | select(.rpc_id == $id and ((.headers."X-User-Token" // .headers."x-user-token") == $w))] | length' "$CAP")" -ge 1 ]
}
rpc_captured_tokenless() {
  [ "$(jq -s --arg id "$1" '[.[] | select(.rpc_id == $id)] | length' "$CAP")" -ge 1 ] \
    && [ "$(jq -s --arg id "$1" '[.[] | select(.rpc_id == $id and (.headers | (has("X-User-Token") or has("x-user-token"))))] | length' "$CAP")" -eq 0 ]
}
no_leak_in_hook_output() {
  ! grep -qF "$TOKEN" "$HOOK_STDOUT" "$HOOK_STDERR" 2>/dev/null
}

echo "== X-User-Token hook wire test (#2943) =="

# --- pre-tool-check.sh: env token, BLOCK decision → check_policy AND the
# backgrounded blocked-audit POST must BOTH carry the token ---
start_server 1
: > "$CAP"
run_hook "$PRE_HOOK" env
if [ "$(captured_count)" -ge 2 ]; then
  pass "pre-tool-check.sh (block path) issued check_policy + audit_tool_call ($(captured_count) requests)"
else
  fail "expected >=2 captured requests on the block path, got $(captured_count)"
fi
if every_captured_has_token; then
  pass "pre-tool-check.sh sends X-User-Token on EVERY governed request (env leg)"
else
  fail "a pre-tool-check.sh request was missing X-User-Token: $(cat "$CAP")"
fi
no_leak_in_hook_output && pass "pre-tool-check.sh never leaks the token to stdout/stderr" \
  || fail "token value leaked into hook stdout/stderr"
# Snapshot the configured run's header-key set (minus the token header) for
# the no-other-drift comparison against the unconfigured run below.
CONFIGURED_KEYS="$(jq -s '[.[] | .headers | keys[]] | unique - ["X-User-Token","x-user-token"] | sort' "$CAP")"

# --- pre-tool-check.sh: 0600 file token ---
: > "$CAP"
run_hook "$PRE_HOOK" file
if every_captured_has_token; then
  pass "pre-tool-check.sh sends X-User-Token from a 0600 user-token.json"
else
  fail "file-leg request missing X-User-Token: $(cat "$CAP")"
fi

# --- pre-tool-check.sh: UNCONFIGURED (the common fleet state) → the header
# must be absent AND the header set must be byte-identical to a pre-#2943
# plugin: no X-User-Token, and no header key beyond the 1.5.x set ---
: > "$CAP"
run_hook "$PRE_HOOK" none
if any_captured_has_token_key; then
  fail "pre-tool-check.sh sent X-User-Token with no token configured: $(cat "$CAP")"
else
  pass "pre-tool-check.sh omits X-User-Token when unconfigured"
fi
UNEXPECTED="$(jq -s '[.[] | .headers | keys[]] | unique - ["Accept","Accept-Encoding","Content-Length","Content-Type","Expect","Host","User-Agent","X-Axonflow-Client","X-License-Token","Authorization"]' "$CAP")"
if [ "$UNEXPECTED" = "[]" ]; then
  pass "unconfigured pre-tool-check.sh header set has no new headers (byte-identical to 1.5.x)"
else
  fail "unconfigured run sent unexpected headers: $UNEXPECTED"
fi
UNCONFIGURED_KEYS="$(jq -s '[.[] | .headers | keys[]] | unique | sort' "$CAP")"
if [ "$CONFIGURED_KEYS" = "$UNCONFIGURED_KEYS" ]; then
  pass "configured header keys == unconfigured keys + X-User-Token only (no other drift)"
else
  fail "header-key drift beyond X-User-Token: configured-minus-token=$CONFIGURED_KEYS unconfigured=$UNCONFIGURED_KEYS"
fi

# --- pre-tool-check.sh: Bash shell-write payload on the ALLOW path → the
# hook-pii check_output scan (the 5th governed curl) fires and must carry the
# token when configured, and omit it when not. This is the one request class
# the Write payload above can never reach — pinned individually via rpc_id so
# a future refactor moving this curl off AUTH_HEADER cannot go uncaught. ---
start_server 0
: > "$CAP"
run_hook "$PRE_HOOK" env bash-redirect
if rpc_captured_with_token "hook-pre" && rpc_captured_with_token "hook-pii"; then
  pass "pre-tool-check.sh shell-write leg: check_policy AND the hook-pii check_output scan both carry X-User-Token (env leg)"
else
  fail "shell-write leg missing X-User-Token on hook-pre/hook-pii: $(cat "$CAP")"
fi
: > "$CAP"
run_hook "$PRE_HOOK" none bash-redirect
if rpc_captured_tokenless "hook-pii"; then
  pass "pre-tool-check.sh hook-pii scan omits X-User-Token when unconfigured"
else
  fail "hook-pii scan absent or sent X-User-Token when unconfigured: $(cat "$CAP")"
fi

# --- post-tool-audit.sh: env token → audit_tool_call + check_output carry it ---
start_server 0
: > "$CAP"
run_hook "$POST_HOOK" env
if [ "$(captured_count)" -ge 2 ] && every_captured_has_token; then
  pass "post-tool-audit.sh sends X-User-Token on every governed request (env leg, $(captured_count) requests)"
else
  fail "post-tool-audit.sh missing X-User-Token (got $(captured_count) requests): $(cat "$CAP")"
fi
no_leak_in_hook_output && pass "post-tool-audit.sh never leaks the token to stdout/stderr" \
  || fail "token value leaked into post-hook stdout/stderr"

# --- post-tool-audit.sh: 0600 file token ---
: > "$CAP"
run_hook "$POST_HOOK" file
if [ "$(captured_count)" -ge 1 ] && every_captured_has_token; then
  pass "post-tool-audit.sh sends X-User-Token from a 0600 user-token.json"
else
  fail "post-tool-audit.sh file leg missing X-User-Token: $(cat "$CAP")"
fi

# --- post-tool-audit.sh: unconfigured → absent ---
: > "$CAP"
run_hook "$POST_HOOK" none
if any_captured_has_token_key; then
  fail "post-tool-audit.sh sent X-User-Token with no token configured: $(cat "$CAP")"
else
  pass "post-tool-audit.sh omits X-User-Token when unconfigured"
fi

# --- world-readable file token → REFUSED on the real hook path, and the
# refusal diagnostic names the file without leaking the value ---
: > "$CAP"
RUN_N=$((RUN_N+1))
BAD_HOME="$WORK/home-$RUN_N"
mkdir -p "$BAD_HOME/.config/axonflow"
printf '{"token":"%s"}' "$TOKEN" > "$BAD_HOME/.config/axonflow/user-token.json"
chmod 644 "$BAD_HOME/.config/axonflow/user-token.json"
( cd "$WORK" && echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.txt","content":"hello"},"tool_response":{"success":true}}' \
  | env -u AXONFLOW_USER_TOKEN HOME="$BAD_HOME" AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_AUTH="" \
      AXONFLOW_TELEMETRY=off "$PRE_HOOK" >"$HOOK_STDOUT" 2>"$HOOK_STDERR" )
sleep 0.4
if any_captured_has_token_key; then
  fail "pre-tool-check.sh used a world-readable user-token.json: $(cat "$CAP")"
else
  pass "pre-tool-check.sh refuses a world-readable (0644) user-token.json"
fi
if grep -q "unsafe permissions" "$HOOK_STDERR" && ! grep -qF "$TOKEN" "$HOOK_STDERR"; then
  pass "0644 refusal diagnostic fires on stderr without leaking the value"
else
  fail "0644 refusal diagnostic missing or leaked the token: $(cat "$HOOK_STDERR")"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
