#!/usr/bin/env bash
# Host-CLI shim test for the Cursor plugin.
#
# Stages the plugin payload as Cursor would, parses .cursor-plugin/plugin.json
# and hooks/hooks.json, and drives the discovered hook scripts via Cursor's
# JSON-on-stdin contract through a full PreToolUse → tool → PostToolUse
# lifecycle. Captures every agent request to a stdlib stub and asserts the
# X-License-Token forwarding contract across Free / Pro-env / Pro-file
# scenarios + the PreToolUse-deny path.
#
# Differences from the Claude shim:
#   - Cursor's hooks.json uses lowercase event names (preToolUse vs Claude's
#     PreToolUse) and flat hook lists (no nested matcher→hooks).
#   - Cursor's deny contract is exit code 2 + stderr message (not JSON
#     hookSpecificOutput).
#   - mcp.json has NO headersHelper today (cursor#43 — sister bug to
#     claude#56). The MCP-forwarding assertion is XFAIL until that lands.
#
# Stdlib-only: bash + curl + jq + python3 stub. No live AxonFlow stack.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH"
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not on PATH"
  exit 0
fi

STAGE_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t host-cli-shim)
LOG_DIR="$STAGE_DIR/.logs"
HOME_DIR="$STAGE_DIR/home"
CAPTURE_FILE="$STAGE_DIR/capture.jsonl"
mkdir -p "$LOG_DIR" "$HOME_DIR/.config/axonflow"
chmod 0700 "$HOME_DIR/.config/axonflow"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { [ -n "${PASS_PRINT:-}" ] && echo "  PASS: $1"; PASS=$((PASS+1)); }
xfail() { echo "  XFAIL (expected, tracked): $1"; }

