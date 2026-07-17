#!/usr/bin/env bash
# mcp.json ↔ plugin.json alignment gate (axonflow-enterprise#2943).
#
# Cursor's MCP connection uses mcp.json's STATIC headers (no headersHelper —
# cursor#43), so the X-Axonflow-Client value there is a hardcoded literal
# that CAN drift from the canonical plugin version. It did: mcp.json shipped
# `cursor-plugin/1.3.0` while plugin.json said 1.5.3 — every MCP-connection
# request misreported the plugin version to the platform's per-client
# version telemetry (same class as the Claude Code plugin's on-wire version
# bug). This gate locks mcp.json's literal to plugin.json so the drift
# cannot recur, and pins the X-User-Token env template (regression lock,
# same pattern as runtime-e2e/mcp-enterprise-auth's Authorization lock).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH"
  exit 0
fi

echo "== mcp.json ↔ plugin.json alignment =="

PLUGIN_VERSION="$(jq -r '.version // empty' "$ROOT/.cursor-plugin/plugin.json")"
if [ -n "$PLUGIN_VERSION" ]; then
  pass "plugin.json declares version $PLUGIN_VERSION"
else
  fail "plugin.json has no .version"
fi

MCP_CLIENT="$(jq -r '.mcpServers.axonflow.headers["X-Axonflow-Client"] // empty' "$ROOT/mcp.json")"
if [ "$MCP_CLIENT" = "cursor-plugin/$PLUGIN_VERSION" ]; then
  pass "mcp.json X-Axonflow-Client ($MCP_CLIENT) matches plugin.json version"
else
  fail "mcp.json X-Axonflow-Client is '$MCP_CLIENT' but plugin.json says $PLUGIN_VERSION — the MCP plane would misreport the plugin version on the wire"
fi

# X-User-Token env template must exist (per-user authorization, #2943). An
# unset env var expands to an empty header value, which the platform treats
# as absent — safe for unconfigured users.
UT_TMPL="$(jq -r '.mcpServers.axonflow.headers["X-User-Token"] // empty' "$ROOT/mcp.json")"
if [ "$UT_TMPL" = '${AXONFLOW_USER_TOKEN}' ]; then
  pass "mcp.json X-User-Token header is templated on \${AXONFLOW_USER_TOKEN}"
else
  fail "mcp.json X-User-Token template missing or wrong: '$UT_TMPL' — the MCP plane would drop per-user authorization"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
