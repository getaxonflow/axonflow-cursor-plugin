#!/usr/bin/env bash
# Generate auth headers for the AxonFlow MCP server connection.
# Called by Cursor's MCP headersHelper at MCP session start.
#
# Resolution order (ADR-048):
#   1. AXONFLOW_AUTH already exported by the user → use it (self-hosted /
#      enterprise / explicit credential).
#   2. No explicit AXONFLOW_AUTH and no AXONFLOW_ENDPOINT → run the
#      Community-SaaS bootstrap to register against try.getaxonflow.com
#      and load the resulting Basic-auth credential.
#   3. AXONFLOW_AUTH still empty after that (bootstrap couldn't run /
#      degraded) → emit empty headers (Community-mode self-hosted, no auth).

# When this script is invoked by Cursor's MCP headersHelper, AXONFLOW_MODE
# is not yet set; resolve it the same way pre-tool-check.sh does so the
# bootstrap helper makes the right call.
if [ -z "${AXONFLOW_MODE:-}" ]; then
  if [ -z "${AXONFLOW_ENDPOINT:-}" ] && [ -z "${AXONFLOW_AUTH:-}" ]; then
    AXONFLOW_MODE="community-saas"
  else
    AXONFLOW_MODE="self-hosted"
  fi
  export AXONFLOW_MODE
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/community-saas-bootstrap.sh"

# Mode-clarity canary on stderr (NEVER stdout — stdout is the headers JSON).
# Mirrors pre-tool-check.sh's canary so MCP-startup-first sessions also get
# the unambiguous endpoint/mode disclosure.
ENDPOINT_FOR_CANARY="${AXONFLOW_ENDPOINT:-https://try.getaxonflow.com}"
if [ "$AXONFLOW_MODE" = "self-hosted" ] && [ -z "${AXONFLOW_ENDPOINT:-}" ]; then
  ENDPOINT_FOR_CANARY="http://localhost:8080"
fi
echo "[AxonFlow] Connected to AxonFlow at ${ENDPOINT_FOR_CANARY} (mode=${AXONFLOW_MODE})" >&2

# One-time positive disclosure — shared stamp with pre-tool-check.sh so
# whichever path fires first owns the disclosure for this install. MCP
# session can begin before any tool runs, so we surface it here too.
DISCLOSURE_STAMP="${HOME}/.cache/axonflow/cursor-plugin-disclosure-shown"
if [ "$AXONFLOW_MODE" = "community-saas" ] && [ ! -f "$DISCLOSURE_STAMP" ]; then
  mkdir -p "$(dirname "$DISCLOSURE_STAMP")" 2>/dev/null && chmod 0700 "$(dirname "$DISCLOSURE_STAMP")" 2>/dev/null
  cat <<'EOF' >&2
[AxonFlow] Connected to AxonFlow Community SaaS at https://try.getaxonflow.com.
Intended for basic testing and evaluation. For real workflows, real systems,
or sensitive data, we recommend self-hosting AxonFlow from day one:
  https://docs.getaxonflow.com/quickstart
Anonymous telemetry: weekly heartbeat. Opt out: AXONFLOW_TELEMETRY=off
EOF
  : >"$DISCLOSURE_STAMP" 2>/dev/null
fi

# ADR-050 §4: every governed request to the agent carries X-Axonflow-Client
# so the agent can derive request scope (plugin) and validate it against the
# token's aud.scope via HasScope().
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/client-header.sh"

# Per-user authorization token (axonflow-enterprise#2943, epic #2919): resolve
# the admin-minted token (env AXONFLOW_USER_TOKEN wins, else 0600-guarded
# ~/.config/axonflow/user-token.json) so MCP-server traffic carries
# X-User-Token and the platform resolves a validated {identity, role} for the
# developer. Same env-then-file precedence as the hooks. SYNC NOTE: the LIVE
# MCP plane is Cursor's STATIC env expansion in mcp.json (Cursor has no
# headersHelper — cursor#43 tracks that gap; this script is the kept-in-sync
# reference impl). The static plane sends `${AXONFLOW_USER_TOKEN}` raw: it
# cannot read the 0600 file and cannot run the wire-safety strip-check. An
# unset env var expands to an EMPTY header value, which the platform treats
# as absent, so unconfigured users are unaffected on that plane too.
# tests/test-user-token.sh pins this reference impl's behavior;
# tests/test-mcp-json-alignment.sh pins the static mcp.json template.
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/user-token.sh"
resolve_user_token

AUTH="${AXONFLOW_AUTH:-}"
LICENSE_TOKEN="${AXONFLOW_LICENSE_TOKEN:-}"
CLIENT_HEADER="${AXONFLOW_CLIENT_HEADER}"
USER_TOKEN="${AXONFLOW_USER_TOKEN:-}"

# Build the JSON header object via jq when available so token values are
# json-escaped correctly. Without jq, fall back to a string-concat path
# (Authorization + X-Axonflow-Client are simple strings; X-License-Token
# would need careful escaping so we drop it on this fallback — per-call
# hooks still ship it).
if command -v jq &>/dev/null; then
  jq -nc \
    --arg auth "$AUTH" --arg lt "$LICENSE_TOKEN" --arg ch "$CLIENT_HEADER" --arg ut "$USER_TOKEN" \
    '{}
     | (if $auth != "" then . + {"Authorization": ("Basic " + $auth)} else . end)
     | (if $lt   != "" then . + {"X-License-Token": $lt} else . end)
     | (if $ut   != "" then . + {"X-User-Token": $ut} else . end)
     | . + {"X-Axonflow-Client": $ch}'
else
  # X-User-Token is safe to hand-quote on the no-jq path: resolve_user_token
  # only exports values that pass the wire-safety check (no quote/backslash/
  # whitespace/control bytes), and the env path needs no jq. (X-License-Token
  # stays dropped here — its resolver requires jq for the file path and its
  # value is not strip-checked.)
  ut_frag=""
  if [ -n "$USER_TOKEN" ]; then
    ut_frag=", \"X-User-Token\": \"$USER_TOKEN\""
  fi
  if [ -n "$AUTH" ]; then
    echo "{\"Authorization\": \"Basic $AUTH\"${ut_frag}, \"X-Axonflow-Client\": \"$CLIENT_HEADER\"}"
  else
    echo "{\"X-Axonflow-Client\": \"$CLIENT_HEADER\"${ut_frag}}"
  fi
fi
