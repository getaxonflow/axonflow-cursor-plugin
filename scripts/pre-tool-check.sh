#!/usr/bin/env bash
# PreToolUse hook — evaluate tool inputs against AxonFlow governance policies.
# Adapted for Cursor IDE from the Claude Code plugin.
#
# Reads tool_name and tool_input from stdin (JSON).
# Calls AxonFlow check_policy via the MCP server endpoint.
#
# Cursor hook exit codes:
#   Exit 0 = allow (no opinion)
#   Exit 2 = block (tool execution prevented)
#   Other non-zero = non-blocking error (tool proceeds)
#
# Fail-open: network failures → exit 0 (allow)
# Fail-closed: auth/config errors → exit 2 (block)

# Fail-open: if dependencies missing, allow the tool call
if ! command -v jq &>/dev/null; then
  exit 0
fi
if ! command -v curl &>/dev/null; then
  exit 0
fi

ENDPOINT="${AXONFLOW_ENDPOINT:-http://localhost:8080}"
AUTH="${AXONFLOW_AUTH:-}"

# Build auth header array safely (avoids word-splitting)
AUTH_HEADER=()
if [ -n "$AUTH" ]; then
  AUTH_HEADER=(-H "Authorization: Basic $AUTH")
fi

# Read hook input from stdin
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}')

# Handle beforeShellExecution format (no tool_name, has command directly)
if [ -z "$TOOL_NAME" ]; then
  DIRECT_COMMAND=$(echo "$INPUT" | jq -r '.command // empty')
  if [ -n "$DIRECT_COMMAND" ]; then
    TOOL_NAME="Shell"
    TOOL_INPUT=$(echo "$INPUT" | jq -c '{command: .command}')
  else
    exit 0
  fi
fi

# Derive connector type: cursor.{ToolName}
CONNECTOR_TYPE="cursor.${TOOL_NAME}"

# Extract the statement to evaluate based on tool type
case "$TOOL_NAME" in
  Bash|Shell)
    STATEMENT=$(echo "$TOOL_INPUT" | jq -r '.command // empty')
    ;;
  Write)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
    CONTENT=$(echo "$TOOL_INPUT" | jq -r '.content // empty' | head -c 2000)
    STATEMENT="${FILE_PATH}"$'\n'"${CONTENT}"
    ;;
  Edit)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
    NEW_STRING=$(echo "$TOOL_INPUT" | jq -r '.new_string // empty' | head -c 2000)
    STATEMENT="${FILE_PATH}"$'\n'"${NEW_STRING}"
    ;;
  NotebookEdit)
    STATEMENT=$(echo "$TOOL_INPUT" | jq -r '.cell_content // .content // empty')
    ;;
  mcp__*)
    STATEMENT=$(echo "$TOOL_INPUT" | jq -r '.query // .statement // .command // .url // empty')
    if [ -z "$STATEMENT" ] || [ "$STATEMENT" = "null" ]; then
      STATEMENT=$(echo "$TOOL_INPUT" | jq -c '.')
    fi
    ;;
  *)
    STATEMENT=$(echo "$TOOL_INPUT" | jq -c '.')
    ;;
esac

# Skip if no statement to evaluate
if [ -z "$STATEMENT" ] || [ "$STATEMENT" = "null" ] || [ "$STATEMENT" = "{}" ]; then
  exit 0
fi

# Call AxonFlow check_policy via MCP server
RESPONSE=$(curl -s --max-time 8 -X POST "${ENDPOINT}/api/v1/mcp-server" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "${AUTH_HEADER[@]}" \
  -d "$(jq -n \
    --arg ct "$CONNECTOR_TYPE" \
    --arg stmt "$STATEMENT" \
    '{
      jsonrpc: "2.0",
      id: "hook-pre",
      method: "tools/call",
      params: {
        name: "check_policy",
        arguments: {
          connector_type: $ct,
          statement: $stmt,
          operation: "execute"
        }
      }
    }')" 2>/dev/null || echo "")

# If AxonFlow is unreachable (empty response = network failure), fail-open
if [ -z "$RESPONSE" ]; then
  exit 0
fi

# Check for JSON-RPC error responses (auth failure, server error, etc.)
# Fail CLOSED on auth/config errors to prevent silent governance bypass.
JSONRPC_ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null || echo "")
if [ -n "$JSONRPC_ERROR" ]; then
  JSONRPC_CODE=$(echo "$RESPONSE" | jq -r '.error.code // 0' 2>/dev/null || echo "0")
  # Auth errors (-32001) and internal errors (-32603) = block
  # Parse errors (-32700) = allow (could be transient)
  if [ "$JSONRPC_CODE" != "-32700" ]; then
    echo "AxonFlow governance error: ${JSONRPC_ERROR}. Fix AxonFlow configuration to restore tool access." >&2
    exit 2
  fi
  exit 0
fi

