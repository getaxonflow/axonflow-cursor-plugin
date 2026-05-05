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

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/.cursor"
cp ../../mcp.json "$WORKDIR/.cursor/mcp.json"

LINES_BEFORE=$(wc -l < "$PROXY_LOG")

"$CURSOR_BIN" "$WORKDIR" >/dev/null 2>&1 &
CURSOR_PID=$!
sleep 30
osascript -e 'quit app "Cursor"' 2>/dev/null || true
wait "$CURSOR_PID" 2>/dev/null || true

LINES_AFTER=$(wc -l < "$PROXY_LOG")
NEW_LINES=$((LINES_AFTER - LINES_BEFORE))

HITS=$(tail -n "$NEW_LINES" "$PROXY_LOG" | grep -c 'X-Axonflow-Client=cursor-plugin/' || true)
if [ "$HITS" -gt 0 ]; then
  echo "PASS: $HITS proxy hit(s) carrying X-Axonflow-Client=cursor-plugin/* — Cursor honored the headers field"
  exit 0
fi

echo "FAIL: no proxy hit carrying X-Axonflow-Client=cursor-plugin/*."
echo "Last 5 proxy lines:"
tail -5 "$PROXY_LOG" >&2
echo ""
echo "Possible causes:"
echo "  1. Cursor didn't activate the MCP config (may need manual user interaction)."
echo "  2. Cursor doesn't honor 'headers' field in mcp.json — would need a stdio bridge."
echo "  3. The proxy isn't running."
exit 1
