#!/usr/bin/env bash
# Plugin status — surfaces tenant_id + tier (with Pro expiry date) so Pro
# buyers can paste the tenant_id into Stripe Checkout's custom field at
# /pro and so any user can quickly verify which tier they're on AND when
# their Pro license expires.
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
#
# JWT exp parsing: the AXON- prefix wraps a standard JWT (header.payload.
# signature). We extract the `exp` claim from the payload to compute the
# tier-line shape:
#   - Pro active   → "tier   Pro (expires YYYY-MM-DD, N days remaining)"
#   - Pro lapsed   → "tier   Free (Pro expired YYYY-MM-DD — visit <url> to renew)"
#   - Free         → "tier   Free (no Pro license configured)"
# Signature is NOT validated here — that's the platform's job.

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

# AXONFLOW_CONFIG_DIR is a status-side override only. The rest of the plugin
# (community-saas-bootstrap.sh, recover-credentials.sh, pre-tool-check.sh)
# currently hardcodes ${HOME}/.config/axonflow, so setting AXONFLOW_CONFIG_DIR
# only changes where THIS script looks. Useful for test harnesses and for
# inspecting an alternate-HOME install; not a substitute for the canonical
# location.
CONFIG_DIR="${AXONFLOW_CONFIG_DIR:-${HOME}/.config/axonflow}"
REGISTRATION_FILE="${CONFIG_DIR}/try-registration.json"
LICENSE_TOKEN_FILE="${CONFIG_DIR}/license-token"
UPGRADE_URL="${AXONFLOW_UPGRADE_URL:-https://www.getaxonflow.com/pricing/}"

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

# extract_jwt_exp <token>  →  prints unix-epoch integer to stdout, exits 0
# on success, non-zero on any parse failure. Pure stdout/stderr; never
# raises. The caller decides how to render a parse failure.
#
# AxonFlow license tokens are formatted `AXON-<JWT>` where <JWT> is a
# standard `header.payload.signature` triple. We base64url-decode the
# middle segment, then look for `"exp":<digits>`. Signature is NEVER
# validated here — display only.
extract_jwt_exp() {
  local tok="$1"
  [ -n "$tok" ] || return 1
  local jwt="${tok#AXON-}"
  local payload
  payload=$(printf '%s' "$jwt" | cut -d. -f2)
  [ -n "$payload" ] || return 1
  payload=$(printf '%s' "$payload" | tr '_-' '/+')
  local pad=$(( 4 - ${#payload} % 4 ))
  if [ "$pad" -ne 4 ]; then
    payload="${payload}$(printf '=%.0s' $(seq 1 "$pad"))"
  fi
  local decoded
  decoded=$(printf '%s' "$payload" | base64 -d 2>/dev/null) \
    || decoded=$(printf '%s' "$payload" | base64 -D 2>/dev/null) \
    || return 1
  [ -n "$decoded" ] || return 1
  local exp
  exp=$(printf '%s' "$decoded" | grep -oE '"exp"[[:space:]]*:[[:space:]]*[0-9]+' | head -1 | grep -oE '[0-9]+$')
  [ -n "$exp" ] || return 1
  printf '%s' "$exp"
}

# format_unix_to_date <unix-epoch>  →  prints YYYY-MM-DD (UTC) to stdout.
format_unix_to_date() {
  local epoch="$1"
  [ -n "$epoch" ] || return 1
  local out
  out=$(date -u -d "@${epoch}" +%Y-%m-%d 2>/dev/null) \
    || out=$(date -u -r "${epoch}" +%Y-%m-%d 2>/dev/null) \
    || return 1
  printf '%s' "$out"
}

# Compute the tier line. Three branches (matching codex / claude / openclaw):
#   1. No token resolved          → "Free (no Pro license configured)"
#   2. Token resolved + exp parsed:
#       2a. exp in future         → "Pro (expires YYYY-MM-DD, N days remaining)"
#       2b. exp in past           → "Free (Pro expired YYYY-MM-DD — visit <url> to renew)"
#   3. Token resolved + exp NOT parseable
#                                 → "Pro (expires UNKNOWN — could not parse token)"
TIER_LINE="Free (no Pro license configured)"
PRO_EXPIRED_FLAG=0
TIER_KIND="free"

if [ -n "$LICENSE_TOKEN" ] && [ "$TOKEN_SOURCE" != "unsafe-perms" ]; then
  # Defensively pad short tokens so we never reveal the middle bytes — if
  # someone test-injected a 3-char token we still show "****" not "AXO".
  TAIL4="****"
  if [ "${#LICENSE_TOKEN}" -ge 4 ]; then
    TAIL4="${LICENSE_TOKEN: -4}"
  fi
  TOKEN_DISPLAY="set (AXON-...${TAIL4}, source=${TOKEN_SOURCE})"

  EXP_EPOCH=$(extract_jwt_exp "$LICENSE_TOKEN" 2>/dev/null || true)
  if [ -n "$EXP_EPOCH" ]; then
    EXP_DATE=$(format_unix_to_date "$EXP_EPOCH" 2>/dev/null || true)
    if [ -n "$EXP_DATE" ]; then
      NOW_EPOCH=$(date -u +%s)
      if [ "$EXP_EPOCH" -gt "$NOW_EPOCH" ]; then
        SECS_LEFT=$(( EXP_EPOCH - NOW_EPOCH ))
        DAYS_LEFT=$(( (SECS_LEFT + 86399) / 86400 ))
        TIER_LINE="Pro (expires ${EXP_DATE}, ${DAYS_LEFT} days remaining)"
        TIER_KIND="pro"
      else
        TIER_LINE="Free (Pro expired ${EXP_DATE} — visit ${UPGRADE_URL} to renew)"
        TIER_KIND="pro-expired"
        PRO_EXPIRED_FLAG=1
      fi
    else
      TIER_LINE="Pro (expires UNKNOWN — could not parse token)"
      TIER_KIND="pro"
    fi
  else
    # Token shape valid but JWT parse failed — treat as Pro for display.
    # The platform is the source of truth; if the token is junk the next
    # governed call will surface the 401.
    TIER_LINE="Pro (expires UNKNOWN — could not parse token)"
    TIER_KIND="pro"
  fi
else
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
  tier               ${TIER_LINE}
EOF

# Only show the upgrade URL on Free tiers (active Pro users don't need it
# in their face). Pro-expired users do want to see it — it's now embedded
# in the tier line itself ("visit <url> to renew") so we suppress the
# duplicate `upgrade` line for them too.
if [ "$TIER_KIND" = "free" ]; then
  printf '  upgrade            %s\n' "${UPGRADE_URL}"
fi

if [ -n "$TENANT_HINT" ]; then
  printf '\n  hint: %s\n' "$TENANT_HINT"
fi

if [ "$TIER_KIND" = "free" ]; then
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
elif [ "$PRO_EXPIRED_FLAG" -eq 1 ]; then
  cat <<EOF

  Your Pro license token is on disk but its 'exp' has passed; the plugin will
  not forward an expired token. After buying a renewal, replace the token:

    export AXONFLOW_LICENSE_TOKEN=AXON-...    # current shell
    printf '%s' AXON-... > ${LICENSE_TOKEN_FILE} && chmod 0600 ${LICENSE_TOKEN_FILE}
EOF
fi

exit 0
