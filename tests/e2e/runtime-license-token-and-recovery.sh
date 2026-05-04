#!/usr/bin/env bash
# Runtime E2E for the V1 paid-tier wire-up (W4) — exercises both halves
# of platform PR #1850 from the plugin side:
#
#   1. X-License-Token wiring. Drives pre-tool-check.sh and post-tool-audit.sh
#      against a captured-request HTTP server and asserts the AXON-prefixed
#      token is forwarded as an X-License-Token header on every governed
#      agent call. Mocks the agent transport, NOT the plugin scripts —
#      the request that hits the wire is the request the agent would see.
#
#   2. Recovery surface. Drives scripts/recover-credentials.sh against the
#      same captured-request server, asserting the right HTTP shape is
#      sent to /api/v1/recover and /api/v1/recover/verify, and that the
#      returned credentials land in ~/.config/axonflow/try-registration.json
#      with the correct file mode.
#
# Why a captured-request server instead of a live stack:
#   - PR audit gate calls the plugin "user-facing", which means we need a
#     runtime-path test (not a mock-only unit test). The path that matters
#     is the plugin shell scripts -> outbound HTTP. We capture at the
#     wire boundary so we can assert what would have hit a real agent.
#   - The runtime-e2e/ directory (the cursor-gate manual runbook surface)
#     is for IDE-mediated features that Cursor cannot automate today.
#     Hook scripts and CLI helpers are NOT IDE-mediated — they're shell
#     processes the plugin invokes directly, which we can drive end-to-end
#     in CI without a live Cursor window.
#   - The full stack-against-Postgres flow is covered by
#     axonflow-enterprise/runtime-e2e/v1_paid_tier/test.sh on the platform
#     side. This test focuses on the plugin's contribution: sending the
#     header, persisting the recovered credentials, and surfacing tier
#     state to the user.
#
# Usage:
#   ./tests/e2e/runtime-license-token-and-recovery.sh
#   AGENT_URL=http://localhost:8080 ./tests/e2e/runtime-license-token-and-recovery.sh

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t v1-paid-runtime)
LOG_DIR="$STAGE_DIR/.logs"
mkdir -p "$LOG_DIR"

# Use a private XDG-style HOME so the test can write a real
# ~/.config/axonflow/license-token without trampling the developer's actual
# credentials. The plugin scripts read $HOME, so re-pointing it scopes
# every file write to the temp dir.
export HOME="$STAGE_DIR/home"
mkdir -p "$HOME"

# Disable telemetry + Community-SaaS auto-bootstrap during the test so the
# only outbound HTTP we see is the test-driven calls. Without this, the
# pre-tool-check hook would also try to register against try.getaxonflow.com.
export AXONFLOW_TELEMETRY=off
export DO_NOT_TRACK=1

# shellcheck disable=SC2329 # invoked indirectly by `trap cleanup EXIT` below
cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }

# ---------- Captured-request server ----------
# Records every inbound POST: path, headers, body. Returns canned
# responses keyed off path so the plugin scripts behave normally.
CAPTURE_FILE="$STAGE_DIR/requests.jsonl"
SERVER_PY="$STAGE_DIR/server.py"
SERVER_LOG="$LOG_DIR/server.log"

cat <<'PYEOF' > "$SERVER_PY"
import json, os, sys, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

CAPTURE_FILE = os.environ["CAPTURE_FILE"]

# Canonical responses the plugin scripts expect. Keep them minimal — the
# pre-tool-check hook only reads .result.content[0].text and parses it as
# JSON. The recover handlers need 202 (request) and a credentials envelope
# (verify).
def mcp_envelope(req_id, body):
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {"content": [{"type": "text", "text": json.dumps(body)}]},
    }

ALLOW_BODY = {"allowed": True, "policies_evaluated": 1, "decision_id": "dec_runtime_allow_001"}

