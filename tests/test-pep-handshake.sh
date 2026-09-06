#!/usr/bin/env bash
# Unit test for scripts/pep-handshake.sh — the ADR-065 capability handshake
# (getaxonflow/axonflow-enterprise#3763).
#
# THE GOLDEN VECTOR IS THE POINT. This repository is public and the wire
# contract lives in a private one, so pep-handshake.sh is a HAND TRANSCRIPTION
# of a wire format - the drift class that bit five SDKs in
# axonflow-enterprise#3603. The expected string below was captured from the
# PLATFORM's own shipped encoder (contract.PEPHandshake.Encode), not
# regenerated from this script's output, so the two implementations are
# compared with each other rather than one with itself.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${PLUGIN_DIR}/scripts/pep-handshake.sh"
HELPER_PATH="${PLUGIN_DIR}/scripts/mcp-auth-headers.sh"

GOLDEN="eyJwcm9maWxlX3ZlcnNpb24iOjEsInBlcF9pZCI6ImN1cnNvci1wbHVnaW4iLCJhdWRpZW5jZSI6ImF4b25mbG93LWRlY2lzaW9uLXByb29mIiwiY2FwYWJpbGl0aWVzIjpbXX0"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }

# --- the encoding matches the platform's own encoder, byte for byte ---------
ACTUAL=$(
  unset AXONFLOW_PEP_HANDSHAKE
  export AXONFLOW_PEP_AUDIENCE="axonflow-decision-proof"
  . "$SCRIPT_PATH"
  echo "${AXONFLOW_PEP_HANDSHAKE:-}"
)
if [ "$ACTUAL" = "$GOLDEN" ]; then
  pass "the encoding matches the platform's own encoder byte for byte"
else
  fail "encoding disagrees with the platform encoder; a mismatch here is a plugin the platform will refuse in the field. got '$ACTUAL' want '$GOLDEN'"
fi

# --- the decoded document declares [] and carries no identity claim ---------
if command -v python3 >/dev/null 2>&1; then
  DOC=$(printf '%s' "$ACTUAL" | python3 -c 'import sys,base64;s=sys.stdin.read().strip();print(base64.urlsafe_b64decode(s+"="*(-len(s)%4)).decode())')
  # An OMITTED capabilities member is MALFORMED to the platform and refuses the
  # request; [] is the declaration "I discharge nothing". Different facts.
  if [[ "$DOC" == *'"capabilities":[]'* ]]; then
    pass "an empty declaration serialises as [], never as an absent member"
  else
    fail "capabilities is not an empty array: $DOC"
  fi
  # A PEP may declare what it CAN DO, never who it is or what it is entitled to.
  if [[ "$DOC" != *'"edition"'* && "$DOC" != *'"tier"'* && "$DOC" != *'"license"'* && "$DOC" != *'"realm"'* ]]; then
    pass "no identity or entitlement member reaches the wire"
  else
    fail "the document carries an identity or entitlement member: $DOC"
  fi
else
  echo "  SKIP: python3 not on PATH (decoded-shape assertions)"
fi

# --- unset audience presents nothing at all --------------------------------
ACTUAL_UNSET=$(
  unset AXONFLOW_PEP_HANDSHAKE AXONFLOW_PEP_AUDIENCE
  . "$SCRIPT_PATH"
  echo "${AXONFLOW_PEP_HANDSHAKE:-}"
)
if [ -z "$ACTUAL_UNSET" ]; then
  pass "an unconfigured install builds no handshake at all"
else
  fail "expected empty, got '$ACTUAL_UNSET'"
fi

# --- a malformed audience refuses to build, loudly -------------------------
for BAD in "has spaces" "-leading-hyphen" "$(printf 'a%.0s' {1..129})"; do
  OUT=$(
    unset AXONFLOW_PEP_HANDSHAKE
    export AXONFLOW_PEP_AUDIENCE="$BAD"
    . "$SCRIPT_PATH" 2>/dev/null
    echo "${AXONFLOW_PEP_HANDSHAKE:-}"
  )
  if [ -z "$OUT" ]; then
    pass "a malformed audience builds no handshake ('${BAD:0:20}')"
  else
    fail "malformed audience '${BAD:0:20}' produced '$OUT'; the platform would 400 every governed call"
  fi
done

# --- a MULTI-LINE audience is rejected, and grep alone would not do it -------
# `grep` is LINE-BASED: an audience of "aud\nhas spaces" matches on its FIRST
# line and passes a `^...$` test that looks airtight, and the document then
# carries a raw newline inside a JSON string - invalid JSON, which the platform
# refuses as a malformed handshake on every governed call. Regression-pinned
# because the equality-against-a-stripped-copy guard is the only thing catching
# it, and a future simplification would delete exactly that line.
MULTI=$(unset AXONFLOW_PEP_HANDSHAKE; export AXONFLOW_PEP_AUDIENCE="$(printf 'aud\nhas spaces')"; . "$SCRIPT_PATH" 2>/dev/null; echo "${AXONFLOW_PEP_HANDSHAKE:-}")
if [ -z "$MULTI" ]; then
  pass "a multi-line audience builds no handshake (grep alone would have admitted it)"
else
  fail "a multi-line audience produced '$MULTI'; the document carries a raw newline and the platform would refuse every governed call"
fi

# --- the MCP headers helper OMITS the header when unconfigured -------------
# ABSENT, not empty. A PRESENT-but-empty value is MALFORMED to the platform and
# refuses the request, which an absent header does not - so this is what keeps
# every unconfigured install working exactly as before.
if command -v jq >/dev/null 2>&1; then
  HEADERS_UNSET=$(unset AXONFLOW_PEP_AUDIENCE; AXONFLOW_MODE=self-hosted bash "$HELPER_PATH" 2>/dev/null)
  if ! jq -e 'has("X-Axonflow-PEP-Handshake")' <<<"$HEADERS_UNSET" >/dev/null 2>&1; then
    pass "the MCP headers helper omits the handshake header entirely when unconfigured"
  else
    fail "unconfigured helper emitted the handshake key: $HEADERS_UNSET"
  fi

  HEADERS_SET=$(AXONFLOW_PEP_AUDIENCE="axonflow-decision-proof" AXONFLOW_MODE=self-hosted bash "$HELPER_PATH" 2>/dev/null)
  if [ "$(jq -r '."X-Axonflow-PEP-Handshake" // ""' <<<"$HEADERS_SET")" = "$GOLDEN" ]; then
    pass "the MCP headers helper emits the declaration when configured"
  else
    fail "configured helper did not emit the expected handshake: $HEADERS_SET"
  fi
else
  echo "  SKIP: jq not on PATH (headers-helper assertions)"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
