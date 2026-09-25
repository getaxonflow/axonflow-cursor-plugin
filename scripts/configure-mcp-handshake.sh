#!/usr/bin/env bash
# configure-mcp-handshake.sh — give Cursor's MCP connection the ADR-065 PEP
# capability handshake, only when an audience is configured.
#
# Cursor's MCP connection uses this plugin's mcp.json: STATIC headers with
# plain ${VAR} expansion and no dynamic header helper. An unset variable
# expands to an EMPTY header value, and a handshake header that is PRESENT
# with an empty value is malformed: the platform refuses the request
# (measured on AxonFlow v11.0.0: HTTP 400, JSON-RPC -32600
# "pep_handshake_malformed ... present and empty"). So the shipped mcp.json
# carries no handshake line at all, and this script writes one only when
# AXONFLOW_PEP_AUDIENCE is set and valid.
#
# The value is the declaration scripts/pep-handshake.sh builds (the same
# encoder the hooks use): profile 1, pep_id cursor-plugin, the audience, and
# an EMPTY capability list (this plugin performs no field redaction). With it,
# a governed MCP call that would carry a mandatory field_redact obligation is
# refused (block_reason unsupported_obligation) instead of being allowed with
# a redacted_message nobody substitutes.
#
# Usage (from the installed plugin directory, e.g.
# ~/.cursor/plugins/local/axonflow-cursor-plugin), then reload Cursor:
#   AXONFLOW_PEP_AUDIENCE=<your audience> bash scripts/configure-mcp-handshake.sh
#   bash scripts/configure-mcp-handshake.sh          # unset: removes the header
# Optional first argument: the mcp.json to edit (default: this plugin's).
#
# Idempotent. Every other key of mcp.json is left as it is. The declaration is
# built from AXONFLOW_PEP_AUDIENCE only: an AXONFLOW_PEP_HANDSHAKE already set in
# the environment is ignored here, although the hooks send such a preset value
# as it is (scripts/pep-handshake.sh builds one only when none is set). The
# write replaces the file (a new inode), so another hard link to it keeps the
# old content, and the file's owner is the caller's. Re-run it after
# changing AXONFLOW_PEP_AUDIENCE: the declaration is a property of the
# deployment, not of a session.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_JSON="${1:-$PLUGIN_DIR/mcp.json}"
HEADER="X-Axonflow-PEP-Handshake"

if ! command -v jq >/dev/null 2>&1; then
  echo "configure-mcp-handshake: jq is required" >&2
  exit 1
fi
if [ ! -f "$MCP_JSON" ]; then
  echo "configure-mcp-handshake: $MCP_JSON not found" >&2
  exit 1
fi
if ! jq -e '.mcpServers.axonflow.headers | type == "object"' "$MCP_JSON" >/dev/null 2>&1; then
  echo "configure-mcp-handshake: $MCP_JSON has no mcpServers.axonflow.headers object" >&2
  exit 1
fi

# Build the declaration with the hooks' encoder. Clear any inherited value so
# the one written is computed from the audience now.
unset AXONFLOW_PEP_HANDSHAKE
# shellcheck source=./pep-handshake.sh
. "$SCRIPT_DIR/pep-handshake.sh"
HANDSHAKE="${AXONFLOW_PEP_HANDSHAKE:-}"

# The file actually written: a symlinked mcp.json is written through to its
# target, so the link stays a link and the target keeps its own mode. A file
# the caller cannot write is refused, never replaced.
TARGET="$MCP_JSON"
_hops=0
while [ -L "$TARGET" ] && [ "$_hops" -lt 20 ]; do
  _link=$(readlink "$TARGET")
  case "$_link" in
    /*) TARGET="$_link" ;;
    *) TARGET="$(dirname "$TARGET")/$_link" ;;
  esac
  _hops=$((_hops + 1))
done
if [ -L "$TARGET" ] || [ ! -f "$TARGET" ]; then
  echo "configure-mcp-handshake: $MCP_JSON does not resolve to a regular file" >&2
  exit 1
fi
if [ ! -w "$TARGET" ]; then
  echo "configure-mcp-handshake: $TARGET is not writable; nothing changed" >&2
  exit 1
fi

write_json() {  # write_json <jq filter> [jq args...]: atomic, the target's mode kept
  local filter="$1"; shift
  local tmp mode
  mode=$(stat -c %a "$TARGET" 2>/dev/null) || mode=""
  case "$mode" in ''|*[!0-7]*) mode=$(stat -f %Lp "$TARGET" 2>/dev/null) || mode="" ;; esac
  case "$mode" in ''|*[!0-7]*) return 1 ;; esac
  tmp=$(mktemp "${TARGET}.XXXXXX") || return 1
  if jq --indent 2 "$@" "$filter" "$TARGET" >"$tmp" 2>/dev/null && [ -s "$tmp" ] && chmod "$mode" "$tmp"; then
    mv "$tmp" "$TARGET"
  else
    rm -f "$tmp"
    return 1
  fi
}

if [ -n "$HANDSHAKE" ]; then
  write_json '.mcpServers.axonflow.headers[$h] = $v' --arg h "$HEADER" --arg v "$HANDSHAKE" || {
    echo "configure-mcp-handshake: could not write $MCP_JSON" >&2
    exit 1
  }
  echo "configure-mcp-handshake: $HEADER set in $MCP_JSON for audience \"$AXONFLOW_PEP_AUDIENCE\". Reload Cursor."
  exit 0
fi

# No declaration: never an empty header. Remove the key if a previous run
# wrote one.
write_json 'del(.mcpServers.axonflow.headers[$h])' --arg h "$HEADER" || {
  echo "configure-mcp-handshake: could not write $MCP_JSON" >&2
  exit 1
}
if [ -n "${AXONFLOW_PEP_AUDIENCE:-}" ]; then
  # pep-handshake.sh already said why on stderr. The operator set an audience
  # and believes a control is in force: fail loudly rather than succeed.
  echo "configure-mcp-handshake: AXONFLOW_PEP_AUDIENCE is malformed; $HEADER removed from $MCP_JSON, so the MCP connection sends no handshake." >&2
  exit 1
fi
echo "configure-mcp-handshake: AXONFLOW_PEP_AUDIENCE is unset; $MCP_JSON sends no $HEADER."
exit 0
