#!/usr/bin/env bash
# Runtime proof — the Authorization header the plugin ships in mcp.json
# actually authenticates the MCP server connection against a real self-hosted /
# Enterprise agent. Hits a REAL agent over real HTTP (no mocks).
#
#   The bug: mcp.json set X-Axonflow-Client + X-License-Token but NO
#   Authorization header, so against an Enterprise/in-VPC agent (which requires
#   HTTP Basic auth on every call, incl. the MCP connection) the connection
#   arrived unauthenticated → 401 → Cursor fell into OAuth discovery and died on
#   the agent's "404 page not found", and governed tool calls were blocked.
#
#   The fix: mcp.json adds "Authorization": "Basic ${AXONFLOW_AUTH}". Cursor
#   expands ${AXONFLOW_AUTH} from the launching environment.
#
# This test reconstructs exactly what Cursor sends — it reads the header
# templates straight out of the shipped mcp.json, expands the env vars the same
# way Cursor does, and POSTs `initialize` to the agent's MCP endpoint. It is a
# regression lock on the shipped config: if the Authorization header is ever
# dropped from mcp.json again, the initialize will 401 and this fails.
#
# Run: AXONFLOW_ENDPOINT=http://localhost:8080 \
#      AXONFLOW_AUTH=$(printf '%s:%s' "<org>" "<license>" | base64 | tr -d '\n') \
#      ./test.sh
# Skips cleanly if the agent or a real credential is unavailable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_JSON="$SCRIPT_DIR/../../mcp.json"

: "${AXONFLOW_ENDPOINT:=http://localhost:8080}"
AUTH="${AXONFLOW_AUTH:-}"

if ! command -v jq >/dev/null 2>&1; then echo "SKIP: jq not on PATH"; exit 0; fi
if [ ! -f "$MCP_JSON" ]; then echo "SKIP: mcp.json not found at $MCP_JSON"; exit 0; fi
if ! curl -sSf -o /dev/null --max-time 5 "$AXONFLOW_ENDPOINT/health"; then
  echo "SKIP: agent not reachable at $AXONFLOW_ENDPOINT/health"; exit 0
fi
if [ -z "$AUTH" ]; then
  echo "SKIP: AXONFLOW_AUTH not set — this proof needs a real Enterprise credential, not demo creds"; exit 0
fi

# 1) Regression lock: the shipped mcp.json MUST carry an Authorization header
#    templated on ${AXONFLOW_AUTH}.
AUTH_TMPL=$(jq -r '.mcpServers.axonflow.headers.Authorization // empty' "$MCP_JSON")
if [ -z "$AUTH_TMPL" ]; then
  echo "FAIL: mcp.json has no Authorization header — Enterprise MCP connection will be unauthenticated"
  exit 1
fi
case "$AUTH_TMPL" in
  *'${AXONFLOW_AUTH}'*) echo "PASS: mcp.json Authorization header is templated on \${AXONFLOW_AUTH} ($AUTH_TMPL)";;
  *) echo "FAIL: mcp.json Authorization header is not env-templated: $AUTH_TMPL"; exit 1;;
esac

# 1b) Regression lock (#2943, same pattern as the Authorization lock above):
#     the shipped mcp.json MUST carry an X-User-Token header templated on
#     ${AXONFLOW_USER_TOKEN} — Cursor's static env expansion is the ONLY way
#     the MCP plane gets per-user authorization (no headersHelper, cursor#43).
UT_TMPL=$(jq -r '.mcpServers.axonflow.headers["X-User-Token"] // empty' "$MCP_JSON")
if [ -z "$UT_TMPL" ]; then
  echo "FAIL: mcp.json has no X-User-Token header — MCP plane drops per-user authorization"
  exit 1
fi
case "$UT_TMPL" in
  *'${AXONFLOW_USER_TOKEN}'*) echo "PASS: mcp.json X-User-Token header is templated on \${AXONFLOW_USER_TOKEN} ($UT_TMPL)";;
  *) echo "FAIL: mcp.json X-User-Token header is not env-templated: $UT_TMPL"; exit 1;;