class H(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _record(self, body_bytes):
        rec = {
            "method": self.command,
            "path": self.path,
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "body": body_bytes.decode("utf-8", errors="replace") if body_bytes else "",
        }
        with open(CAPTURE_FILE, "a") as f:
            f.write(json.dumps(rec) + "\n")

    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        raw = self.rfile.read(length) if length else b""
        self._record(raw)

        if self.path == "/api/v1/mcp-server":
            try:
                req = json.loads(raw or b"{}")
            except json.JSONDecodeError:
                req = {}
            envelope = mcp_envelope(req.get("id"), ALLOW_BODY)
            payload = json.dumps(envelope).encode("utf-8")
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        if self.path == "/api/v1/recover":
            # Anti-enumeration: always 202.
            self.send_response(202)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", "2")
            self.end_headers()
            self.wfile.write(b"{}")
            return

        if self.path == "/api/v1/recover/verify":
            try:
                req = json.loads(raw or b"{}")
            except json.JSONDecodeError:
                req = {}
            tok = req.get("token", "")
            # Reject any token starting with the literal hex sentinel
            # "dead0000" — lets the test simulate a consumed/expired token
            # that the server rejects with 401, while still using a valid
            # hex token shape (so the script's hex-stripping doesn't
            # swallow non-hex chars before the request even goes out).
            if not tok or tok.startswith("dead0000"):
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'{"error":"invalid_token"}')
                return
            body = {
                "tenant_id": "cs_runtime_test_tenant",
                "secret": "runtime_test_secret_value_unique_001",
                "secret_prefix": "runtime_t",
                "expires_at": "2099-01-01T00:00:00Z",
                "endpoint": "https://try.getaxonflow.com",
                "email": req.get("email", "captured@axonflow-test.invalid"),
                "note": "runtime-e2e capture",
            }
            payload = json.dumps(body).encode("utf-8")
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        self.send_response(404)
        self.end_headers()

def main():
    open(CAPTURE_FILE, "w").close()
    httpd = HTTPServer(("127.0.0.1", 0), H)
    print(f"PORT={httpd.server_address[1]}", flush=True)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    threading.Event().wait()

if __name__ == "__main__":
    main()
PYEOF

CAPTURE_FILE="$CAPTURE_FILE" python3 "$SERVER_PY" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

# Wait up to 5s for PORT= line.
PORT=""
for _ in $(seq 1 50); do
  PORT=$(grep -oE 'PORT=[0-9]+' "$SERVER_LOG" 2>/dev/null | head -1 | cut -d= -f2)
  [ -n "$PORT" ] && break
  sleep 0.1
done
if [ -z "$PORT" ]; then
  echo "FATAL: capture server failed to start"
  cat "$SERVER_LOG"
  exit 1
fi
ENDPOINT="http://127.0.0.1:$PORT"
echo "Capture server ready at $ENDPOINT"
echo

# Helper: count captured requests with a given header value substring.
count_with_header() {
  local header_substring="$1"
  jq -c 'select(.headers | to_entries | map(.key + ": " + .value) | join("\n") | contains("'"$header_substring"'"))' \
    < "$CAPTURE_FILE" 2>/dev/null | wc -l | tr -d ' '
}
# Helper: count captured requests on a given path.
count_on_path() {
  local p="$1"
  jq -c 'select(.path == "'"$p"'")' < "$CAPTURE_FILE" 2>/dev/null | wc -l | tr -d ' '
}

# ============================================================================
# Part 1 — X-License-Token wiring
# ============================================================================
echo "=== Part 1: X-License-Token wiring ==="

# Reset capture between parts so each section's assertions are scoped.
truncate -s 0 "$CAPTURE_FILE"

# 1.1 — pre-tool-check.sh WITHOUT a token.
echo "  1.1 pre-tool-check without AXONFLOW_LICENSE_TOKEN (free tier baseline)"
NO_TOKEN_INPUT='{"tool_name":"Bash","tool_input":{"command":"echo benign"}}'
NO_TOKEN_STDERR=$(echo "$NO_TOKEN_INPUT" | \
  AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_TELEMETRY=off DO_NOT_TRACK=1 \
  bash "$PLUGIN_DIR/scripts/pre-tool-check.sh" 2>&1 1>/dev/null)
NO_TOKEN_REQUESTS_WITH_HEADER=$(count_with_header "x-license-token:")
if [ "$NO_TOKEN_REQUESTS_WITH_HEADER" = "0" ]; then
  pass "free-tier path sends no X-License-Token header"
else
  fail "free-tier path leaked $NO_TOKEN_REQUESTS_WITH_HEADER X-License-Token header(s)"
fi
if echo "$NO_TOKEN_STDERR" | grep -q "Pro tier active"; then
  fail "free-tier canary should NOT advertise 'Pro tier active'"
else
  pass "free-tier canary correctly omits 'Pro tier active'"
fi

