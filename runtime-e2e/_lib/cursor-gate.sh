#!/usr/bin/env bash
# Shared release-prep gate for Cursor runtime-e2e features.
#
# Cursor's CLI has no headless agent mode — `cursor` is a window
# manager only. So Cursor "runtime tests" are a manual runbook + this
# gate that refuses to pass unless someone actually ran the runbook
# recently and checked in EVIDENCE.md alongside it.
#
# Each per-feature test.sh sources this and calls cursor_gate with the
# MCP tool name(s) the runbook exercises (so the gate verifies every
# tool the manual run drives is actually advertised by the platform
# before asking a human to run a doomed manual test). Pass one argument
# per tool; the gate fails if any of them is not advertised.

set -uo pipefail

: "${AXONFLOW_ENDPOINT:=http://localhost:8080}"
: "${AXONFLOW_CLIENT_ID:=demo-client}"
: "${AXONFLOW_CLIENT_SECRET:=demo-secret}"
: "${EVIDENCE_FRESHNESS_DAYS:=60}"

# runtime_e2e_refuse_production <url> <what this suite writes there>
#
# Production Community SaaS (https://try.getaxonflow.com) is never a default
# target: a suite that registers a tenant, writes a policy or edits the
# database there changes live state (axonflow-enterprise#4249, comments
# 5684192928 and 5694502320). When <url>'s host is try.getaxonflow.com the
# suite SKIPs, naming what it would write, unless the operator set
# AXONFLOW_E2E_ALLOW_PRODUCTION=1 for this run. Any other host returns.
runtime_e2e_refuse_production() {
  local url="$1" writes="$2" host
  host=$(printf '%s' "$url" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://##; s#^[^@/]*@##; s#[:/?#].*$##' | tr '[:upper:]' '[:lower:]')
  case "$host" in
    try.getaxonflow.com|try.getaxonflow.com.) ;;
    *) return 0 ;;
  esac
  if [ "${AXONFLOW_E2E_ALLOW_PRODUCTION:-}" = "1" ]; then
    echo "WARNING: running against PRODUCTION Community SaaS at $url (AXONFLOW_E2E_ALLOW_PRODUCTION=1); this suite $writes"
    return 0
  fi
  echo "SKIP: $url is PRODUCTION Community SaaS, and this suite $writes."
  echo "      Point it at a stack you own, or set AXONFLOW_E2E_ALLOW_PRODUCTION=1 to run it there deliberately."
  exit 0
}


# cursor_gate <script-dir> <mcp-tool-name>...
cursor_gate() {
  local script_dir="$1"
  shift
  local mcp_tools=("$@")
  if [ "${#mcp_tools[@]}" -eq 0 ]; then
    echo "FAIL: cursor_gate called without any MCP tool name"
    return 1
  fi
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
    local mcp_tool
    for mcp_tool in "${mcp_tools[@]}"; do
      if printf '%s' "$list_resp" | grep "\"name\":\"$mcp_tool\"" >/dev/null; then
        echo "PASS: MCP server advertises $mcp_tool"
      else
        echo "FAIL: MCP server did not advertise $mcp_tool - wiring is wrong"
        errors=$((errors + 1))
      fi
    done
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
    # Freshness is the RUN DATE the evidence records, not the file's mtime:
    # a clone or checkout resets mtime to now, so an mtime check passed on
    # evidence of any age, and editing the file's text refreshed it too.
    local run_date run_s now_s age_days
    run_date=$(sed -n 's/^\*\*Run date (UTC):\*\* *\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p' "$script_dir/EVIDENCE.md" | head -1)
    run_s=""
    if [ -n "$run_date" ]; then
      run_s=$(date -u -j -f "%Y-%m-%d" "$run_date" +%s 2>/dev/null || date -u -d "$run_date" +%s 2>/dev/null || echo "")
    fi
    if [ -z "$run_s" ]; then
      echo "FAIL: EVIDENCE.md records no readable '**Run date (UTC):** YYYY-MM-DD' line"
      errors=$((errors + 1))
    else
      now_s=$(date -u +%s)
      age_days=$(( (now_s - run_s) / 86400 ))
      if [ "$age_days" -gt "$EVIDENCE_FRESHNESS_DAYS" ]; then
        echo "FAIL: EVIDENCE.md records a run $age_days days old ($run_date, >${EVIDENCE_FRESHNESS_DAYS}d) — re-run the manual runbook"
        errors=$((errors + 1))
      else
        echo "PASS: EVIDENCE.md records a run $age_days days old ($run_date, ≤ ${EVIDENCE_FRESHNESS_DAYS}-day window)"
      fi
    fi
  fi

  if [ "$errors" -gt 0 ]; then
    echo ""
    echo "FAIL: $errors prereq(s) failed — fix before requesting Cursor release approval"
    return 1
  fi
  echo ""
  echo "PASS: cursor ${mcp_tools[*]} runtime gate - manual evidence on file is fresh"
}
