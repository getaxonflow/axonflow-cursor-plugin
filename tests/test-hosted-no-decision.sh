#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
hook_shell=${AXONFLOW_TEST_BASH:-bash}
tmp=$(mktemp -d -t axonflow-hosted-decision.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config" "$tmp/cache"
printf '%s\n' '{"tenant_id":"cs_12345678-1234-1234-1234-123456789abc","secret":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","expires_at":"2099-01-01T00:00:00Z","endpoint":"https://try.getaxonflow.com"}' > "$tmp/config/hosted-cursor.json"
chmod 700 "$tmp/config"
chmod 600 "$tmp/config/hosted-cursor.json"
cat > "$tmp/bin/curl" <<'FAKE_CURL'
#!/bin/sh
headers=''; body=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -D) headers=$2; shift 2 ;;
    -o) body=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$AXONFLOW_FAKE_SCENARIO" in
  bare401) code=401; payload='' ;;
  bare402) code=402; payload='' ;;
  server500) code=500; payload='{"jsonrpc":"2.0","id":"hook-pre","error":{"code":-32603,"message":"server error"}}' ;;
  empty200) code=200; payload='' ;;
  malformed200) code=200; payload='not json' ;;
  parse200) code=200; payload='{"jsonrpc":"2.0","id":"hook-pre","error":{"code":-32700,"message":"parse error"}}' ;;
  internal200) code=200; payload='{"jsonrpc":"2.0","id":"hook-pre","error":{"code":-32603,"message":"internal error"}}' ;;
  allow200) code=200; payload='{"jsonrpc":"2.0","id":"hook-pre","result":{"content":[{"type":"text","text":"{\"allowed\":true}"}]}}' ;;
  *) exit 90 ;;
esac
printf 'HTTP/1.1 %s\r\n\r\n' "$code" > "$headers"
printf '%s' "$payload" > "$body"
printf '%s' "$code"
FAKE_CURL
chmod +x "$tmp/bin/curl"

probe() {
  local scenario=$1 endpoint=$2 expected_exit=$3 actual_exit
  if printf '%s\n' '{"tool_name":"Shell","tool_input":{"command":"echo synthetic"}}' |
      env -u AXONFLOW_AUTH -u AXONFLOW_USER_TOKEN -u AXONFLOW_MCP_AUTHORIZATION \
        AXONFLOW_ENDPOINT="$endpoint" AXONFLOW_FAKE_SCENARIO="$scenario" \
        AXONFLOW_CONFIG_DIR="$tmp/config" XDG_CACHE_HOME="$tmp/cache/$scenario-$expected_exit" \
        AXONFLOW_TELEMETRY=off AXONFLOW_PLUGIN_VERSION_CHECK=off PATH="$tmp/bin:$PATH" \
        "$hook_shell" "$root/scripts/pre-tool-check.sh" > "$tmp/stdout" 2> "$tmp/stderr"; then
    actual_exit=0
  else
    actual_exit=$?
  fi
  [ "$actual_exit" -eq "$expected_exit" ] || { cat "$tmp/stdout" "$tmp/stderr" >&2; exit 1; }
}

for scenario in bare401 bare402 server500 empty200 malformed200 parse200 internal200; do
  probe "$scenario" 'https://try.getaxonflow.com' 2
done
probe allow200 'https://try.getaxonflow.com' 0
for scenario in server500 empty200 parse200 internal200; do
  probe "$scenario" 'https://try.getaxonflow.com.evil.test' 0
done
printf '%s\n' 'PASS Hosted no-decision/refusal matrix; self-hosted fallback retained'