# 1.2 — pre-tool-check.sh WITH AXONFLOW_LICENSE_TOKEN env var.
echo "  1.2 pre-tool-check with AXONFLOW_LICENSE_TOKEN env"
truncate -s 0 "$CAPTURE_FILE"
TEST_TOKEN="AXON-runtimeenv1.runtimeenv1.runtimeenv1"
ENV_STDERR=$(echo "$NO_TOKEN_INPUT" | \
  AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_LICENSE_TOKEN="$TEST_TOKEN" \
  AXONFLOW_TELEMETRY=off DO_NOT_TRACK=1 \
  bash "$PLUGIN_DIR/scripts/pre-tool-check.sh" 2>&1 1>/dev/null)
ENV_REQUESTS_WITH_HEADER=$(count_with_header "x-license-token: $TEST_TOKEN")
if [ "$ENV_REQUESTS_WITH_HEADER" -ge "1" ]; then
  pass "env-sourced license token forwarded as X-License-Token (count=$ENV_REQUESTS_WITH_HEADER)"
else
  fail "env-sourced license token did NOT reach the wire (count=0)"
  echo "    captured headers:"
  jq -c '.headers' < "$CAPTURE_FILE" | sed 's/^/      /'
fi
if echo "$ENV_STDERR" | grep -q "Pro tier active"; then
  pass "Pro-tier canary surfaced on stderr"
else
  fail "Pro-tier canary missing from stderr"
  echo "    stderr: $ENV_STDERR"
fi

# 1.3 — pre-tool-check.sh with a token persisted in plugin config (the
# natural Cursor surface — we discovered the existing 0700 ~/.config/axonflow
# directory and the 0600 try-registration.json convention; persist the
# license-token alongside it).
echo "  1.3 pre-tool-check with token persisted in ~/.config/axonflow/license-token"
truncate -s 0 "$CAPTURE_FILE"
mkdir -p "$HOME/.config/axonflow"
chmod 0700 "$HOME/.config/axonflow"
FILE_TOKEN="AXON-runtimefile1.runtimefile1.runtimefile1"
echo -n "$FILE_TOKEN" > "$HOME/.config/axonflow/license-token"
chmod 0600 "$HOME/.config/axonflow/license-token"
FILE_STDERR=$(echo "$NO_TOKEN_INPUT" | \
  AXONFLOW_ENDPOINT="$ENDPOINT" \
  AXONFLOW_TELEMETRY=off DO_NOT_TRACK=1 \
  bash "$PLUGIN_DIR/scripts/pre-tool-check.sh" 2>&1 1>/dev/null)
FILE_REQUESTS_WITH_HEADER=$(count_with_header "x-license-token: $FILE_TOKEN")
if [ "$FILE_REQUESTS_WITH_HEADER" -ge "1" ]; then
  pass "file-sourced license token forwarded as X-License-Token (count=$FILE_REQUESTS_WITH_HEADER)"
else
  fail "file-sourced license token did NOT reach the wire"
  echo "    captured: $(jq -c '.headers' < "$CAPTURE_FILE")"
fi
if echo "$FILE_STDERR" | grep -q "Pro tier active"; then
  pass "Pro-tier canary surfaced when token came from file"
else
  fail "Pro-tier canary missing when token came from file"
fi

# 1.4 — env wins over file when both are set.
echo "  1.4 env-supplied token wins over file-supplied token"
truncate -s 0 "$CAPTURE_FILE"
echo "$NO_TOKEN_INPUT" | \
  AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_LICENSE_TOKEN="$TEST_TOKEN" \
  AXONFLOW_TELEMETRY=off DO_NOT_TRACK=1 \
  bash "$PLUGIN_DIR/scripts/pre-tool-check.sh" >/dev/null 2>&1
ENV_WINS=$(count_with_header "x-license-token: $TEST_TOKEN")
FILE_LEAKED=$(count_with_header "x-license-token: $FILE_TOKEN")
if [ "$ENV_WINS" -ge "1" ] && [ "$FILE_LEAKED" = "0" ]; then
  pass "env token wins (env count=$ENV_WINS, file leak=$FILE_LEAKED)"
else
  fail "env-vs-file precedence broken (env=$ENV_WINS, file=$FILE_LEAKED)"
fi

# 1.5 — file with unsafe (0644) permissions is refused.
echo "  1.5 file with unsafe permissions (0644) is refused, not loaded"
truncate -s 0 "$CAPTURE_FILE"
chmod 0644 "$HOME/.config/axonflow/license-token"
UNSAFE_STDERR=$(echo "$NO_TOKEN_INPUT" | \
  AXONFLOW_ENDPOINT="$ENDPOINT" \
  AXONFLOW_TELEMETRY=off DO_NOT_TRACK=1 \
  bash "$PLUGIN_DIR/scripts/pre-tool-check.sh" 2>&1 1>/dev/null)
