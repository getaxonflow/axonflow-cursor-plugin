#!/usr/bin/env bash
# Runtime test for cursor#47: Cursor MCP-session forwards X-Axonflow-Client
# + X-License-Token (when set) on every probe to the AxonFlow agent.
#
# This is a runtime test per CLAUDE.md HARD RULE #0 — it MUST hit a real
# agent (no mocks). The host CLI here is Cursor; we drive it via the
# `cursor` CLI launcher pointed at a project workspace whose
# `.cursor/mcp.json` matches the plugin's shipped one.
#
# Run locally:
#   1. Bring up local agent + logging proxy (see runtime-e2e/README.md).
#   2. export AXONFLOW_ENDPOINT=http://localhost:8181  # logging proxy
#   3. export AXONFLOW_LICENSE_TOKEN=AXON-...          # optional Pro tier
#   4. ./test.sh

set -uo pipefail

PROXY_LOG="${PROXY_LOG:-/tmp/axonflow-e2e/proxy.log}"

if [ ! -f "$PROXY_LOG" ]; then
  echo "SKIP: $PROXY_LOG not found — start the logging proxy first (see runtime-e2e/README.md)."
  exit 0
fi

CURSOR_BIN=""
if command -v cursor >/dev/null 2>&1; then
  CURSOR_BIN=$(command -v cursor)
elif [ -x /Applications/Cursor.app/Contents/Resources/app/bin/cursor ]; then
  CURSOR_BIN=/Applications/Cursor.app/Contents/Resources/app/bin/cursor
else
  echo "SKIP: Cursor CLI not on PATH and Cursor.app not installed at /Applications/Cursor.app."
  exit 0
fi

# run_cursor_against <mcp.json>: launch Cursor on a workspace whose
# .cursor/mcp.json is that file, let the MCP server activate, quit, and print
# the proxy lines this launch added.
run_cursor_against() {
  local mcp="$1" workdir before after
  workdir=$(mktemp -d)
  mkdir -p "$workdir/.cursor"
  cp "$mcp" "$workdir/.cursor/mcp.json"
  before=$(wc -l < "$PROXY_LOG")
  "$CURSOR_BIN" "$workdir" >/dev/null 2>&1 &
  local pid=$!
  sleep 30
  osascript -e 'quit app "Cursor"' 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  after=$(wc -l < "$PROXY_LOG")
  tail -n "$((after - before))" "$PROXY_LOG"
  rm -rf "$workdir"
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FAILED=0

NEW=$(run_cursor_against "$PLUGIN_DIR/mcp.json")
HITS=$(grep -c 'X-Axonflow-Client=cursor-plugin/' <<<"$NEW" || true)
if [ "$HITS" -gt 0 ]; then
  echo "PASS: $HITS proxy hit(s) carrying X-Axonflow-Client=cursor-plugin/* — Cursor honored the headers field"
else
  echo "FAIL: no proxy hit carrying X-Axonflow-Client=cursor-plugin/*."
  echo "Last 5 proxy lines:"
  tail -5 "$PROXY_LOG" >&2
  echo ""
  echo "Possible causes:"
  echo "  1. Cursor didn't activate the MCP config (may need manual user interaction)."
  echo "  2. Cursor doesn't honor 'headers' field in mcp.json — would need a stdio bridge."
  echo "  3. The proxy isn't running."
  FAILED=1
fi

# The ADR-065 capability handshake (cursor#95), EVIDENCE-GATED: it needs a
# supervised Cursor launch and a proxy that logs, per request, either
# `X-Axonflow-PEP-Handshake=<value>` (the header present, possibly empty) or
# nothing for that header when it is absent. Opt in with
# AXONFLOW_E2E_CURSOR_HANDSHAKE=1. It settles what the wire-level stage 3 of
# runtime-e2e/pep_capability_handshake cannot: what CURSOR sends.
if [ "${AXONFLOW_E2E_CURSOR_HANDSHAKE:-}" = "1" ]; then
  # 1. No audience: the shipped template must make Cursor send NO handshake
  #    header at all. An empty one is malformed and refuses the connection.
  NEW=$(unset AXONFLOW_PEP_AUDIENCE; run_cursor_against "$PLUGIN_DIR/mcp.json")
  if grep -q 'X-Axonflow-PEP-Handshake=' <<<"$NEW"; then
    echo "FAIL: with no audience Cursor sent an X-Axonflow-PEP-Handshake header: $(grep -m1 'X-Axonflow-PEP-Handshake=' <<<"$NEW")"
    FAILED=1
  else
    echo "PASS: with no audience Cursor sent no X-Axonflow-PEP-Handshake header"
  fi
  # 2. An audience, written by scripts/configure-mcp-handshake.sh: every
  #    request carries the encoder's value.
  CONFIGURED=$(mktemp)
  cp "$PLUGIN_DIR/mcp.json" "$CONFIGURED"
  AXONFLOW_PEP_AUDIENCE="${AXONFLOW_PEP_AUDIENCE:-axonflow-decision-proof}" bash "$PLUGIN_DIR/scripts/configure-mcp-handshake.sh" "$CONFIGURED" >/dev/null
  WANT=$(jq -r '.mcpServers.axonflow.headers["X-Axonflow-PEP-Handshake"]' "$CONFIGURED")
  NEW=$(run_cursor_against "$CONFIGURED")
  rm -f "$CONFIGURED"
  if grep -qF "X-Axonflow-PEP-Handshake=$WANT" <<<"$NEW"; then
    echo "PASS: with an audience Cursor sent the handshake the writer configured"
  else
    echo "FAIL: with an audience Cursor did not send X-Axonflow-PEP-Handshake=$WANT"
    FAILED=1
  fi
else
  echo "SKIP: the handshake legs (set AXONFLOW_E2E_CURSOR_HANDSHAKE=1; evidence-gated, see README.md)"
fi

exit "$FAILED"
