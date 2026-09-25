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

# ADR-065 capability handshake (#95). The shipped template must carry NO
# X-Axonflow-PEP-Handshake line: Cursor expands an unset variable to an EMPTY
# header value, and a handshake header present and empty is malformed, which
# the platform refuses (measured on AxonFlow v11.0.0: HTTP 400, -32600
# pep_handshake_malformed). scripts/configure-mcp-handshake.sh writes the
# header only when AXONFLOW_PEP_AUDIENCE is set.
echo ""
echo "== mcp.json handshake: never an unconditional line =="
if jq -e '.mcpServers.axonflow.headers | has("X-Axonflow-PEP-Handshake")' "$ROOT/mcp.json" >/dev/null; then
  fail "the shipped mcp.json carries an X-Axonflow-PEP-Handshake header: every install without an audience would send it empty and be refused"
else
  pass "the shipped mcp.json carries no X-Axonflow-PEP-Handshake header"
fi
if grep -q 'PEP_HANDSHAKE\|PEP_AUDIENCE' "$ROOT/mcp.json"; then
  fail "the shipped mcp.json references the handshake or audience variable"
else
  pass "the shipped mcp.json references no handshake or audience variable"
fi

WRITER="$ROOT/scripts/configure-mcp-handshake.sh"
# The platform's own encoder's bytes for audience axonflow-decision-proof
# (the golden runtime-e2e/pep_capability_handshake/test.sh asserts).
GOLDEN="eyJwcm9maWxlX3ZlcnNpb24iOjEsInBlcF9pZCI6ImN1cnNvci1wbHVnaW4iLCJhdWRpZW5jZSI6ImF4b25mbG93LWRlY2lzaW9uLXByb29mIiwiY2FwYWJpbGl0aWVzIjpbXX0"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/mcp.json" "$TMP/mcp.json"
SHIPPED=$(jq -S . "$ROOT/mcp.json")
header_of() { jq -r '.mcpServers.axonflow.headers["X-Axonflow-PEP-Handshake"] // "<absent>"' "$1"; }

env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=axonflow-decision-proof bash "$WRITER" "$TMP/mcp.json" >/dev/null 2>&1
rc=$?
if [ "$rc" = 0 ] && [ "$(header_of "$TMP/mcp.json")" = "$GOLDEN" ]; then
  pass "audience set: the writer adds the header with the platform encoder's bytes"
else
  fail "audience set: rc=$rc, header '$(header_of "$TMP/mcp.json")'"
fi
if [ "$(jq -S 'del(.mcpServers.axonflow.headers["X-Axonflow-PEP-Handshake"])' "$TMP/mcp.json")" = "$SHIPPED" ]; then
  pass "audience set: every other key of mcp.json is unchanged"
else
  fail "audience set: the writer changed keys other than the handshake header"
fi
env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=axonflow-decision-proof bash "$WRITER" "$TMP/mcp.json" >/dev/null 2>&1
if [ "$(header_of "$TMP/mcp.json")" = "$GOLDEN" ] && [ "$(jq '.mcpServers.axonflow.headers | length' "$TMP/mcp.json")" = "$(jq '.mcpServers.axonflow.headers | length' "$ROOT/mcp.json" | awk '{print $1+1}')" ]; then
  pass "audience set twice: idempotent (one header, same value)"
else
  fail "audience set twice: not idempotent"
fi
env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=other-audience bash "$WRITER" "$TMP/mcp.json" >/dev/null 2>&1
if [ "$(header_of "$TMP/mcp.json")" != "$GOLDEN" ] && [ "$(header_of "$TMP/mcp.json")" != "<absent>" ]; then
  pass "a changed audience rewrites the header (not the previous value)"
else
  fail "a changed audience left '$(header_of "$TMP/mcp.json")'"
fi
env -u AXONFLOW_PEP_HANDSHAKE -u AXONFLOW_PEP_AUDIENCE bash "$WRITER" "$TMP/mcp.json" >/dev/null 2>&1
rc=$?
if [ "$rc" = 0 ] && [ "$(jq -S . "$TMP/mcp.json")" = "$SHIPPED" ]; then
  pass "audience unset: the header is removed and mcp.json is back to the shipped content"