cleanup() {
  if [ -n "${STUB_PID:-}" ]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Stage the plugin payload
# ---------------------------------------------------------------------------
echo "stage plugin to $STAGE_DIR/plugin"
PLUGIN_STAGE="$STAGE_DIR/plugin"
mkdir -p "$PLUGIN_STAGE/.cursor-plugin" "$PLUGIN_STAGE/hooks" "$PLUGIN_STAGE/scripts"

cp -p "$PLUGIN_DIR/.cursor-plugin/plugin.json" "$PLUGIN_STAGE/.cursor-plugin/" \
  || { fail "missing .cursor-plugin/plugin.json"; exit 1; }
cp -p "$PLUGIN_DIR/mcp.json" "$PLUGIN_STAGE/" \
  || { fail "missing mcp.json"; exit 1; }
cp -p "$PLUGIN_DIR/hooks/hooks.json" "$PLUGIN_STAGE/hooks/" \
  || { fail "missing hooks/hooks.json"; exit 1; }

cp -p "$PLUGIN_DIR/scripts"/*.sh "$PLUGIN_STAGE/scripts/"
chmod +x "$PLUGIN_STAGE/scripts/"*.sh

pass "plugin payload staged"

# ---------------------------------------------------------------------------
# 2. Parse manifests
# ---------------------------------------------------------------------------
PLUGIN_NAME=$(jq -r '.name' "$PLUGIN_STAGE/.cursor-plugin/plugin.json")
[ "$PLUGIN_NAME" = "axonflow" ] && pass "plugin name=axonflow" \
  || fail "plugin name mismatch: got '$PLUGIN_NAME'"

# Cursor's hooks.json uses lowercase event names + flat hook lists.
# Resolve relative ./scripts/ paths against the plugin-root staging dir.
PRE_HOOK_CMD=$(jq -r '.hooks.preToolUse[0].command' "$PLUGIN_STAGE/hooks/hooks.json")
POST_HOOK_CMD=$(jq -r '.hooks.postToolUse[0].command' "$PLUGIN_STAGE/hooks/hooks.json")

PRE_HOOK_RESOLVED="$PLUGIN_STAGE/${PRE_HOOK_CMD#./}"
POST_HOOK_RESOLVED="$PLUGIN_STAGE/${POST_HOOK_CMD#./}"

[ -x "$PRE_HOOK_RESOLVED" ] && pass "preToolUse hook resolves: $(basename "$PRE_HOOK_RESOLVED")" \
  || fail "preToolUse hook not executable at '$PRE_HOOK_RESOLVED'"
[ -x "$POST_HOOK_RESOLVED" ] && pass "postToolUse hook resolves: $(basename "$POST_HOOK_RESOLVED")" \
  || fail "postToolUse hook not executable at '$POST_HOOK_RESOLVED'"

# Cursor's mcp.json today: no headersHelper (cursor#43).
HEADERS_HELPER=$(jq -r '.mcpServers.axonflow.headersHelper // empty' "$PLUGIN_STAGE/mcp.json")

# ---------------------------------------------------------------------------
# 3. Start the capture stub
# ---------------------------------------------------------------------------
STUB_LOG="$LOG_DIR/stub.log"
CAPTURE_FILE="$CAPTURE_FILE" \
  python3 "$SCRIPT_DIR/capture-stub.py" 0 >"$STUB_LOG" 2>&1 &
STUB_PID=$!

PORT=""
for _ in $(seq 1 50); do
  if grep -q '^PORT=' "$STUB_LOG" 2>/dev/null; then
    PORT=$(grep -oE 'PORT=[0-9]+' "$STUB_LOG" | head -1 | cut -d= -f2)
    break
  fi
  sleep 0.1
done
if [ -z "$PORT" ]; then
  fail "capture-stub failed to start"
  cat "$STUB_LOG"
  exit 1
fi
pass "capture-stub listening on 127.0.0.1:$PORT"
ENDPOINT="http://127.0.0.1:$PORT"

curl -sSf -o /dev/null --max-time 2 "$ENDPOINT/health" \
  && pass "stub /health responds" \
  || { fail "stub /health unreachable"; exit 1; }

# ---------------------------------------------------------------------------
# 4. Lifecycle helpers
# ---------------------------------------------------------------------------
reset_captures() { : > "$CAPTURE_FILE"; }

# Cursor pre-tool-check.sh accepts {tool_name, tool_input.command} on stdin
# and returns exit 0 (allow) or exit 2 (deny + stderr message).
# Returns the hook's stderr output.
fire_pretooluse() {
  local statement="${1:-echo benign}"
  local stderr_out
  stderr_out=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$statement\"}}" | \
    HOME="$HOME_DIR" \
    AXONFLOW_ENDPOINT="$ENDPOINT" \
    AXONFLOW_TELEMETRY=off \
    AXONFLOW_LICENSE_TOKEN="${LICENSE_TOKEN:-}" \
    AXONFLOW_AUTH="${AXONFLOW_AUTH:-}" \
    "$PRE_HOOK_RESOLVED" 2>&1 1>/dev/null)
  echo "$stderr_out"
  return 0
}

# Returns the hook's exit code separately so deny-vs-allow is testable.
pretooluse_exit_code() {
  local statement="${1:-echo benign}"
  echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$statement\"}}" | \
    HOME="$HOME_DIR" \
    AXONFLOW_ENDPOINT="$ENDPOINT" \
    AXONFLOW_TELEMETRY=off \
    AXONFLOW_LICENSE_TOKEN="${LICENSE_TOKEN:-}" \
    AXONFLOW_AUTH="${AXONFLOW_AUTH:-}" \
    "$PRE_HOOK_RESOLVED" >/dev/null 2>&1
  echo $?
}

fire_posttooluse() {
  local statement="${1:-echo benign}"
  local stdout="${2:-ok}"
  echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$statement\"},\"tool_response\":{\"stdout\":\"$stdout\",\"exitCode\":0}}" | \
    HOME="$HOME_DIR" \
    AXONFLOW_ENDPOINT="$ENDPOINT" \
    AXONFLOW_TELEMETRY=off \
    AXONFLOW_LICENSE_TOKEN="${LICENSE_TOKEN:-}" \
    AXONFLOW_AUTH="${AXONFLOW_AUTH:-}" \
    "$POST_HOOK_RESOLVED" >/dev/null 2>&1
}

captured_with_license_token() {
  jq -s 'map(select(.headers["x-license-token"] != null)) | length' "$CAPTURE_FILE"
}

# Returns the count of captured requests carrying X-Axonflow-Client (ADR-050 §4).
captured_with_client_header() {
  jq -s 'map(select(.headers["x-axonflow-client"] != null)) | length' "$CAPTURE_FILE"
}

captured_with_tool() {
  local tool="$1"
  jq -s --arg t "$tool" 'map(select(.tool_name == $t)) | length' "$CAPTURE_FILE"
}

# Returns params.arguments.<field> from the first captured audit_tool_call
# request (empty string if none / key absent). Pins the #2912 caller-name
# dual-send payload on the wire: a silent revert of caller_name/tool_type,
# or a callerName-style typo, makes this return "" and fails CI — the
# captured-request COUNT alone (audit_tool_call fired) would still pass.
captured_audit_arg() {
  local field="$1"
  jq -rs --arg f "$field" '
    map(select(.tool_name == "audit_tool_call"))
    | (.[0].body // "{}")
    | (fromjson? // {})
    | (.params.arguments[$f] // "")
  ' "$CAPTURE_FILE"
}

invoke_headers_helper() {
  if [ -z "$HEADERS_HELPER" ]; then
    # mcp.json has no headersHelper — nothing to invoke.
    echo ""
    return
  fi
  CURSOR_PLUGIN_ROOT="$PLUGIN_STAGE" \
  HOME="$HOME_DIR" \
  AXONFLOW_ENDPOINT="$ENDPOINT" \
  AXONFLOW_LICENSE_TOKEN="${LICENSE_TOKEN:-}" \
  AXONFLOW_AUTH="${AXONFLOW_AUTH:-}" \
  bash -c "$HEADERS_HELPER" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 5. Scenario A — Free tier
# ---------------------------------------------------------------------------
echo "--- scenario: Free tier ---"
LICENSE_TOKEN=""
reset_captures
fire_pretooluse "echo benign" >/dev/null
fire_posttooluse "echo benign" "ok"

PRE_REQ_COUNT=$(captured_with_tool "check_policy")
[ "$PRE_REQ_COUNT" -ge 1 ] && pass "Free: preToolUse fired check_policy" \
  || fail "Free: preToolUse did not call check_policy (got $PRE_REQ_COUNT)"

POST_REQ_COUNT=$(captured_with_tool "audit_tool_call")
[ "$POST_REQ_COUNT" -ge 1 ] && pass "Free: postToolUse fired audit_tool_call" \
  || fail "Free: postToolUse did not call audit_tool_call (got $POST_REQ_COUNT)"

# #2912: pin the caller-identity payload the postToolUse audit actually put on
# the wire. Dual-send during the tool_type->caller_name deprecation window:
# caller_name wins on a #2953+ platform, tool_type is the legacy fallback on
# pre-#2953 platforms. Both must be present and equal to the client id.
AUDIT_CALLER_NAME=$(captured_audit_arg "caller_name")
[ "$AUDIT_CALLER_NAME" = "cursor" ] \
  && pass "Free: audit_tool_call carries caller_name=cursor (#2912)" \
  || fail "Free: audit_tool_call caller_name expected 'cursor', got '$AUDIT_CALLER_NAME' (#2912 payload regression)"

AUDIT_TOOL_TYPE=$(captured_audit_arg "tool_type")
[ "$AUDIT_TOOL_TYPE" = "cursor" ] \
  && pass "Free: audit_tool_call carries legacy tool_type=cursor (#2912 dual-send)" \
  || fail "Free: audit_tool_call tool_type expected 'cursor', got '$AUDIT_TOOL_TYPE' (#2912 dual-send regression)"

LIC_COUNT=$(captured_with_license_token)
[ "$LIC_COUNT" -eq 0 ] && pass "Free: NO captured requests carry X-License-Token" \
  || fail "Free: $LIC_COUNT request(s) carried X-License-Token (should be 0)"

# ADR-050 §4: X-Axonflow-Client ships on EVERY request regardless of tier.
CLIENT_COUNT=$(captured_with_client_header)
TOTAL_COUNT_FREE=$(jq -s 'length' "$CAPTURE_FILE")
if [ "$CLIENT_COUNT" -ge 1 ] && [ "$CLIENT_COUNT" -eq "$TOTAL_COUNT_FREE" ]; then
  pass "Free: ALL $TOTAL_COUNT_FREE captured request(s) carry X-Axonflow-Client"
else
  fail "Free: $CLIENT_COUNT of $TOTAL_COUNT_FREE captured requests carried X-Axonflow-Client (expected all)"
fi

# ---------------------------------------------------------------------------
# 6. Scenario B — Pro tier (env)
# ---------------------------------------------------------------------------
echo "--- scenario: Pro tier (env) ---"
LICENSE_TOKEN="AXON-shim-pro-test-token-must-be-32-chars-long-XYZW"
reset_captures
fire_pretooluse "echo benign-pro" >/dev/null
fire_posttooluse "echo benign-pro" "ok"

LIC_COUNT=$(captured_with_license_token)
TOTAL_COUNT=$(jq -s 'length' "$CAPTURE_FILE")
if [ "$LIC_COUNT" -ge 1 ] && [ "$LIC_COUNT" -eq "$TOTAL_COUNT" ]; then
  pass "Pro/env: ALL $TOTAL_COUNT captured request(s) carry X-License-Token"
else
  fail "Pro/env: $LIC_COUNT of $TOTAL_COUNT captured requests carried X-License-Token (expected all)"
fi

# ADR-050 §4: X-Axonflow-Client ships on EVERY request, including Pro/env.
CLIENT_COUNT=$(captured_with_client_header)
if [ "$CLIENT_COUNT" -eq "$TOTAL_COUNT" ]; then
  pass "Pro/env: ALL $TOTAL_COUNT captured request(s) carry X-Axonflow-Client"
else
  fail "Pro/env: $CLIENT_COUNT of $TOTAL_COUNT carried X-Axonflow-Client (expected all)"
fi

TOKEN_OBSERVED=$(jq -s -r '.[0].headers["x-license-token"] // empty' "$CAPTURE_FILE")
[ "$TOKEN_OBSERVED" = "$LICENSE_TOKEN" ] && pass "Pro/env: captured token value matches AXONFLOW_LICENSE_TOKEN" \
  || fail "Pro/env: captured token '$TOKEN_OBSERVED' != env '$LICENSE_TOKEN'"

# Cursor's MCP shape is `{type, url, command, args, env}` only — no
# headersHelper / dynamic-header field is supported by Cursor (verified
# 2026-05-05 by inspecting Cursor.app's main.js binary keys + the docs
# at /Applications/Cursor.app/Contents/Resources/app/out/main.js
# containing none of headersHelper / httpHeaders / requestInit).
# That means MCP-session traffic from Cursor → AxonFlow MCP server
# carries no X-License-Token / X-Axonflow-Client. Pro-tier customers
# using MCP-session paths get Free-tier enforcement until either
# (a) Cursor adds dynamic-header support, or
# (b) we switch to a stdio MCP server that runs as subprocess and
#     can inject headers in the proxy hop.
# Tracked as cursor#43. Marking XFAIL with the accurate framing.
if [ -z "$HEADERS_HELPER" ]; then
  xfail "Pro/env: mcp.json has no headersHelper — Cursor MCP doesn't support that field (cursor#43)"
else
  HEADERS_PRO=$(invoke_headers_helper)
  if echo "$HEADERS_PRO" | jq -e --arg t "$LICENSE_TOKEN" '."X-License-Token" == $t' >/dev/null 2>&1; then
    pass "Pro/env: headersHelper forwards X-License-Token (cursor#43 fixed)"
  else
    xfail "Pro/env: headersHelper drops X-License-Token (cursor#43). got: $HEADERS_PRO"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Scenario C — Pro tier (file)
# ---------------------------------------------------------------------------
echo "--- scenario: Pro tier (file) ---"
LICENSE_TOKEN=""
# Cursor uses a plain-text token file (not wrapped JSON like claude's
# license-token.json). See pre-tool-check.sh:54.
TOKEN_FILE="$HOME_DIR/.config/axonflow/license-token"
TOKEN_VALUE="AXON-shim-pro-file-token-must-be-32-chars-PQRS"
printf '%s' "$TOKEN_VALUE" > "$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
reset_captures

fire_pretooluse "echo file-pro" >/dev/null
fire_posttooluse "echo file-pro" "ok"

LIC_COUNT=$(captured_with_license_token)
TOTAL_COUNT=$(jq -s 'length' "$CAPTURE_FILE")
if [ "$LIC_COUNT" -ge 1 ] && [ "$LIC_COUNT" -eq "$TOTAL_COUNT" ]; then
  pass "Pro/file: ALL $TOTAL_COUNT captured request(s) carry X-License-Token"
else
  fail "Pro/file: $LIC_COUNT of $TOTAL_COUNT captured requests carried X-License-Token (expected all)"
fi

# ADR-050 §4: X-Axonflow-Client ships on EVERY request, including Pro/file.
CLIENT_COUNT=$(captured_with_client_header)
if [ "$CLIENT_COUNT" -eq "$TOTAL_COUNT" ]; then
  pass "Pro/file: ALL $TOTAL_COUNT captured request(s) carry X-Axonflow-Client"
else
  fail "Pro/file: $CLIENT_COUNT of $TOTAL_COUNT carried X-Axonflow-Client (expected all)"
fi

TOKEN_OBSERVED=$(jq -s -r '.[0].headers["x-license-token"] // empty' "$CAPTURE_FILE")
[ "$TOKEN_OBSERVED" = "$TOKEN_VALUE" ] && pass "Pro/file: captured token value matches license-token plain file" \
  || fail "Pro/file: captured token '$TOKEN_OBSERVED' != file '$TOKEN_VALUE'"

# 0644 → refused
chmod 0644 "$TOKEN_FILE"
reset_captures
fire_pretooluse "echo unsafe-perms" >/dev/null
LIC_COUNT=$(captured_with_license_token)
[ "$LIC_COUNT" -eq 0 ] && pass "Pro/file: token file with mode 0644 is refused (no X-License-Token on wire)" \
  || fail "Pro/file: unsafe-perms file STILL forwarded X-License-Token in $LIC_COUNT request(s)"
chmod 0600 "$TOKEN_FILE"

# ---------------------------------------------------------------------------
# 8. Scenario D — preToolUse deny path (Cursor: exit 2 + stderr)
# ---------------------------------------------------------------------------
echo "--- scenario: preToolUse deny path ---"
LICENSE_TOKEN="AXON-shim-pro-deny-token-must-be-32-chars-DENY"
reset_captures

DENY_STDERR=$(fire_pretooluse "deny-me operation")
DENY_EXIT=$(pretooluse_exit_code "deny-me operation")

[ "$DENY_EXIT" = "2" ] && pass "Deny: preToolUse exited 2 (block)" \
  || fail "Deny: preToolUse exit code was $DENY_EXIT (expected 2)"

if echo "$DENY_STDERR" | grep -q "policy violation\|stub-deny"; then
  pass "Deny: preToolUse stderr surfaced block reason"
else
  fail "Deny: preToolUse stderr missing block reason: $DENY_STDERR"
fi

# Background fire-and-forget — poll.
AUDIT_BLOCKED=0
for _ in $(seq 1 30); do
  AUDIT_BLOCKED=$(captured_with_tool "audit_tool_call")
  [ "$AUDIT_BLOCKED" -ge 1 ] && break
  sleep 0.1
done
[ "$AUDIT_BLOCKED" -ge 1 ] && pass "Deny: blocked-attempt audit_tool_call captured" \
  || fail "Deny: blocked attempt did not emit audit_tool_call (got $AUDIT_BLOCKED)"

LIC_COUNT=$(captured_with_license_token)
[ "$LIC_COUNT" -ge 2 ] && pass "Deny: X-License-Token forwarded on both check_policy AND audit_tool_call" \
  || fail "Deny: X-License-Token only on $LIC_COUNT request(s) (expected ≥2)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== host-cli-shim summary (cursor) ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
