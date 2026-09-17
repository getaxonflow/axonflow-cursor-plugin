#!/usr/bin/env bash
# PostToolUse hook — audit logging and output scanning.
# Adapted for Cursor IDE from the Claude Code plugin.
#
# 1. Records tool execution in AxonFlow audit trail (fire-and-forget, background)
# 2. Scans tool output for PII/secrets (synchronous — returns context to Cursor)
#
# Cursor PostToolUse always exits 0 — it never blocks; the tool already ran.
#
# The input, as Cursor documents it (https://cursor.com/docs/hooks, read
# 2026-09-16; not verified against a captured session):
#   - postToolUse: tool_name, tool_input, and tool_output, a JSON-STRINGIFIED
#     result payload such as "{\"exitCode\":0,\"stdout\":\"...\"}";
#   - afterShellExecution: command and output, no tool_name (read here, but
#     hooks/hooks.json does not register this event; postToolUse carries the
#     shell output);
#   - afterFileEdit: file_path and edits [{old_string, new_string}], no
#     tool_name.
# The legacy object tool_response ({stdout, exitCode}) is still read. Before
# this change the hook read only an object, so every documented postToolUse
# output and every afterFileEdit edit went unscanned, with nothing shown.
#
# The output: a governance alert is written twice, as Cursor's documented
# top-level additional_context and as hookSpecificOutput.additionalContext
# (the shape this hook emitted before, which a host reading the Claude Code
# shape reads). Nothing reads both; each host reads the one it knows.
#
# When the output could not be checked it says so, reading the same status
# table as pre-tool-check.sh (scripts/lib/failure-posture.sh):
#   - an answer that refused the check (a 401 or its cooldown, a 429 or a
#     request-rate limit stamp, a 3xx, a 4xx other than 408 without a JSON-RPC
#     answer, a JSON-RPC error other than -32603 / -32700, a result without a
#     decision), or a check request that could not be built -> a GOVERNANCE
#     ALERT telling the model not to use the output;
#   - no usable answer (unreachable, timeout, 408, 5xx, JSON-RPC -32603 /
#     -32700, an empty or unreadable body, jq or curl missing) ->
#     AXONFLOW_FAIL_MODE decides, and on Cursor the default is the same alert.
#     Only "open" passes the output, with a notice on stderr (Cursor documents
#     no field that shows a person a notice here).

# The script's directory from builtins only: this runs before the dependency
# check below, on a PATH that may hold nothing but bash.
# The time budget (scripts/lib/failure-posture.sh) counts bash's SECONDS from
# here. SECONDS exported by the calling environment would otherwise move it:
# a large value exhausts the budget before the check, a negative one lifts it.
SECONDS=0

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
if [ "$SCRIPT_DIR" = "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="."
fi
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"

# _axonflow_json_string <text>
#   The text as a JSON string. jq when it is installed; without it, by hand:
#   backslashes and double quotes escaped and control characters dropped, so
#   the document stays valid (the text is this script's own wording).
_axonflow_json_string() {
  if command -v jq &>/dev/null; then
    printf '%s' "$1" | jq -Rs .
  else
    # Builtins only: this runs when jq is missing, on a PATH that may hold
    # nothing else. Backslashes and double quotes are escaped and control
    # characters dropped, so the document stays valid.
    local s="$1" out="" c i
    for ((i = 0; i < ${#s}; i++)); do
      c="${s:i:1}"
      case "$c" in
        \\) out="${out}\\\\" ;;
        '"') out="${out}\\\"" ;;
        [[:cntrl:]]) ;;
        *) out="${out}${c}" ;;
      esac
    done
    printf '"%s"' "$out"
  fi
}

# Emit a PostToolUse governance alert and stop: Cursor's documented top-level
# additional_context, and the hookSpecificOutput.additionalContext shape.
axonflow_post_alert() {
  local msg
  msg=$(_axonflow_json_string "$1")
  printf '{"additional_context":%s,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$msg" "$msg"
  exit 0
}

