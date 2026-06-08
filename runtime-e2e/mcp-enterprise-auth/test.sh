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

# 2) Expand the header values exactly as Cursor would, from mcp.json + env.
expand() { # $1 = template; substitutes ${AXONFLOW_AUTH}/${AXONFLOW_LICENSE_TOKEN}
  printf '%s' "$1" \
    | sed "s|\${AXONFLOW_AUTH}|${AUTH}|g" \
    | sed "s|\${AXONFLOW_LICENSE_TOKEN}|${AXONFLOW_LICENSE_TOKEN:-}|g"
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

echo ""; echo "PASS: mcp-enterprise-auth (shipped mcp.json Authorization header authenticates the MCP connection)"