UNSAFE_HEADER_LEAK=$(count_with_header "x-license-token:")
if [ "$UNSAFE_HEADER_LEAK" = "0" ]; then
  pass "unsafe-mode file not loaded (no X-License-Token sent)"
else
  fail "unsafe-mode file was loaded anyway (count=$UNSAFE_HEADER_LEAK)"
fi
if echo "$UNSAFE_STDERR" | grep -q "unsafe permissions"; then
  pass "unsafe-mode file produced clear stderr warning"
else
  fail "unsafe-mode file silently ignored — no warning"
fi
# Restore for downstream tests.
chmod 0600 "$HOME/.config/axonflow/license-token"

# 1.6 — post-tool-audit.sh also forwards the header.
echo "  1.6 post-tool-audit.sh forwards X-License-Token (audit must be tier-aware too)"
truncate -s 0 "$CAPTURE_FILE"
POST_INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_response":{"stdout":"hi","exitCode":0}}'
echo "$POST_INPUT" | \
  AXONFLOW_ENDPOINT="$ENDPOINT" AXONFLOW_LICENSE_TOKEN="$TEST_TOKEN" \
  AXONFLOW_TELEMETRY=off DO_NOT_TRACK=1 \
  bash "$PLUGIN_DIR/scripts/post-tool-audit.sh" >/dev/null 2>&1
# post-tool-audit fires the audit write in the background; give it a moment.
sleep 0.5
POST_REQUESTS_WITH_HEADER=$(count_with_header "x-license-token: $TEST_TOKEN")
if [ "$POST_REQUESTS_WITH_HEADER" -ge "1" ]; then
  pass "post-tool-audit forwarded X-License-Token (count=$POST_REQUESTS_WITH_HEADER)"
else
  fail "post-tool-audit did NOT forward X-License-Token"
  echo "    captured: $(jq -c '.headers' < "$CAPTURE_FILE")"
fi

# Tear down the file token so Part 2 starts from a clean state.
rm -f "$HOME/.config/axonflow/license-token"

# ============================================================================
# Part 2 — Recovery surface
# ============================================================================
echo
echo "=== Part 2: recovery surface (scripts/recover-credentials.sh) ==="
truncate -s 0 "$CAPTURE_FILE"

# 2.1 — happy path: drive recover with stubbed email + token via env.
echo "  2.1 happy-path recovery via env (no tty needed)"
RECOVER_EMAIL="runtime-recover@axonflow-test.invalid"
RECOVER_TOKEN="abcdef0123456789abcdef0123456789abcdef01"
RECOVER_STDOUT=$(AXONFLOW_ENDPOINT="$ENDPOINT" \
  AXONFLOW_RECOVER_EMAIL="$RECOVER_EMAIL" \
  AXONFLOW_RECOVER_TOKEN="$RECOVER_TOKEN" \
  bash "$PLUGIN_DIR/scripts/recover-credentials.sh" 2>"$LOG_DIR/recover.err")
RECOVER_EXIT=$?
if [ "$RECOVER_EXIT" = "0" ]; then
  pass "recover-credentials.sh exited 0"
else
  fail "recover-credentials.sh exited $RECOVER_EXIT"
  echo "    stderr: $(cat "$LOG_DIR/recover.err")"
fi
if [ "$RECOVER_STDOUT" = "cs_runtime_test_tenant" ]; then
  pass "stdout = recovered tenant_id (callable as \$(./recover-credentials.sh))"
else
  fail "stdout was '$RECOVER_STDOUT', expected 'cs_runtime_test_tenant'"
fi

# 2.2 — POST /api/v1/recover was called with the right email.
RECOVER_POST_COUNT=$(count_on_path "/api/v1/recover")
if [ "$RECOVER_POST_COUNT" = "1" ]; then
  pass "POST /api/v1/recover called exactly once"
else
  fail "expected 1 POST /api/v1/recover, got $RECOVER_POST_COUNT"
fi
RECOVER_BODY=$(jq -r 'select(.path == "/api/v1/recover") | .body' < "$CAPTURE_FILE" | head -1)
if echo "$RECOVER_BODY" | jq -e --arg e "$RECOVER_EMAIL" '.email == $e' >/dev/null 2>&1; then
  pass "POST /api/v1/recover body has the right email"
else
  fail "POST /api/v1/recover body wrong: $RECOVER_BODY"
fi

