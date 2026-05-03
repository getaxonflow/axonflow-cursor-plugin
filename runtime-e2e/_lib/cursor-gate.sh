#!/usr/bin/env bash
# Shared release-prep gate for Cursor runtime-e2e features.
#
# Cursor's CLI has no headless agent mode — `cursor` is a window
# manager only. So Cursor "runtime tests" are a manual runbook + this
# gate that refuses to pass unless someone actually ran the runbook
# recently and checked in EVIDENCE.md alongside it.
#
# Each per-feature test.sh sources this and calls cursor_gate with the
# MCP tool name the runbook exercises (so the gate verifies the tool
# is actually advertised by the platform before asking a human to run
# a doomed manual test).

set -uo pipefail

: "${AXONFLOW_ENDPOINT:=http://localhost:8080}"
: "${AXONFLOW_CLIENT_ID:=demo-client}"
: "${AXONFLOW_CLIENT_SECRET:=demo-secret}"
: "${EVIDENCE_FRESHNESS_DAYS:=60}"

# cursor_gate <script-dir> <mcp-tool-name>
cursor_gate() {
  local script_dir="$1"
  local mcp_tool="$2"
  local plugin_dir
  plugin_dir="$(cd "$script_dir/../.." && pwd)"
  local errors=0

  local cursor_bin="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
  if [ ! -x "$cursor_bin" ] && ! command -v cursor >/dev/null 2>&1; then
    echo "SKIP: Cursor IDE not installed"
    return 0
  fi
  echo "PASS: Cursor IDE present"

  if ! curl -sSf -o /dev/null --max-time 5 "$AXONFLOW_ENDPOINT/health"; then
    echo "SKIP: AxonFlow stack not reachable at $AXONFLOW_ENDPOINT/health"
    return 0
  fi
  echo "PASS: AxonFlow stack reachable at $AXONFLOW_ENDPOINT"

  local auth_b64 headers_file session_id list_resp
  auth_b64=$(printf '%s:%s' "$AXONFLOW_CLIENT_ID" "$AXONFLOW_CLIENT_SECRET" | base64)
  headers_file=$(mktemp -t axonflow-mcp-cursor-headers.XXXXXX)
  curl -s -D "$headers_file" -X POST \
    -H "Authorization: Basic $auth_b64" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -H "MCP-Protocol-Version: 2025-06-18" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"cursor-runtime-prereq","version":"1.0.0"},"capabilities":{}}}' \
    "$AXONFLOW_ENDPOINT/api/v1/mcp-server" >/dev/null
  session_id=$(grep -i "^mcp-session-id" "$headers_file" | awk '{print $2}' | tr -d '\r\n')
  rm -f "$headers_file"
  if [ -z "$session_id" ]; then
    echo "FAIL: MCP initialize did not return a session id"
    errors=$((errors + 1))
  else
    list_resp=$(curl -s -X POST -H "Authorization: Basic $auth_b64" \
      -H "Content-Type: application/json" -H "Accept: application/json" \
      -H "MCP-Protocol-Version: 2025-06-18" \
      -H "Mcp-Session-Id: $session_id" \
      -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
      "$AXONFLOW_ENDPOINT/api/v1/mcp-server")
    if printf '%s' "$list_resp" | grep -q "\"name\":\"$mcp_tool\""; then
      echo "PASS: MCP server advertises $mcp_tool"
    else
      echo "FAIL: MCP server did not advertise $mcp_tool — wiring is wrong"
      errors=$((errors + 1))
    fi
  fi

  if [ -f "$plugin_dir/mcp.json" ]; then
    local url
    url=$(jq -r '.mcpServers.axonflow.url // empty' "$plugin_dir/mcp.json" 2>/dev/null)
    if [ -n "$url" ]; then
      echo "PASS: mcp.json declares MCP server URL: $url"
    else
      echo "FAIL: mcp.json missing .mcpServers.axonflow.url"
      errors=$((errors + 1))
    fi
  else
    echo "FAIL: $plugin_dir/mcp.json not found"
    errors=$((errors + 1))
  fi

  if [ ! -f "$script_dir/MANUAL_RUNBOOK.md" ]; then
    echo "FAIL: MANUAL_RUNBOOK.md missing in $script_dir"
    errors=$((errors + 1))
  fi

  if [ ! -f "$script_dir/EVIDENCE.md" ]; then
    echo "FAIL: EVIDENCE.md missing — run MANUAL_RUNBOOK.md and check in the captured output"
    errors=$((errors + 1))
  else
    local mtime_s now_s age_days
    if [ "$(uname)" = "Darwin" ]; then
      mtime_s=$(stat -f %m "$script_dir/EVIDENCE.md")
    else
      mtime_s=$(stat -c %Y "$script_dir/EVIDENCE.md")
    fi
    now_s=$(date +%s)
    age_days=$(( (now_s - mtime_s) / 86400 ))
    if [ "$age_days" -gt "$EVIDENCE_FRESHNESS_DAYS" ]; then
      echo "FAIL: EVIDENCE.md is $age_days days old (>${EVIDENCE_FRESHNESS_DAYS}d) — re-run the manual runbook"
      errors=$((errors + 1))
    else
      echo "PASS: EVIDENCE.md is $age_days days old (≤ ${EVIDENCE_FRESHNESS_DAYS}-day window)"
    fi
  fi

  if [ "$errors" -gt 0 ]; then
    echo ""
    echo "FAIL: $errors prereq(s) failed — fix before requesting Cursor release approval"
    return 1
  fi
  echo ""
  echo "PASS: cursor $mcp_tool runtime gate — manual evidence on file is fresh"
}