# The output could not be checked: tell the model not to use it, saying why.
axonflow_post_unchecked() {
  axonflow_post_alert "GOVERNANCE ALERT: AxonFlow could not check this tool output ($1). Do not use or reference the output in your response until it can be checked."
}

# The failure-posture table this hook reads. Without it the hook cannot tell a
# check from a refusal, so the model is told not to use the output.
# shellcheck source=./lib/failure-posture.sh
if ! . "${SCRIPT_DIR}/lib/failure-posture.sh" 2>/dev/null; then
  axonflow_post_unchecked "the AxonFlow plugin install is incomplete: scripts/lib/failure-posture.sh is missing or unreadable"
fi

# The output could not be checked because no usable answer arrived.
# AXONFLOW_FAIL_MODE decides, and the Cursor default is the alert: only "open"
# (any case) passes the output, with a notice on stderr.
axonflow_post_ungoverned() {
  if ! axonflow_fail_mode_open; then
    axonflow_post_unchecked "$1"
  fi
  echo "[AxonFlow] GOVERNANCE UNAVAILABLE: $1. This tool output was NOT checked, because AXONFLOW_FAIL_MODE is open." >&2
  exit 0
}

# The hook cannot read the tool call or reach AxonFlow without these.
if ! command -v jq &>/dev/null; then
  axonflow_post_ungoverned "the AxonFlow hook needs jq, which is not installed"
fi
if ! command -v curl &>/dev/null; then
  axonflow_post_ungoverned "the AxonFlow hook needs curl, which is not installed"
fi

# Endpoint resolution per ADR-048: default to AxonFlow Community SaaS only when
# the user has not set explicit config. Mirrors pre-tool-check.sh exactly so the
# two hooks always agree on which AxonFlow they're talking to.
if [ -z "${AXONFLOW_ENDPOINT:-}" ] && [ -z "${AXONFLOW_AUTH:-}" ]; then
  ENDPOINT="https://try.getaxonflow.com"
  AXONFLOW_MODE="community-saas"
  # Test-harness override, as in pre-tool-check.sh: production code paths leave
  # AXONFLOW_HARNESS unset and the endpoint stays pinned
  # (tests/test-hooks.sh, the harness community-saas legs).
  if [ "${AXONFLOW_HARNESS:-}" = "1" ] && [ -n "${AXONFLOW_HARNESS_AGENT_ENDPOINT:-}" ]; then
    ENDPOINT="$AXONFLOW_HARNESS_AGENT_ENDPOINT"
  fi
else
  ENDPOINT="${AXONFLOW_ENDPOINT:-http://localhost:8080}"
  AXONFLOW_MODE="self-hosted"
fi
export AXONFLOW_MODE
# The configured per-request timeout (a positive integer; anything else is the
# default). The scan itself gets no more than the hook's time budget leaves.
CONFIGURED_TIMEOUT_SECONDS="${AXONFLOW_TIMEOUT_SECONDS:-5}"
case "$CONFIGURED_TIMEOUT_SECONDS" in ''|*[!0-9]*|0) CONFIGURED_TIMEOUT_SECONDS=5 ;; esac
REQUEST_TIMEOUT_SECONDS="$CONFIGURED_TIMEOUT_SECONDS"

# Bootstrap the Community-SaaS credential if needed. No-op in self-hosted mode.
# Pre-tool-check ran first and likely already wrote the registration file; this
# is just loading it. Mode-clarity log line is intentionally NOT repeated here —
# pre-tool-check fires it once per hook invocation.
_AXONFLOW_REGISTER_MAX_TIME=$(axonflow_budget_timeout 5 4)
# Only this run's bootstrap may define its cleanup: nothing of that name from
# the environment (an exported shell function) is ever called.
unset _AXONFLOW_BOOTSTRAP_TRAP
unset -f _axonflow_bootstrap_cleanup_on_exit 2>/dev/null
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/community-saas-bootstrap.sh"
AUTH="${AXONFLOW_AUTH:-}"