# Parse the MCP response to get the tool result
TOOL_RESULT=$(echo "$RESPONSE" | jq -r '.result.content[0].text // empty' 2>/dev/null || echo "")
if [ -z "$TOOL_RESULT" ]; then
  exit 0
fi

# Note: jq's // operator treats false as falsy, so .allowed // true returns
# true even when .allowed is false. Use explicit if/else instead.
ALLOWED=$(echo "$TOOL_RESULT" | jq -r 'if .allowed == false then "false" else "true" end' 2>/dev/null || echo "true")
BLOCK_REASON=$(echo "$TOOL_RESULT" | jq -r '.block_reason // empty' 2>/dev/null || echo "")
POLICIES_EVALUATED=$(echo "$TOOL_RESULT" | jq -r '.policies_evaluated // 0' 2>/dev/null || echo "0")

if [ "$ALLOWED" = "false" ]; then
  # Record the blocked attempt in the audit trail (fire-and-forget)
  curl -s --max-time 5 -X POST "${ENDPOINT}/api/v1/mcp-server" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${AUTH_HEADER[@]}" \
    -d "$(jq -n \
      --arg tn "$TOOL_NAME" \
      --arg stmt "$STATEMENT" \
      --arg reason "$BLOCK_REASON" \
      --arg policies "$POLICIES_EVALUATED" \
      '{
        jsonrpc: "2.0",
        id: "hook-audit-blocked",
        method: "tools/call",
        params: {
          name: "audit_tool_call",
          arguments: {
            tool_name: $tn,
            tool_type: "cursor",
            input: {statement: $stmt},
            output: {policy_decision: "blocked", block_reason: $reason, policies_evaluated: $policies},
            success: false,
            error_message: ("Blocked by policy: " + $reason)
          }
        }
      }')" > /dev/null 2>&1 &

  # Cursor: exit 2 = block tool execution. Reason on stderr.
  echo "AxonFlow policy violation: ${BLOCK_REASON} (${POLICIES_EVALUATED} policies evaluated)" >&2
  exit 2
fi

# For shell write commands (echo/printf/cat redirecting to file), also scan
# the content for PII via check_output before allowing.
if [ "$TOOL_NAME" = "Shell" ] || [ "$TOOL_NAME" = "Bash" ]; then
  if echo "$STATEMENT" | grep -qE '(>>?\s*\S|tee\s)'; then
    # Extract the content being written (everything before the redirect)
    WRITE_CONTENT=$(echo "$STATEMENT" | sed -E 's/\s*[12]?>>\s*\S+.*//; s/\s*\|\s*tee\s.*//')
    # Strip the command prefix (echo, printf, cat <<)
    WRITE_CONTENT=$(echo "$WRITE_CONTENT" | sed -E 's/^(echo|printf|cat\s+<<[^ ]*)\s+//; s/^"//; s/"$//')
    if [ -n "$WRITE_CONTENT" ] && [ ${#WRITE_CONTENT} -gt 5 ]; then
      PII_RESPONSE=$(curl -s --max-time 5 -X POST "${ENDPOINT}/api/v1/mcp-server" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        "${AUTH_HEADER[@]}" \
        -d "$(jq -n \
          --arg ct "$CONNECTOR_TYPE" \
          --arg msg "$WRITE_CONTENT" \
          '{
            jsonrpc: "2.0",
            id: "hook-pii",
            method: "tools/call",
            params: {
              name: "check_output",
              arguments: {
                connector_type: $ct,
                message: $msg
              }
            }
          }')" 2>/dev/null || echo "")
      if [ -n "$PII_RESPONSE" ]; then
        PII_RESULT=$(echo "$PII_RESPONSE" | jq -r '.result.content[0].text // empty' 2>/dev/null || echo "")
        REDACTED=$(echo "$PII_RESULT" | jq -r '.redacted_message // empty' 2>/dev/null || echo "")
        PII_ALLOWED=$(echo "$PII_RESULT" | jq -r 'if .allowed == false then "false" else "true" end' 2>/dev/null || echo "true")
        if [ -n "$REDACTED" ] && [ "$REDACTED" != "null" ] && [ "$REDACTED" != "$WRITE_CONTENT" ]; then
          # Respect PII_ACTION: block (default) | warn | log | redact
          PII_ACTION="${PII_ACTION:-redact}"
          case "$PII_ACTION" in
            block)
              echo "AxonFlow: PII detected in file write content. Redacted: ${REDACTED}" >&2
              exit 2
              ;;
            redact)
              # Hooks cannot rewrite shell commands — block and show redacted version
              # so the user can re-submit with safe content.
              echo "AxonFlow: PII detected — use redacted content instead: ${REDACTED}" >&2
              exit 2
              ;;
            warn)
              echo "AxonFlow warning: PII detected in file write content. Redacted: ${REDACTED}" >&2
              # Warn but allow — exit 0
              ;;
            log)
              # Allow silently — server-side handles logging
              ;;
          esac
        fi
      fi
    fi
  fi
fi

# Allowed — exit 0
exit 0