esac

# 2) Expand the header values exactly as Cursor would, from mcp.json + env.
expand() { # $1 = template; substitutes the env vars mcp.json templates on
  printf '%s' "$1" \
    | sed "s|\${AXONFLOW_AUTH}|${AUTH}|g" \
    | sed "s|\${AXONFLOW_LICENSE_TOKEN}|${AXONFLOW_LICENSE_TOKEN:-}|g" \
    | sed "s|\${AXONFLOW_USER_TOKEN}|${AXONFLOW_USER_TOKEN:-}|g"
}
AUTH_HEADER=$(expand "$AUTH_TMPL")
CLIENT_HEADER=$(jq -r '.mcpServers.axonflow.headers["X-Axonflow-Client"] // "cursor-plugin"' "$MCP_JSON")

# 3) The real proof: initialize against the agent with the reconstructed
#    headers MUST succeed (200 + serverInfo), i.e. the shipped config
#    authenticates on an Enterprise agent.
BODY=$(mktemp)
CODE=$(curl -s -m 10 -o "$BODY" -w '%{http_code}' -X POST "${AXONFLOW_ENDPOINT}/api/v1/mcp-server" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H "Authorization: $AUTH_HEADER" -H "X-Axonflow-Client: $CLIENT_HEADER" \
  -d '{"jsonrpc":"2.0","id":"init","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"cursor","version":"1"}}}')

if [ "$CODE" = "200" ] && jq -e '.result.serverInfo' "$BODY" >/dev/null 2>&1; then
  echo "PASS: initialize with the shipped mcp.json header set returned 200 + serverInfo (authenticated)"
  rm -f "$BODY"
else
  echo "FAIL: initialize returned HTTP $CODE: $(head -c 200 "$BODY")"
  rm -f "$BODY"; exit 1
fi

# 4) X-User-Token MCP-plane legs (#2943). Cursor sends the header exactly as
#    the env expands it — including an EMPTY value when AXONFLOW_USER_TOKEN
#    is unset. Reconstruct all three states and assert the live agent's
#    behavior explicitly (never pass on a transport error: the code must be
#    the exact expected HTTP status).
#
# mcp_init <x-user-token-value|__EMPTY__> — POST initialize with the shipped
# header set plus X-User-Token; prints the HTTP code. curl's `-H "Name;"`
# form sends the header with an empty value — exactly what Cursor's env
# expansion produces for an unset var.
mcp_init_with_user_token() {
  local ut="$1"
  local -a ut_header
  if [ "$ut" = "__EMPTY__" ]; then
    ut_header=(-H "X-User-Token;")
  else
    ut_header=(-H "X-User-Token: $ut")
  fi
  curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST "${AXONFLOW_ENDPOINT}/api/v1/mcp-server" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H "Authorization: $AUTH_HEADER" -H "X-Axonflow-Client: $CLIENT_HEADER" \
    "${ut_header[@]}" \
    -d '{"jsonrpc":"2.0","id":"init-ut","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"cursor","version":"1"}}}'
}

# 4a) Env unset → the template expands to an EMPTY header value; the platform
#     treats empty as absent (strings.TrimSpace in extractPerUserToken) and
#     the connection must still authenticate. This is every unconfigured
#     Cursor user after this change — it can never regress to a 401.
EXPANDED_EMPTY="$( (unset AXONFLOW_USER_TOKEN; expand "$UT_TMPL") )"
if [ -n "$EXPANDED_EMPTY" ]; then
  echo "FAIL: X-User-Token template expanded non-empty with the env unset: '$EXPANDED_EMPTY'"
  exit 1
fi
CODE=$(mcp_init_with_user_token "__EMPTY__")
if [ "$CODE" = "200" ]; then
  echo "PASS: empty X-User-Token (unset env, as Cursor expands it) → HTTP 200 (treated as absent)"