# Plugin-claimed Pro license token (W4 paid tier, ADR-049). Same env-then-file
# resolution as pre-tool-check.sh so audit writes carry the same tier context
# as the policy check that preceded them. Without this, the agent would tag
# audit rows from a Pro user with the free-tier retention/quota.
LICENSE_TOKEN="${AXONFLOW_LICENSE_TOKEN:-}"
LICENSE_TOKEN_FILE="${HOME}/.config/axonflow/license-token"
if [ -z "$LICENSE_TOKEN" ] && [ -f "$LICENSE_TOKEN_FILE" ]; then
  TOK_MODE=$(stat -c %a "$LICENSE_TOKEN_FILE" 2>/dev/null) || TOK_MODE=""
  case "$TOK_MODE" in
    ''|*[!0-9]*) TOK_MODE=$(stat -f %Lp "$LICENSE_TOKEN_FILE" 2>/dev/null) || TOK_MODE="" ;;
  esac
  case "$TOK_MODE" in
    ''|*[!0-9]*) TOK_MODE="" ;;
  esac
  if [ "$TOK_MODE" = "600" ] || [ "$TOK_MODE" = "0600" ]; then
    LICENSE_TOKEN=$(tr -d '\r\n' < "$LICENSE_TOKEN_FILE" 2>/dev/null || echo "")
  fi
  # Permission warning is intentionally only emitted by pre-tool-check.sh —
  # post-tool-audit.sh runs once per tool call and we don't want to spam.
fi

# ADR-050 §4: X-Axonflow-Client identifies the calling plugin so the agent
# can derive request scope (plugin) and validate against the token's aud.scope.
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/client-header.sh"

# V1 Plugin Pro upgrade-prompt envelope handling (umbrella
# axonflow-enterprise#1958) and the shared throttle-until stamp.
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/upgrade-prompt.sh"

AUTH_ALERT="GOVERNANCE ALERT: AxonFlow could not check this tool output (the AxonFlow agent rejected authentication, HTTP 401). Do not use or reference the output in your response until the credential is fixed and it can be checked."

# A recent governed call stamped the shared throttle-until file, and the hook
# answers locally. The output cannot be checked while a gating stamp holds, so
# the model is told not to use it: the 401 cooldown (auth_failure) or a
# request-rate limit written less than 300 seconds ago (ruled 2026-09-14).
# Any other stamp gates nothing (scripts/upgrade-prompt.sh, the stamp rules).
case "$(axonflow_governed_stamp)" in
  auth_failure)
    echo "[AxonFlow] $(axonflow_auth_cooldown_note)" >&2
    axonflow_post_alert "$AUTH_ALERT"
    ;;
  limit)
    axonflow_post_alert "$AXONFLOW_LIMIT_POST_ALERT"
    ;;
esac

AUTH_HEADER=()
if [ -n "$AUTH" ]; then
  AUTH_HEADER+=(-H "Authorization: Basic $AUTH")
fi
AUTH_HEADER+=(-H "X-Axonflow-Client: ${AXONFLOW_CLIENT_HEADER}")
# ADR-065 capability handshake (axonflow-enterprise#3763). Declares what this
# enforcement point can discharge, so the platform refuses to hand it a
# mandatory obligation it has said it cannot carry out.
#
# Added ONLY when non-empty. A header that is PRESENT with an empty value is
# MALFORMED to the platform and refuses the request, which an ABSENT header
# does not - so an unconditional -H here would 400 every unconfigured install.
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/pep-handshake.sh"
if [ -n "${AXONFLOW_PEP_HANDSHAKE:-}" ]; then
  AUTH_HEADER+=(-H "X-Axonflow-PEP-Handshake: ${AXONFLOW_PEP_HANDSHAKE}")
fi
if [ -n "$LICENSE_TOKEN" ]; then
  AUTH_HEADER+=(-H "X-License-Token: $LICENSE_TOKEN")
fi

# Per-user authorization token (axonflow-enterprise#2943, epic #2919) —
# mirror pre-tool-check.sh so the audit_tool_call POST AND the check_output
# scan below (both reuse AUTH_HEADER) carry X-User-Token and the platform
# resolves a VALIDATED {identity, role} for this developer. Omitted entirely
# when unconfigured (no empty header); the token value is never logged.
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/user-token.sh"
resolve_user_token
if [ -n "${AXONFLOW_USER_TOKEN:-}" ]; then
  AUTH_HEADER+=(-H "X-User-Token: ${AXONFLOW_USER_TOKEN}")
