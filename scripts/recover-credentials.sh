#!/usr/bin/env bash
# Email-recovery helper for AxonFlow plugin credentials (W3 free tier).
#
# Cursor plugins do not run a long-lived process and Cursor itself does not
# expose a "plugin command" surface, so the natural recovery surface is a
# script the user invokes from a terminal — either directly, or via the
# /recover-credentials chat skill, which guides the agent to run this script
# and prompt the user for the magic-link token.
#
# Flow (matches platform PR #1850):
#   1. Prompt for the email the tenant was registered with.
#   2. POST /api/v1/recover {"email": "<addr>"} — server always returns 202
#      regardless of whether the email is on file (anti-enumeration).
#   3. Tell the user to open the magic link from their inbox; either paste
#      the full URL (we extract the token) or paste the bare token.
#   4. POST /api/v1/recover/verify {"token": "<hex>"}.
#   5. Persist the returned {tenant_id, secret} as ~/.config/axonflow/try-registration.json
#      (mode 0600 inside a 0700 directory) — same shape the community-saas
#      bootstrap writes, so the existing pre-tool-check loader picks it up
#      with no other changes.
#   6. Print a one-line confirmation.
#
# Non-interactive use (test harness): set AXONFLOW_RECOVER_EMAIL and
# AXONFLOW_RECOVER_TOKEN to drive the flow without stdin prompts.
#
# Endpoint resolution mirrors pre-tool-check.sh: AXONFLOW_ENDPOINT wins,
# falls back to https://try.getaxonflow.com if neither AXONFLOW_ENDPOINT
# nor AXONFLOW_AUTH is set.

set -uo pipefail

# Dependencies — bail with a clear message rather than failing later in the
# pipeline. Recovery is rare and user-initiated; we want a hard failure with
# a fix path, not a silent no-op.
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "recover-credentials: $cmd is required but not on PATH" >&2
    exit 2
  fi
done

if [ -z "${AXONFLOW_ENDPOINT:-}" ] && [ -z "${AXONFLOW_AUTH:-}" ]; then
  ENDPOINT="https://try.getaxonflow.com"
  MODE="community-saas"
else
  ENDPOINT="${AXONFLOW_ENDPOINT:-http://localhost:8080}"
  MODE="self-hosted"
fi

CONFIG_DIR="${HOME}/.config/axonflow"
REGISTRATION_FILE="${CONFIG_DIR}/try-registration.json"

# Step 1: collect email. AXONFLOW_RECOVER_EMAIL is the test-harness
# override so tests can drive the flow non-interactively.
EMAIL="${AXONFLOW_RECOVER_EMAIL:-}"
if [ -z "$EMAIL" ]; then
  if [ ! -t 0 ]; then
    echo "recover-credentials: stdin not a tty and AXONFLOW_RECOVER_EMAIL not set" >&2
    exit 2
  fi
  printf 'Email registered with AxonFlow: ' >&2
  read -r EMAIL
fi
if [ -z "$EMAIL" ]; then
  echo "recover-credentials: empty email; aborting" >&2
  exit 2
fi

echo "[recover-credentials] endpoint=$ENDPOINT mode=$MODE email=$EMAIL" >&2

# ADR-050 §4: identify ourselves to the agent so it can derive request scope.
# /api/v1/recover is unauthenticated by design but the header still belongs.
# shellcheck disable=SC1091
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
. "${SCRIPT_DIR}/client-header.sh"

# Step 2: POST /api/v1/recover. Always 202 — anti-enumeration. The
# response body is intentionally generic; we don't surface anything from it
# to the user (would otherwise leak whether the email is on file).
RECOVER_HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST "$ENDPOINT/api/v1/recover" \
  -H "Content-Type: application/json" \
  -H "X-Axonflow-Client: ${AXONFLOW_CLIENT_HEADER}" \
  -d "$(jq -nc --arg e "$EMAIL" '{email: $e}')" 2>/dev/null)
if [ "$RECOVER_HTTP" != "202" ]; then
  # Network failure or unexpected status. Keep going — the user might
  # have a stale token from a previous request and we don't want to
  # block recovery on a transient blip. But surface what we saw.
  echo "[recover-credentials] WARN: /api/v1/recover returned HTTP $RECOVER_HTTP (expected 202)" >&2
fi

cat <<EOF >&2

Check your inbox for an email from AxonFlow. Open the magic link and
either paste the full URL here, or paste just the token portion (the
hex string after token=).

