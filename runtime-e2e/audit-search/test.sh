#!/usr/bin/env bash
# Cursor runtime E2E gate for audit-search (W2 — rule #1)
#
# Cursor product limitation: the `cursor` CLI is window-management only —
# no `cursor exec "prompt"` equivalent of `claude -p` / `codex exec` /
# `openclaw agent --local --message`. So Cursor's agent surface cannot be
# fully automated today.
#
# What this script enforces at release-prep time
#
# 1. Cursor IDE is installed (so a human can run the manual runbook).
# 2. The live AxonFlow stack is reachable.
# 3. The MCP server actually advertises `search_audit_events` (catches
#    wiring breakage on the platform side before asking a human to run
#    a doomed manual test).
# 4. The plugin's `mcp.json` is well-formed and points at a usable URL.
# 5. The manual runbook (`MANUAL_RUNBOOK.md`) exists.
# 6. The captured evidence (`EVIDENCE.md`) from the human's last run
#    exists AND is no more than 60 days old.
#
# Why this still meets rule #1
#
# Rule #1 says "no user-facing feature merges without one runtime-path
# test." It does not say the test must be fully headless. The manual
# runbook IS the runtime test for Cursor; this script is the gate that
# refuses to pass unless someone actually ran it recently. The
# rule-#1 evidence is in EVIDENCE.md, not in this script's output.
#
# When Cursor ships a headless mode, replace this with the automated
# equivalent of the Claude/Codex/OpenClaw runtime tests in the sibling
# plugins.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

: "${AXONFLOW_ENDPOINT:=http://localhost:8080}"
: "${AXONFLOW_CLIENT_ID:=demo-client}"
: "${AXONFLOW_CLIENT_SECRET:=demo-secret}"

errors=0

# 1. Cursor IDE present.
CURSOR_BIN="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
if [ ! -x "$CURSOR_BIN" ] && ! command -v cursor >/dev/null 2>&1; then
  echo "SKIP: Cursor IDE not installed — manual runbook can't be executed here"
  exit 0
fi
echo "PASS: Cursor IDE present"

# 2. Live stack.
if ! curl -sSf -o /dev/null --max-time 5 "$AXONFLOW_ENDPOINT/health"; then
  echo "SKIP: AxonFlow stack not reachable at $AXONFLOW_ENDPOINT/health"
  exit 0
fi
echo "PASS: AxonFlow stack reachable at $AXONFLOW_ENDPOINT"

# 3. MCP server advertises the tool the runbook depends on.
AUTH_B64=$(printf '%s:%s' "$AXONFLOW_CLIENT_ID" "$AXONFLOW_CLIENT_SECRET" | base64)
HEADERS_FILE=$(mktemp -t axonflow-mcp-cursor-headers.XXXXXX)
curl -s -D "$HEADERS_FILE" -X POST \
  -H "Authorization: Basic $AUTH_B64" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"cursor-runtime-prereq","version":"1.0.0"},"capabilities":{}}}' \
  "$AXONFLOW_ENDPOINT/api/v1/mcp-server" >/dev/null
SESSION_ID=$(grep -i "^mcp-session-id" "$HEADERS_FILE" | awk '{print $2}' | tr -d '\r\n')
rm -f "$HEADERS_FILE"
if [ -z "$SESSION_ID" ]; then
  echo "FAIL: MCP initialize did not return a session id (server problem)"
  errors=$((errors + 1))
else
  LIST_RESP=$(curl -s -X POST -H "Authorization: Basic $AUTH_B64" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -H "MCP-Protocol-Version: 2025-06-18" \
    -H "Mcp-Session-Id: $SESSION_ID" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    "$AXONFLOW_ENDPOINT/api/v1/mcp-server")
  if printf '%s' "$LIST_RESP" | grep -q '"name":"search_audit_events"'; then
    echo "PASS: MCP server advertises search_audit_events"
  else
    echo "FAIL: MCP server did not advertise search_audit_events — wiring is wrong"
    errors=$((errors + 1))
  fi
fi

# 4. Plugin mcp.json well-formed.
if [ -f "$PLUGIN_DIR/mcp.json" ]; then
  URL=$(jq -r '.mcpServers.axonflow.url // empty' "$PLUGIN_DIR/mcp.json" 2>/dev/null)
  if [ -n "$URL" ]; then
    echo "PASS: mcp.json declares MCP server URL: $URL"
  else
    echo "FAIL: mcp.json missing .mcpServers.axonflow.url"
    errors=$((errors + 1))
  fi
else
  echo "FAIL: $PLUGIN_DIR/mcp.json not found"
  errors=$((errors + 1))
fi

# 5+6. Manual runbook + fresh evidence.
if [ ! -f "$SCRIPT_DIR/MANUAL_RUNBOOK.md" ]; then
  echo "FAIL: MANUAL_RUNBOOK.md missing"
  errors=$((errors + 1))
fi
if [ ! -f "$SCRIPT_DIR/EVIDENCE.md" ]; then
  echo "FAIL: EVIDENCE.md missing — run MANUAL_RUNBOOK.md and check in the captured output"
  errors=$((errors + 1))
else
  if [ "$(uname)" = "Darwin" ]; then
    EVIDENCE_MTIME_S=$(stat -f %m "$SCRIPT_DIR/EVIDENCE.md")
  else
    EVIDENCE_MTIME_S=$(stat -c %Y "$SCRIPT_DIR/EVIDENCE.md")
  fi
  NOW_S=$(date +%s)
  AGE_DAYS=$(( (NOW_S - EVIDENCE_MTIME_S) / 86400 ))
  if [ "$AGE_DAYS" -gt 60 ]; then
    echo "FAIL: EVIDENCE.md is $AGE_DAYS days old — re-run the manual runbook before tagging a release"
    errors=$((errors + 1))
  else
    echo "PASS: EVIDENCE.md is $AGE_DAYS days old (≤ 60-day freshness window)"
  fi
fi

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "FAIL: $errors prereq(s) failed — fix before requesting Cursor release approval"
  exit 1
fi
echo ""
echo "PASS: cursor audit-search runtime gate — Cursor present, stack live, MCP wiring correct, manual evidence fresh"
echo "      Rule-#1 evidence is in EVIDENCE.md (real human-driven Cursor IDE run)."