fi

# Read hook input from stdin
INPUT=$(cat)

# Input that is not a JSON object cannot be checked: tell the model not to use the
# output (the Cursor default for anything this hook cannot govern). Empty input
# names no call and is left alone.
if [ -n "$INPUT" ] && ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  axonflow_post_unchecked "the hook input for this tool call is not JSON (or not a JSON object)"
fi

# Normalize the three documented shapes and the legacy one into:
#   TOOL_NAME, TOOL_INPUT (object) and PAYLOAD (the tool's result: an object
#   when it is JSON, else the raw string; {} when there is none).
NORMALIZED=$(printf '%s' "$INPUT" | jq -c '
  def payload:
    if .tool_response != null then .tool_response
    elif (.tool_output | type) == "string" then (.tool_output | (fromjson? // .))
    elif has("tool_output") then .tool_output
    else {} end;
  if (.tool_name // "") != "" then
    {tool_name: .tool_name, tool_input: (.tool_input // {}), payload: payload}
  elif (.command // "") != "" then
    {tool_name: "Shell", tool_input: {command: .command}, payload: {stdout: (.output // "")}}
  elif (.file_path // "") != "" and (.edits | type) == "array" then
    {tool_name: "Edit", tool_input: {file_path: .file_path, edits: .edits},
     payload: {}, edit_text: ([.edits[]? | .new_string? // empty | strings] | join("\n"))}
  else empty end' 2>/dev/null)

TOOL_NAME=$(printf '%s' "$NORMALIZED" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
TOOL_INPUT=$(printf '%s' "$NORMALIZED" | jq -c '.tool_input // {}' 2>/dev/null || echo "{}")

# Skip if no tool name (an input none of the shapes above describe)
if [ -z "$TOOL_NAME" ]; then
  exit 0
fi

CONNECTOR_TYPE="cursor.${TOOL_NAME}"

# 1. Record audit entry (fire-and-forget, background). The record is built from
# the normalized input on stdin, so no field of any size becomes a command-line
# argument; the output summary is the first 500 characters of the payload.
# `success` is sent only when the payload says how the tool ended: a numeric
# exitCode (0 is success) or a boolean success. The platform stores an absent
# success as unknown (POST /api/v1/audit/tool-call requires only tool_name).
# Community SaaS with no credential after the bootstrap (the registration did
# not complete: unreachable, refused, rate limited, or out of time): there is
# nothing to authenticate the check with, so it is no usable answer. No request
# is sent (neither the audit record nor the scan; either could only be refused
# as a 401, which would stamp a cooldown), and no stamp is written.
if [ "${AXONFLOW_MODE:-}" = "community-saas" ] && [ -z "$AUTH" ]; then
  axonflow_post_ungoverned "the AxonFlow Community SaaS registration did not succeed, so there is no credential to ask the AxonFlow agent at ${ENDPOINT} with (the agent was not asked)"
fi

# The audit call runs in the background, so it holds none of the hook's
# output open (a host reading the hook's stdout to its end would otherwise
# wait for it), and it gets no more than the hook's time budget leaves.
AUDIT_TIMEOUT_SECONDS=$(axonflow_budget_timeout "$CONFIGURED_TIMEOUT_SECONDS" 1)
if [ "$AUDIT_TIMEOUT_SECONDS" -ge 1 ]; then
(
  printf '%s' "$NORMALIZED" | jq -c \
      '.payload as $r
      | {
        jsonrpc: "2.0",
        id: "hook-audit",
        method: "tools/call",
        params: {
          name: "audit_tool_call",
          arguments: ({
            tool_name: .tool_name,
            caller_name: "cursor",
            tool_type: "cursor",
            input: .tool_input,
            output: {summary: ($r | tojson | .[0:500])},
            error_message: (if ($r | type) == "object" then (($r.stderr // "") | tostring) else "" end)
          } + (if ($r | type) == "object" and ($r.exitCode | type) == "number" then {success: ($r.exitCode == 0)}
               elif ($r | type) == "object" and ($r.success | type) == "boolean" then {success: $r.success}
               else {} end))
        }
      }' 2>/dev/null | curl -sS --max-time "$AUDIT_TIMEOUT_SECONDS" -X POST "${ENDPOINT}/api/v1/mcp-server" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${AUTH_HEADER[@]}" \
    --data-binary @- > /dev/null 2>&1
) >/dev/null 2>&1 &
fi

# 2. Scan tool output for PII/secrets (synchronous — returns context if PII found)
OUTPUT_TEXT=""
case "$TOOL_NAME" in
  Bash|Shell)
    # The payload's stdout and stderr (or output). A string payload is scanned
    # as it came; any other non-object JSON (an array, a number) is scanned as
    # JSON text; an object with none of those fields is scanned whole. A
    # result shape this hook does not know is never silently skipped, and an
    # empty stdout does not hide a stderr.
    OUTPUT_TEXT=$(printf '%s' "$NORMALIZED" | jq -r '.payload
      | if type == "string" then .
        elif type == "object" then
          ([.stdout, .output, .stderr] | map(select(type == "string" and . != "")) | join("\n")) as $t
          | if $t != "" then $t elif length == 0 then empty else tojson end
        elif type == "null" then empty
        else tojson end' 2>/dev/null || echo "")
    # A command with a redirect (echo ... > file) carries its data in the
    # input, not the output, so the command is scanned too, ahead of whatever
    # output the command printed.
    COMMAND=$(printf '%s' "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null || echo "")
    if grep -qE '>>?\s*\S' <<<"$COMMAND"; then
      if [ -z "$OUTPUT_TEXT" ] || [ "$OUTPUT_TEXT" = "null" ]; then
        OUTPUT_TEXT="$COMMAND"
      else
        OUTPUT_TEXT="${COMMAND}
${OUTPUT_TEXT}"
      fi
    fi
    ;;
  Write)
    OUTPUT_TEXT=$(printf '%s' "$TOOL_INPUT" | jq -r '.content // empty' 2>/dev/null || echo "")
    ;;
  Edit)
    OUTPUT_TEXT=$(printf '%s' "$NORMALIZED" | jq -r '.edit_text // .tool_input.new_string // empty' 2>/dev/null || echo "")
    ;;
  NotebookEdit)
    OUTPUT_TEXT=$(printf '%s' "$TOOL_INPUT" | jq -r '.new_source // .cell_content // .content // empty' 2>/dev/null || echo "")
    ;;
  mcp__*|MCP:*)
    OUTPUT_TEXT=$(printf '%s' "$NORMALIZED" | jq -r '.payload | if type == "string" then . else tojson end' 2>/dev/null || echo "")
    ;;
esac

if [ -n "$OUTPUT_TEXT" ] && [ "$OUTPUT_TEXT" != "null" ]; then
  SCAN_REQUEST=$(mktemp)
  SCAN_BODY=$(mktemp)
  SCAN_HEADERS=$(mktemp)
  trap 'rm -f "$SCAN_REQUEST" "$SCAN_BODY" "$SCAN_HEADERS"; axonflow_bootstrap_cleanup' EXIT

  # The output reaches jq on stdin and the body reaches curl as a file, never as
  # a command-line argument: an argument has a size limit, and the tool decides
  # how much output there is. If the request cannot be built, the output was
  # never checked, and the model is told not to use it.
  if ! printf '%s' "$OUTPUT_TEXT" | jq -Rsc --arg ct "$CONNECTOR_TYPE" \
      '{
        jsonrpc: "2.0",
        id: "hook-scan",
        method: "tools/call",
        params: {
          name: "check_output",
          arguments: {
            connector_type: $ct,
            message: .
          }
        }
      }' > "$SCAN_REQUEST" 2>/dev/null || [ ! -s "$SCAN_REQUEST" ]; then
    axonflow_post_unchecked "the check request could not be built"
  fi

  REQUEST_TIMEOUT_SECONDS=$(axonflow_budget_timeout "$CONFIGURED_TIMEOUT_SECONDS" 1)
  if [ "$REQUEST_TIMEOUT_SECONDS" -lt 1 ]; then
    axonflow_post_ungoverned "the hook's ${_AXONFLOW_HOOK_BUDGET_SECONDS}-second time budget ran out before the AxonFlow agent at ${ENDPOINT} could be asked"
  fi
  SCAN_HTTP=$(curl -sS --max-time "$REQUEST_TIMEOUT_SECONDS" \
    -D "$SCAN_HEADERS" -o "$SCAN_BODY" -w '%{http_code}' \
    -X POST "${ENDPOINT}/api/v1/mcp-server" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${AUTH_HEADER[@]}" \
    --data-binary @"$SCAN_REQUEST" 2>/dev/null)
  SCAN_CURL_EXIT=$?

  # No answer arrived: timeout, DNS failure, connection refused, TCP reset.
  if [ "$SCAN_CURL_EXIT" -ne 0 ]; then
    axonflow_post_ungoverned "the AxonFlow agent at ${ENDPOINT} could not be reached (curl exit ${SCAN_CURL_EXIT})"
  fi

  # V1 Plugin Pro: stamp throttle + show the upgrade prompt on envelope
  # responses, and tell the model the output could not be checked.
  if axonflow_handle_envelope_response "$SCAN_HTTP" "$SCAN_BODY" "$SCAN_HEADERS"; then
    axonflow_post_alert "$AXONFLOW_LIMIT_POST_ALERT"
  fi
  # axonflow-enterprise#2275: a 401 stamps a cooldown (the helper; 300 seconds
  # by default) so a tight retry loop can't keep firing the same auth-failing
  # scan request, and the model is told not to use the unchecked output.
  if axonflow_handle_auth_failure "$SCAN_HTTP" "$SCAN_BODY" "$SCAN_HEADERS"; then
    echo "[AxonFlow] $(axonflow_auth_cooldown_note)" >&2
    axonflow_post_alert "$AUTH_ALERT"
  fi
  SCAN_RESPONSE=$(cat "$SCAN_BODY" 2>/dev/null || echo "")

  # The status of an answer the lines above did not settle, read by the table
  # pre-tool-check.sh reads (scripts/lib/failure-posture.sh). The platform's
  # words are cleaned of control characters and quoted as the platform's.
  SCAN_TEXT=$(axonflow_platform_text "$SCAN_RESPONSE")
  SCAN_SAID="${SCAN_TEXT:+; AxonFlow said: \"$SCAN_TEXT\"}"
  SCAN_IS_JSONRPC=$(axonflow_is_jsonrpc_answer "$SCAN_RESPONSE")
  case "$(axonflow_status_class "$SCAN_HTTP" "$SCAN_IS_JSONRPC")" in
    answer) ;;
    limit)
      axonflow_post_unchecked "the AxonFlow agent answered HTTP 429, a request limit${SCAN_SAID}"
      ;;
    too_large)
      axonflow_post_unchecked "the AxonFlow agent refused the check as too large, HTTP 413${SCAN_SAID}"
      ;;
    refused)
      axonflow_post_unchecked "the AxonFlow agent refused the request, HTTP ${SCAN_HTTP}${SCAN_SAID}"
      ;;
    *)
      axonflow_post_ungoverned "the AxonFlow agent answered HTTP ${SCAN_HTTP}${SCAN_SAID}"
      ;;
  esac

  if [ -z "$SCAN_RESPONSE" ]; then
    axonflow_post_ungoverned "the AxonFlow agent answered HTTP ${SCAN_HTTP} with an empty body"
  fi

  # A body that is not exactly one JSON document is no usable answer: a result
  # and an error in one body would each be read by a different line below.
  if ! axonflow_one_json_document "$SCAN_RESPONSE"; then
    axonflow_post_ungoverned "the AxonFlow agent's answer (HTTP ${SCAN_HTTP}) was not one JSON document"
  fi

  # A JSON-RPC error is not a check. Server-internal and parse errors are no
  # usable answer; every other code (auth, method, params, unknown), and an
  # error object with no numeric code or no message, refused it.
  SCAN_RPC_CODE=$(axonflow_jsonrpc_error_code "$SCAN_RESPONSE")
  if [ -n "$SCAN_RPC_CODE" ]; then
    SCAN_RPC_ERROR="${SCAN_TEXT:-no message}"
    case "$SCAN_RPC_CODE" in
      -32603|-32700)
        axonflow_post_ungoverned "the AxonFlow agent answered a server error (code ${SCAN_RPC_CODE}; AxonFlow said: \"${SCAN_RPC_ERROR}\")"
        ;;
      *)
        axonflow_post_unchecked "the AxonFlow agent refused the check, code ${SCAN_RPC_CODE}; AxonFlow said: \"${SCAN_RPC_ERROR}\""
        ;;
    esac
  fi

  SCAN_RESULT=$(echo "$SCAN_RESPONSE" | jq -r '.result.content[0].text // empty' 2>/dev/null || echo "")
  if [ -z "$SCAN_RESULT" ]; then
    # A JSON-RPC result with no tool result carries no decision.
    if echo "$SCAN_RESPONSE" | jq -e 'has("result")' >/dev/null 2>&1; then
      axonflow_post_unchecked "the AxonFlow agent returned no decision"
    fi
    axonflow_post_ungoverned "the AxonFlow agent's answer (HTTP ${SCAN_HTTP}) was not a check result"
  fi

  # A result flagged isError, or one without a boolean `allowed`, is not a
  # decision (ruled 2026-09-14). The Free-tier cap answers this way with its
  # upgrade envelope as the text: the handler still shows the prompt.
  SCAN_IS_ERROR=$(echo "$SCAN_RESPONSE" | jq -r 'if .result.isError == true then "true" else "false" end' 2>/dev/null || echo "false")
  SCAN_HAS_DECISION=$(echo "$SCAN_RESULT" | jq -r 'if (.allowed | type) == "boolean" then "true" else "false" end' 2>/dev/null || echo "false")
  if [ "$SCAN_IS_ERROR" = "true" ] || [ "$SCAN_HAS_DECISION" != "true" ]; then
    if axonflow_handle_envelope_text "$SCAN_RESULT"; then
      axonflow_post_alert "$AXONFLOW_LIMIT_POST_ALERT"
    fi
    SCAN_ERROR=$(axonflow_result_text "$SCAN_RESULT" '.error // empty')
    axonflow_post_unchecked "${SCAN_ERROR:-the AxonFlow agent returned no decision}"
  fi
  # The redacted output is handed to the model whole: its ASCII control
  # characters go, except newline and tab, and it is not cut.
  # Whether a redaction came is decided on the raw value: one made only of
  # control characters still raises the alert.
  REDACTED_RAW=$(printf '%s' "$SCAN_RESULT" | jq -r '.redacted_message // empty' 2>/dev/null)
  REDACTED=$(axonflow_clean_block "$REDACTED_RAW")
  POLICIES_FOUND=$(axonflow_result_text "$SCAN_RESULT" '.policies_evaluated // 0')
  ALLOWED=$(echo "$SCAN_RESULT" | jq -r 'if .allowed == false then "false" else "true" end' 2>/dev/null || echo "true")

  if [ -n "$REDACTED_RAW" ] && [ "$REDACTED_RAW" != "null" ]; then
    axonflow_post_alert "GOVERNANCE ALERT: PII/sensitive data detected in tool output (${POLICIES_FOUND} policies evaluated). You MUST use this redacted version instead of the original: ${REDACTED}"
  elif [ "$ALLOWED" = "false" ]; then
    BLOCK_REASON=$(axonflow_result_text "$SCAN_RESULT" '.block_reason // "Policy violation in tool output"')
    axonflow_post_alert "GOVERNANCE ALERT: Tool output blocked by policy: ${BLOCK_REASON}. Do not use or reference the blocked output in your response."
  fi
fi

# No issues — exit silently
exit 0