The token is consumed once — paste it before requesting another email,
or the new request will invalidate the link you're holding.

EOF

# Step 3: collect token. Accept either a bare token or the full
# magic-link URL — we slice off the token= query parameter when present.
RAW="${AXONFLOW_RECOVER_TOKEN:-}"
if [ -z "$RAW" ]; then
  if [ ! -t 0 ]; then
    echo "recover-credentials: stdin not a tty and AXONFLOW_RECOVER_TOKEN not set" >&2
    exit 2
  fi
  printf 'Magic link or token: ' >&2
  read -r RAW
fi

# Strip URL prefix and any trailing query params after the token. Token
# format from the platform is hex (>=32 chars); we don't validate that
# here because the server is the source of truth — let it 401 if malformed.
TOKEN="$RAW"
case "$TOKEN" in
  *token=*) TOKEN="${TOKEN##*token=}";;
esac
TOKEN="${TOKEN%%[!0-9a-fA-F]*}"
if [ -z "$TOKEN" ]; then
  echo "recover-credentials: could not extract a token from input" >&2
  exit 2
fi

# Step 4: POST /api/v1/recover/verify. The server consumes the token here
# (one-shot) and returns the new credentials.
VERIFY_RESP=$(curl -sS --max-time 10 \
  -X POST "$ENDPOINT/api/v1/recover/verify" \
  -H "Content-Type: application/json" \
  -H "X-Axonflow-Client: ${AXONFLOW_CLIENT_HEADER}" \
  -d "$(jq -nc --arg t "$TOKEN" '{token: $t}')" \
  -w "\n%{http_code}" 2>/dev/null)
VERIFY_CODE=$(printf '%s' "$VERIFY_RESP" | tail -n1)
VERIFY_BODY=$(printf '%s' "$VERIFY_RESP" | sed '$d')

if [ "$VERIFY_CODE" != "200" ]; then
  echo "recover-credentials: verify failed with HTTP $VERIFY_CODE" >&2
  echo "  body: $VERIFY_BODY" >&2
  echo "  Common causes: token already used, token expired, or the email had no tenant on file." >&2
  exit 1
fi

NEW_TENANT_ID=$(printf '%s' "$VERIFY_BODY" | jq -r '.tenant_id // empty')
NEW_SECRET=$(printf '%s' "$VERIFY_BODY" | jq -r '.secret // empty')
NEW_EXPIRES_AT=$(printf '%s' "$VERIFY_BODY" | jq -r '.expires_at // empty')
NEW_ENDPOINT=$(printf '%s' "$VERIFY_BODY" | jq -r '.endpoint // empty')
NEW_EMAIL=$(printf '%s' "$VERIFY_BODY" | jq -r '.email // empty')

if [ -z "$NEW_TENANT_ID" ] || [ -z "$NEW_SECRET" ]; then
  echo "recover-credentials: verify response missing tenant_id or secret" >&2
  echo "  body: $VERIFY_BODY" >&2
  exit 1
fi

# Step 5: persist as the same try-registration.json file the bootstrap
# already loads from. Atomic write + 0600 perms inside a 0700 directory.
mkdir -p "$CONFIG_DIR" 2>/dev/null
chmod 0700 "$CONFIG_DIR" 2>/dev/null
TMP="${REGISTRATION_FILE}.tmp.$$"
if (umask 077 && printf '%s' "$VERIFY_BODY" > "$TMP" 2>/dev/null) && mv -f "$TMP" "$REGISTRATION_FILE" 2>/dev/null; then
  :
else
  echo "recover-credentials: failed to write $REGISTRATION_FILE" >&2
  rm -f "$TMP" 2>/dev/null
  exit 1
fi

# Step 6: confirm to the user. Echo nothing sensitive — just the tenant_id,
# the email, and where the file landed.
cat <<EOF >&2

✓ Credentials recovered.
  tenant_id: $NEW_TENANT_ID
  email:     $NEW_EMAIL
  endpoint:  ${NEW_ENDPOINT:-$ENDPOINT}
  expires:   ${NEW_EXPIRES_AT:-unknown}
  saved to:  $REGISTRATION_FILE (mode 0600)

The community-saas bootstrap will pick this up automatically on the next
governed tool call. No re-export of AXONFLOW_AUTH is required.
EOF

# stdout: the tenant_id, so callers can capture it with command substitution
# without parsing the human-readable confirmation.
printf '%s\n' "$NEW_TENANT_ID"
exit 0