else
  fail "audience unset: rc=$rc, header '$(header_of "$TMP/mcp.json")'"
fi
for bad in "" "has spaces" "-leading-hyphen"; do
  cp "$ROOT/mcp.json" "$TMP/bad.json"
  env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=axonflow-decision-proof bash "$WRITER" "$TMP/bad.json" >/dev/null 2>&1
  env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE="$bad" bash "$WRITER" "$TMP/bad.json" >/dev/null 2>&1
  rc=$?
  if [ "$(header_of "$TMP/bad.json")" = "<absent>" ]; then
    if [ -n "$bad" ] && [ "$rc" = 0 ]; then
      fail "a malformed audience ('$bad') removed the header but exited 0 (the operator believes a control is in force)"
    else
      pass "audience '$bad': no header is left (rc=$rc)"
    fi
  else
    fail "audience '$bad': a header is left: '$(header_of "$TMP/bad.json")'"
  fi
done
# With the header written, no header value is the empty string (the handshake
# header included, the one an unset variable would have emptied).
cp "$ROOT/mcp.json" "$TMP/set.json"
env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=axonflow-decision-proof bash "$WRITER" "$TMP/set.json" >/dev/null 2>&1
if [ "$(header_of "$TMP/set.json")" != "<absent>" ] && \
   jq -e '[.mcpServers.axonflow.headers[] | select(. == "")] | length == 0' "$TMP/set.json" >/dev/null; then
  pass "a written mcp.json carries the handshake header and no header value is the empty string"
else
  fail "a written mcp.json has no handshake header, or an empty header value"
fi

# The file's own mode is kept.
cp "$ROOT/mcp.json" "$TMP/mode.json"
chmod 640 "$TMP/mode.json"
env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=axonflow-decision-proof bash "$WRITER" "$TMP/mode.json" >/dev/null 2>&1
mode=$(stat -c %a "$TMP/mode.json" 2>/dev/null || stat -f %Lp "$TMP/mode.json")
if [ "$mode" = "640" ] && [ "$(header_of "$TMP/mode.json")" != "<absent>" ]; then
  pass "a 0640 mcp.json is written and stays 0640"
else
  fail "a 0640 mcp.json came back with mode $mode"
fi

# A symlinked mcp.json is written through to its target: the link stays a link.
mkdir -p "$TMP/real"
cp "$ROOT/mcp.json" "$TMP/real/mcp.json"
chmod 600 "$TMP/real/mcp.json"
ln -s "real/mcp.json" "$TMP/link.json"
env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=axonflow-decision-proof bash "$WRITER" "$TMP/link.json" >/dev/null 2>&1
rc=$?
mode=$(stat -c %a "$TMP/real/mcp.json" 2>/dev/null || stat -f %Lp "$TMP/real/mcp.json")
if [ "$rc" = 0 ] && [ -L "$TMP/link.json" ] && [ "$(header_of "$TMP/real/mcp.json")" != "<absent>" ] && [ "$mode" = "600" ]; then
  pass "a symlinked mcp.json: the target gets the header and keeps mode 0600; the link stays a link"
else
  fail "a symlinked mcp.json: rc=$rc, link kept=$([ -L "$TMP/link.json" ] && echo yes || echo no), target header '$(header_of "$TMP/real/mcp.json")', mode $mode"
fi

# A file the caller cannot write is refused and left as it was.
cp "$ROOT/mcp.json" "$TMP/ro.json"
chmod 444 "$TMP/ro.json"
before=$(cat "$TMP/ro.json")
env -u AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE=axonflow-decision-proof bash "$WRITER" "$TMP/ro.json" >/dev/null 2>&1
rc=$?
if [ "$(id -u)" = "0" ]; then
  pass "a read-only mcp.json (skipped as root, which can write it)"
elif [ "$rc" != 0 ] && [ "$(cat "$TMP/ro.json")" = "$before" ]; then
  pass "a read-only mcp.json is refused (rc=$rc) and left unchanged"
else
  fail "a read-only mcp.json: rc=$rc, changed=$([ "$(cat "$TMP/ro.json")" = "$before" ] && echo no || echo yes)"
fi
chmod 644 "$TMP/ro.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