else
  echo "FAIL: empty X-User-Token returned HTTP $CODE (expected 200 — unconfigured users would be locked out)"
  exit 1
fi

# 4b/4c) Real vs tampered token — need a platform that validates X-User-Token
#     (enterprise#2929+) and mint material. Probe with a garbage token: a
#     pre-#2929 platform ignores the header (200) → SKIP these legs.
PROBE=$(mcp_init_with_user_token "e2e-garbage-token-probe")
if [ "$PROBE" != "401" ]; then
  echo "SKIP: platform does not validate X-User-Token (probe HTTP $PROBE; needs enterprise#2929+) — real/tampered token legs skipped"
else
  UT_TOKEN="${AXONFLOW_E2E_USER_TOKEN:-}"
  if [ -z "$UT_TOKEN" ] && [ -n "${AXONFLOW_E2E_JWT_SECRET:-}" ] && [ -n "${AXONFLOW_E2E_ORG_ID:-}" ] && command -v python3 >/dev/null 2>&1; then
    # Sign a token with the agent's JWT_SECRET using the exact mint-API claims
    # contract — the platform runs its FULL validation against it (signature,
    # issuer, expiry, org binding, revocation); nothing is stubbed.
    UT_TOKEN=$(TOKEN_EMAIL="e2e-mcp-plane-$(date +%s)@example.com" ORG_ID="$AXONFLOW_E2E_ORG_ID" JWT_SECRET="$AXONFLOW_E2E_JWT_SECRET" python3 - <<'PY'
import base64, hashlib, hmac, json, os, time, uuid
def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
now = int(time.time())
claims = {"iss": "axonflow-user-token-mint", "email": os.environ["TOKEN_EMAIL"],
          "role": "developer", "org_id": os.environ["ORG_ID"],
          "jti": str(uuid.uuid4()), "iat": now, "exp": now + 3600}
si = b64url(json.dumps({"alg":"HS256","typ":"JWT"}, separators=(",", ":")).encode()) + "." + \
     b64url(json.dumps(claims, separators=(",", ":")).encode())
sig = hmac.new(os.environ["JWT_SECRET"].encode(), si.encode(), hashlib.sha256).digest()
print(si + "." + b64url(sig))
PY
)
  fi
  if [ -z "$UT_TOKEN" ]; then
    echo "SKIP: no minted token (set AXONFLOW_E2E_USER_TOKEN, or AXONFLOW_E2E_JWT_SECRET+AXONFLOW_E2E_ORG_ID) — real/tampered token legs skipped"
  else
    # 4b) Real minted token, expanded exactly as Cursor would → 200.
    EXPANDED_UT="$(AXONFLOW_USER_TOKEN="$UT_TOKEN" expand "$UT_TMPL")"
    CODE=$(mcp_init_with_user_token "$EXPANDED_UT")
    if [ "$CODE" = "200" ]; then
      echo "PASS: real minted X-User-Token via the mcp.json template → HTTP 200 (per-user identity accepted)"
    else
      echo "FAIL: real minted X-User-Token returned HTTP $CODE (expected 200)"
      exit 1
    fi
    # 4c) Tampered token (bit-flipped signature) → EXPLICIT 401 (fail-closed).
    case "$UT_TOKEN" in
      *x) TAMPERED="${UT_TOKEN%?}A" ;;
      *)  TAMPERED="${UT_TOKEN%?}x" ;;
    esac
    CODE=$(mcp_init_with_user_token "$TAMPERED")
    if [ "$CODE" = "401" ]; then
      echo "PASS: tampered X-User-Token → HTTP 401 (fail-closed; not a transport error)"
    else
      echo "FAIL: tampered X-User-Token returned HTTP $CODE (expected exactly 401)"
      exit 1
    fi
  fi
fi

echo ""; echo "PASS: mcp-enterprise-auth (shipped mcp.json Authorization header authenticates the MCP connection; X-User-Token template behaves per #2943 on the live agent)"