# 2.3 — POST /api/v1/recover/verify was called with the right token.
VERIFY_POST_COUNT=$(count_on_path "/api/v1/recover/verify")
if [ "$VERIFY_POST_COUNT" = "1" ]; then
  pass "POST /api/v1/recover/verify called exactly once"
else
  fail "expected 1 POST /api/v1/recover/verify, got $VERIFY_POST_COUNT"
fi
VERIFY_BODY=$(jq -r 'select(.path == "/api/v1/recover/verify") | .body' < "$CAPTURE_FILE" | head -1)
if echo "$VERIFY_BODY" | jq -e --arg t "$RECOVER_TOKEN" '.token == $t' >/dev/null 2>&1; then
  pass "POST /api/v1/recover/verify body has the right token"
else
  fail "POST /api/v1/recover/verify body wrong: $VERIFY_BODY"
fi

# 2.4 — credentials persisted to the right file with the right mode.
REG="$HOME/.config/axonflow/try-registration.json"
if [ -f "$REG" ]; then
  pass "try-registration.json was written"
else
  fail "try-registration.json was NOT written"
fi
REG_MODE=$(stat -f %Lp "$REG" 2>/dev/null || stat -c %a "$REG" 2>/dev/null)
if [ "$REG_MODE" = "600" ]; then
  pass "try-registration.json has mode 0600"
else
  fail "try-registration.json mode is $REG_MODE, expected 600"
fi
PERSISTED_TENANT=$(jq -r '.tenant_id // empty' < "$REG" 2>/dev/null)
if [ "$PERSISTED_TENANT" = "cs_runtime_test_tenant" ]; then
  pass "persisted tenant_id matches verify response"
else
  fail "persisted tenant_id was '$PERSISTED_TENANT', expected 'cs_runtime_test_tenant'"
fi

# 2.5 — accept the full magic-link URL too (not just the bare token).
echo "  2.5 magic-link URL form is accepted (not just bare token)"
truncate -s 0 "$CAPTURE_FILE"
URL_TOKEN="cafebabe1234567890abcdef0987654321abcdef"
MAGIC_LINK="https://try.getaxonflow.com/api/v1/recover/verify?token=$URL_TOKEN"
AXONFLOW_ENDPOINT="$ENDPOINT" \
  AXONFLOW_RECOVER_EMAIL="$RECOVER_EMAIL" \
  AXONFLOW_RECOVER_TOKEN="$MAGIC_LINK" \
  bash "$PLUGIN_DIR/scripts/recover-credentials.sh" >/dev/null 2>"$LOG_DIR/recover-url.err"
URL_VERIFY_BODY=$(jq -r 'select(.path == "/api/v1/recover/verify") | .body' < "$CAPTURE_FILE" | head -1)
if echo "$URL_VERIFY_BODY" | jq -e --arg t "$URL_TOKEN" '.token == $t' >/dev/null 2>&1; then
  pass "URL form: token extracted from query string"
else
  fail "URL form: token extraction failed (sent body: $URL_VERIFY_BODY)"
fi

# 2.6 — server-side rejection (expired/used token) surfaces non-zero exit.
# Use a valid-shape hex token starting with the dead0000 sentinel the stub
# server is wired to reject — same path a real server would take for a
# consumed-once or expired token.
echo "  2.6 expired/used token surfaces a clear failure"
truncate -s 0 "$CAPTURE_FILE"
EXPIRED_OUTPUT=$(AXONFLOW_ENDPOINT="$ENDPOINT" \
  AXONFLOW_RECOVER_EMAIL="$RECOVER_EMAIL" \
  AXONFLOW_RECOVER_TOKEN="dead000011112222333344445555666677778888" \
  bash "$PLUGIN_DIR/scripts/recover-credentials.sh" 2>&1 1>/dev/null)
EXPIRED_EXIT=$?
if [ "$EXPIRED_EXIT" != "0" ]; then
  pass "expired-token path exited non-zero ($EXPIRED_EXIT)"
else
  fail "expired-token path exited 0 — should fail"
fi
if echo "$EXPIRED_OUTPUT" | grep -q "verify failed with HTTP 401"; then
  pass "expired-token path surfaced clear HTTP-401 error message"
else
  fail "expired-token path missing HTTP-401 message"
  echo "    output: $EXPIRED_OUTPUT"
fi

# ============================================================================
# Summary
# ============================================================================
echo
echo "Pass: $PASS"
echo "Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "FAIL: $FAIL assertion(s) failed — see above"
  exit 1
fi
echo
echo "PASS: V1 paid-tier wire-up runtime test — X-License-Token + recovery surface verified end-to-end"
exit 0
