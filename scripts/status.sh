#!/usr/bin/env bash
# Plugin status — surfaces tenant_id + tier so Pro buyers can paste the
# tenant_id into Stripe Checkout's custom field at /pro and so any user
# can quickly verify which tier they're on.
#
# Cursor does not run plugin code in a long-lived process, and the IDE has
# no command palette for plugin output. The natural surface is a script the
# user invokes from a terminal — directly, or via the /axonflow-status skill,
# which guides the agent to run this script in the integrated terminal.
#
# Output is human-readable on stdout. The bare tenant_id is also printed to
# a fenced "tenant_id:" line near the top so callers can grep one value out
# without parsing the whole block.
#
# Security: the license token is a bearer credential. NEVER print the full
# value. Show "AXON-...XXXX" using only the last 4 chars (defensively
# padded). Mirrors the fix in axonflow-codex-plugin#41 (cmd_status was
# leaking the full token to the terminal).

set -uo pipefail

# Endpoint resolution mirrors pre-tool-check.sh: AXONFLOW_ENDPOINT wins,
# falls back to https://try.getaxonflow.com when neither AXONFLOW_ENDPOINT
# nor AXONFLOW_AUTH is set (community-saas mode).
if [ -z "${AXONFLOW_ENDPOINT:-}" ] && [ -z "${AXONFLOW_AUTH:-}" ]; then
  ENDPOINT="https://try.getaxonflow.com"
  MODE="community-saas"
else
  ENDPOINT="${AXONFLOW_ENDPOINT:-http://localhost:8080}"
  MODE="self-hosted"
fi

CONFIG_DIR="${AXONFLOW_CONFIG_DIR:-${HOME}/.config/axonflow}"
REGISTRATION_FILE="${CONFIG_DIR}/try-registration.json"
LICENSE_TOKEN_FILE="${CONFIG_DIR}/license-token"
UPGRADE_URL="${AXONFLOW_UPGRADE_URL:-https://getaxonflow.com/pro}"

# tenant_id from try-registration.json. Falls back to a clear hint when
# missing so the buyer knows what to do (most paths auto-register on the
# next governed tool call; if the file was deleted, recovery re-mints it).
TENANT_ID=""
TENANT_HINT=""
if [ -f "$REGISTRATION_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    TENANT_ID=$(jq -r '.tenant_id // empty' "$REGISTRATION_FILE" 2>/dev/null || true)
  else
    # jq not on PATH — best-effort grep fallback so status still works in
    # ultra-minimal shells. Returns empty string on no match.
    TENANT_ID=$(grep -oE '"tenant_id"[[:space:]]*:[[:space:]]*"[^"]+"' "$REGISTRATION_FILE" 2>/dev/null \
      | head -1 | sed 's/.*"tenant_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  fi
fi
if [ -z "$TENANT_ID" ]; then
  TENANT_ID="(not registered)"
  TENANT_HINT="Lost your registration? Run scripts/recover-credentials.sh"
fi

# Tier resolution: env first, then file (mode 0600 only — same gate as
# pre-tool-check.sh). NEVER print the full token. Token presence alone
# determines the displayed tier; the platform is the source of truth for
# whether the token is actually valid (this script intentionally does not
# call the agent to verify, so it works offline / pre-bootstrap too).
LICENSE_TOKEN="${AXONFLOW_LICENSE_TOKEN:-}"
TOKEN_SOURCE=""
if [ -n "$LICENSE_TOKEN" ]; then
  TOKEN_SOURCE="env"
elif [ -f "$LICENSE_TOKEN_FILE" ]; then
  TOK_MODE=$(stat -c %a "$LICENSE_TOKEN_FILE" 2>/dev/null) || TOK_MODE=""
  case "$TOK_MODE" in
    ''|*[!0-9]*) TOK_MODE=$(stat -f %Lp "$LICENSE_TOKEN_FILE" 2>/dev/null) || TOK_MODE="" ;;
  esac
  case "$TOK_MODE" in
    ''|*[!0-9]*) TOK_MODE="" ;;
  esac
  if [ "$TOK_MODE" = "600" ] || [ "$TOK_MODE" = "0600" ]; then
    LICENSE_TOKEN=$(tr -d '\r\n' < "$LICENSE_TOKEN_FILE" 2>/dev/null || echo "")
    [ -n "$LICENSE_TOKEN" ] && TOKEN_SOURCE="file"
  else
    # Don't refuse to print status on an unsafe-perms file — just call it
    # out and treat the token as absent for display purposes.
    TOKEN_SOURCE="unsafe-perms"
  fi
fi

if [ -n "$LICENSE_TOKEN" ] && [ "$TOKEN_SOURCE" != "unsafe-perms" ]; then
  TIER="Pro"
  # Defensively pad short tokens so we never reveal the middle bytes — if
  # someone test-injected a 3-char token we still show "****" not "AXO".
  TAIL4="****"
  if [ "${#LICENSE_TOKEN}" -ge 4 ]; then
    TAIL4="${LICENSE_TOKEN: -4}"
  fi
  TOKEN_DISPLAY="set (AXON-...${TAIL4}, source=${TOKEN_SOURCE})"
else
  TIER="Free"
  if [ "$TOKEN_SOURCE" = "unsafe-perms" ]; then
    TOKEN_DISPLAY="present at $LICENSE_TOKEN_FILE but refused (unsafe permissions; chmod 0600)"
  else
    TOKEN_DISPLAY="unset"
  fi
fi

cat <<EOF
AxonFlow Cursor plugin — status

  endpoint           ${ENDPOINT}
  mode               ${MODE}
  tenant_id:         ${TENANT_ID}
  registration file  ${REGISTRATION_FILE}
  license token      ${TOKEN_DISPLAY}
  tier               ${TIER}
  upgrade            ${UPGRADE_URL}
EOF

if [ -n "$TENANT_HINT" ]; then
  printf '\n  hint: %s\n' "$TENANT_HINT"
fi

if [ "$TIER" = "Free" ]; then
  cat <<EOF

To upgrade to Pro, copy your tenant_id above, visit
${UPGRADE_URL}, paste the tenant_id into the "Your AxonFlow tenant ID"
field, and complete checkout. The license token arrives by email; activate it
with one of:

  export AXONFLOW_LICENSE_TOKEN=AXON-...    # current shell
  printf '%s' AXON-... > ${LICENSE_TOKEN_FILE} && chmod 0600 ${LICENSE_TOKEN_FILE}

Token resolution order: AXONFLOW_LICENSE_TOKEN env var, then
${LICENSE_TOKEN_FILE} (mode 0600 only).
EOF
fi

exit 0
