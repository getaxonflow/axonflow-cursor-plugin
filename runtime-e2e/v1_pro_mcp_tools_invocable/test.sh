#!/usr/bin/env bash
# V1 Plugin Pro MCP-tools-invocable runtime proof for the Cursor plugin.
#
# Drives the SAME wire path Cursor IDE uses (the plugin's mcp.json
# pointed at the agent's /api/v1/mcp-server endpoint, with the same
# X-Axonflow-Client header Cursor sends — verified live in the sister
# `mcp-session-headers` test) against the live AxonFlow agent at
# https://try.getaxonflow.com.
#
# Per HARD RULE #0: every byte through the test came from the real
# plugin's MCP wire shape, real agent on prod (Community SaaS), real
# registered tenant. No fixtures.
#
# The 5 V1 Pro MCP tools per PRD §V1:
#
#   1. axonflow_list_pro_features        Free callable, returns 5 differentiators + buy_url
#   2. axonflow_get_cost_estimate        Pro-only — HIDDEN from Free tools/list, but if invoked
#                                        by name returns envelope (isError:true, feature_pro_only)
#   3. axonflow_request_approval         Free 1/7d quota, returns approval_id non-empty on first call
#   4. axonflow_create_tenant_policy     Free 2-active max, returns policy_id non-empty
#   5. axonflow_get_tenant_id            Free callable, returns matching tenant_id + upgrade_url
#
# This test drives the MCP wire DIRECTLY (curl + JSON-RPC). The
# operator-driven companion `MANUAL_RUNBOOK.md` covers the IDE chat
# panel (driving Cursor itself); this script gives CI a deterministic
# automated check on the same wire shape.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

UTC_TS=$(date -u +%Y%m%dT%H%M%SZ)
EVIDENCE="$SCRIPT_DIR/EVIDENCE/$UTC_TS"
mkdir -p "$EVIDENCE"

AGENT_URL="${AGENT_URL:-https://try.getaxonflow.com}"

for tool in jq curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not on PATH"
    exit 0
  fi
done

if ! curl -sSf -o /dev/null --max-time 10 "${AGENT_URL}/health"; then
  echo "SKIP: agent /health not reachable at $AGENT_URL"
  exit 0
fi

# ---------------------------------------------------------------------------
# Tenant resolution: env > register fresh
# ---------------------------------------------------------------------------
TENANT="${TENANT:-}"
SECRET="${SECRET:-}"
REG_BODY_TMP=""
cleanup_on_exit() {
  [ -n "$REG_BODY_TMP" ] && rm -f "$REG_BODY_TMP" 2>/dev/null
  return 0
}
trap cleanup_on_exit EXIT

if [ -z "$TENANT" ] || [ -z "$SECRET" ]; then
  EMAIL_TAG=$(date -u +%s)
  REG_BODY_TMP=$(mktemp)
  REG_HTTP=$(curl -sS -o "$REG_BODY_TMP" -w '%{http_code}' \
    -X POST "${AGENT_URL}/api/v1/register" \
    -H 'Content-Type: application/json' \
    -d "{\"label\":\"v1-pro-cursor-mcp-${EMAIL_TAG}\",\"email\":\"e2e+cursor-mcp-${EMAIL_TAG}@getaxonflow.com\"}" 2>/dev/null) || REG_HTTP="000"
  if [ "$REG_HTTP" != "200" ] && [ "$REG_HTTP" != "201" ]; then
    echo "SKIP: tenant registration HTTP=$REG_HTTP. Pass TENANT=... SECRET=... env to reuse an existing tenant."
    cat "$REG_BODY_TMP" 2>/dev/null
    exit 0
  fi
  TENANT=$(jq -r '.tenant_id' "$REG_BODY_TMP")
  SECRET=$(jq -r '.secret' "$REG_BODY_TMP")
  echo "Registered: $TENANT"
fi

# Idempotency: best-effort clear prior HITL approvals + dynamic policies.
if command -v aws >/dev/null 2>&1; then
  DB_LIB="${PLUGIN_DIR}/../axonflow-enterprise/runtime-e2e/v1_paid_tier_staging/lib/db_helpers.sh"
  if [ -f "$DB_LIB" ]; then
    case "$AGENT_URL" in
      *try-staging*) STACK_PREFIX='axonflow-community-saas-staging-2' ;;
      *try.getaxonflow*) STACK_PREFIX='axonflow-community-saas-2' ;;
      *) STACK_PREFIX='' ;;
    esac
    if [ -n "$STACK_PREFIX" ]; then
      DETECTED_STACK=$(aws cloudformation list-stacks --region us-east-1 \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
        --query "StackSummaries[?starts_with(StackName, '$STACK_PREFIX') && !contains(StackName, 'staging-2') && !contains(StackName, 'alarm') && !contains(StackName, 'synth')].StackName" \
        --output text 2>/dev/null | tr '\t' '\n' | sort -r | head -1)
      DETECTED_TASK=$(aws ecs list-tasks --region us-east-1 --cluster "${DETECTED_STACK}-cluster" \
        --service-name "${DETECTED_STACK}-orchestrator-service" --query 'taskArns[0]' --output text 2>/dev/null)
      DETECTED_DB=$(aws rds describe-db-instances --region us-east-1 \
        --query "DBInstances[?DBInstanceIdentifier == '${DETECTED_STACK}-db'].Endpoint.Address" \
        --output text 2>/dev/null | head -1)
      DETECTED_PASS=$(aws secretsmanager get-secret-value --region us-east-1 \
        --secret-id "${DETECTED_STACK}-db-password" --query SecretString --output text 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])' 2>/dev/null)
      if [ -n "$DETECTED_STACK" ] && [ -n "$DETECTED_TASK" ] && [ -n "$DETECTED_DB" ] && [ -n "$DETECTED_PASS" ]; then
        export STACK="$DETECTED_STACK" ORCH_TASK="$DETECTED_TASK" DB_HOST="$DETECTED_DB" DB_PASS="$DETECTED_PASS" REGION=us-east-1
        # shellcheck disable=SC1090
        source "$DB_LIB"
        echo "Idempotency: clear hitl_approval_queue + dynamic_policies for $TENANT"
        db_run_sql "DELETE FROM hitl_approval_queue WHERE tenant_id = '${TENANT}'; DELETE FROM dynamic_policies WHERE tenant_id = '${TENANT}';" >/dev/null 2>&1 || true
      fi
    fi
  fi
fi

# Read the cursor-plugin client header out of the installed mcp.json's
# convention (cursor-plugin/<version>) so the wire shape matches what
# Cursor IDE actually sends — proven in mcp-session-headers/EVIDENCE.md.
PLUGIN_VERSION="$(jq -r '.version // "unknown"' "$PLUGIN_DIR/.cursor-plugin/plugin.json" 2>/dev/null || echo unknown)"
CLIENT_HEADER="cursor-plugin/${PLUGIN_VERSION}"

AUTH=$(printf '%s:%s' "$TENANT" "$SECRET" | base64 | tr -d '\n')

# ---------------------------------------------------------------------------
# MCP session — same lifecycle Cursor IDE drives:
#   POST initialize (gets mcp-session-id) → POST notifications/initialized
#   → tools/list → tools/call per tool.
# ---------------------------------------------------------------------------
INIT_RESP=$(mktemp)
curl -sS -i "${AGENT_URL}/api/v1/mcp-server" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Basic $AUTH" \
  -H "X-Axonflow-Client: $CLIENT_HEADER" \
  --max-time 15 \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"cursor-runtime-e2e","version":"1"}}}' \
  > "$INIT_RESP"

SID=$(grep -i '^mcp-session-id:' "$INIT_RESP" | awk '{print $2}' | tr -d '\r')
if [ -z "$SID" ]; then
  echo "FAIL: initialize did not return mcp-session-id"
  cat "$INIT_RESP"
  rm -f "$INIT_RESP"
  exit 1
fi
rm -f "$INIT_RESP"
echo "MCP session: $SID"

curl -sS "${AGENT_URL}/api/v1/mcp-server" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Basic $AUTH" \
  -H "mcp-session-id: $SID" \
  -H "X-Axonflow-Client: $CLIENT_HEADER" \
  --max-time 10 \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' > /dev/null

# tools/list — captures what the agent advertises to a Free tenant.
curl -sS "${AGENT_URL}/api/v1/mcp-server" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Basic $AUTH" \
  -H "mcp-session-id: $SID" \
  -H "X-Axonflow-Client: $CLIENT_HEADER" \
  --max-time 10 \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > "$EVIDENCE/tools_list.json"

# ---------------------------------------------------------------------------
# Per-tool driver
# ---------------------------------------------------------------------------
PASS=true
fail() { echo "FAIL: $1"; PASS=false; }

call_tool() {
  local tool="$1" args="$2"
  local out_file="$EVIDENCE/${tool}.json"
  curl -sS "${AGENT_URL}/api/v1/mcp-server" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Basic $AUTH" \
    -H "mcp-session-id: $SID" \
    -H "X-Axonflow-Client: $CLIENT_HEADER" \
    --max-time 20 \
    -d "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"tools/call\",\"params\":{\"name\":\"${tool}\",\"arguments\":${args}}}" > "$out_file"
  echo "  $tool: $(wc -c <"$out_file") bytes captured"
}

# Test 1 — list_pro_features (Free callable, must return 5 differentiators)
echo
echo "================ tool 1: axonflow_list_pro_features ================"
call_tool "axonflow_list_pro_features" "{}"
LIST_BODY=$(jq -r '.result.content[0].text // empty' "$EVIDENCE/axonflow_list_pro_features.json")
LIST_SUCCESS=$(echo "$LIST_BODY" | jq -r '.success // empty' 2>/dev/null)
if [ "$LIST_SUCCESS" != "true" ]; then
  fail "axonflow_list_pro_features: missing 'success: true' (axonflow-enterprise#1989)"
fi
if ! echo "$LIST_BODY" | grep -qF 'differentiators'; then
  fail "axonflow_list_pro_features: missing 'differentiators'"
fi
DIFF_COUNT=$(echo "$LIST_BODY" | jq -r '.differentiators | length // 0' 2>/dev/null)
if [ "$DIFF_COUNT" != "5" ]; then
  fail "axonflow_list_pro_features: differentiators length = $DIFF_COUNT (want 5)"
fi
PRICE=$(echo "$LIST_BODY" | jq -r '.pricing.price_usd // empty' 2>/dev/null)
if [ "$PRICE" != "9.99" ]; then
  fail "axonflow_list_pro_features: pricing.price_usd = '$PRICE' (want 9.99)"
fi
[ "$PASS" = "true" ] && echo "  axonflow_list_pro_features: success:true + 5 differentiators + 9.99 ✓"

# Test 2 — get_cost_estimate (Pro-only)
# Two-part assertion:
#   (a) HIDDEN from tools/list (the agent gates the Free advertisement).
#   (b) When invoked-by-name anyway (as Cursor's IDE LLM does when
#       prompted explicitly), the agent returns isError:true with the
#       locked V1 envelope (limit_type=feature_pro_only + buy_url).
echo
echo "================ tool 2: axonflow_get_cost_estimate ================"
HIDDEN=$(jq -r '[.result.tools[].name] | index("axonflow_get_cost_estimate") // empty' "$EVIDENCE/tools_list.json")
if [ -n "$HIDDEN" ] && [ "$HIDDEN" != "null" ]; then
  fail "axonflow_get_cost_estimate: visible to Free tenant in tools/list (V1 gating broken)"
else
  echo "  axonflow_get_cost_estimate: hidden from Free tools/list ✓"
fi
call_tool "axonflow_get_cost_estimate" '{"plan":"runtime-e2e probe"}'
COST_IS_ERR=$(jq -r '.result.isError // false' "$EVIDENCE/axonflow_get_cost_estimate.json")
COST_BODY=$(jq -r '.result.content[0].text // empty' "$EVIDENCE/axonflow_get_cost_estimate.json")
if [ "$COST_IS_ERR" != "true" ]; then
  fail "axonflow_get_cost_estimate (forced call): result.isError = '$COST_IS_ERR' (want true)"
fi
if ! echo "$COST_BODY" | grep -qF 'feature_pro_only'; then
  fail "axonflow_get_cost_estimate (forced call): body missing 'feature_pro_only' limit_type"
fi
if ! echo "$COST_BODY" | grep -qF 'buy.stripe.com/bJe28qbztcdVchjdkw8k800'; then
  fail "axonflow_get_cost_estimate (forced call): body missing locked V1 buy URL"
fi
[ "$COST_IS_ERR" = "true" ] && echo "  axonflow_get_cost_estimate (forced call): isError + feature_pro_only envelope ✓"

# Test 3 — request_approval (Free 1/7d, expect approval_id on first call)
echo
echo "================ tool 3: axonflow_request_approval ================"
call_tool "axonflow_request_approval" '{"original_query":"runtime-e2e probe","request_type":"shell_command","trigger_reason":"runtime_e2e_test","severity":"low"}'
RA_BODY=$(jq -r '.result.content[0].text // empty' "$EVIDENCE/axonflow_request_approval.json")
RA_IS_ERR=$(jq -r '.result.isError // false' "$EVIDENCE/axonflow_request_approval.json")
RA_ID=$(echo "$RA_BODY" | jq -r '.approval_id // empty' 2>/dev/null)
RA_SUCCESS=$(echo "$RA_BODY" | jq -r '.success // empty' 2>/dev/null)
RA_SUBMITTED=$(echo "$RA_BODY" | jq -r '.submitted // empty' 2>/dev/null)
if [ "$RA_IS_ERR" = "true" ]; then
  fail "axonflow_request_approval: isError = true on first Free call"
  echo "$RA_BODY" | head -10 | sed 's/^/    /'
elif [ -z "$RA_ID" ] || [ "$RA_ID" = "null" ]; then
  fail "axonflow_request_approval: missing approval_id on first Free call"
else
  if [ "$RA_SUCCESS" != "true" ]; then
    fail "axonflow_request_approval: missing 'success: true' (axonflow-enterprise#1989)"
  fi
  if [ "$RA_SUBMITTED" != "true" ]; then
    fail "axonflow_request_approval: missing 'submitted: true' (axonflow-enterprise#1989)"
  fi
  echo "  axonflow_request_approval: success:true + submitted:true + approval_id=$RA_ID ✓"
fi

# Test 4 — create_tenant_policy (Free 2-active, expect policy_id)
echo
echo "================ tool 4: axonflow_create_tenant_policy ================"
call_tool "axonflow_create_tenant_policy" "{\"name\":\"runtime-e2e-cursor-${UTC_TS}\",\"description\":\"runtime-e2e probe\",\"connector_type\":\"cursor.Bash\",\"pattern\":\"axonflow-runtime-e2e-marker\",\"action\":\"warn\"}"
CP_BODY=$(jq -r '.result.content[0].text // empty' "$EVIDENCE/axonflow_create_tenant_policy.json")
CP_IS_ERR=$(jq -r '.result.isError // false' "$EVIDENCE/axonflow_create_tenant_policy.json")
CP_ID=$(echo "$CP_BODY" | jq -r '.policy_id // empty' 2>/dev/null)
CP_SUCCESS=$(echo "$CP_BODY" | jq -r '.success // empty' 2>/dev/null)
CP_CREATED=$(echo "$CP_BODY" | jq -r '.created // empty' 2>/dev/null)
if [ "$CP_IS_ERR" = "true" ]; then
  fail "axonflow_create_tenant_policy: isError = true on first Free call"
  echo "$CP_BODY" | head -10 | sed 's/^/    /'
elif [ -z "$CP_ID" ] || [ "$CP_ID" = "null" ]; then
  fail "axonflow_create_tenant_policy: missing policy_id"
else
  if [ "$CP_SUCCESS" != "true" ]; then
    fail "axonflow_create_tenant_policy: missing 'success: true' (axonflow-enterprise#1989)"
  fi
  if [ "$CP_CREATED" != "true" ]; then
    fail "axonflow_create_tenant_policy: missing 'created: true' (axonflow-enterprise#1989)"
  fi
  echo "  axonflow_create_tenant_policy: success:true + created:true + policy_id=$CP_ID ✓"
fi

# Test 5 — get_tenant_id (Free callable, must include tenant_id + upgrade_url)
echo
echo "================ tool 5: axonflow_get_tenant_id ================"
call_tool "axonflow_get_tenant_id" "{}"
GT_BODY=$(jq -r '.result.content[0].text // empty' "$EVIDENCE/axonflow_get_tenant_id.json")
GT_TENANT=$(echo "$GT_BODY" | jq -r '.tenant_id // empty' 2>/dev/null)
GT_UPGRADE=$(echo "$GT_BODY" | jq -r '.upgrade_url // empty' 2>/dev/null)
GT_SUCCESS=$(echo "$GT_BODY" | jq -r '.success // empty' 2>/dev/null)
if [ "$GT_SUCCESS" != "true" ]; then
  fail "axonflow_get_tenant_id: missing 'success: true' (axonflow-enterprise#1989)"
fi
if [ "$GT_TENANT" != "$TENANT" ]; then
  fail "axonflow_get_tenant_id: tenant_id='$GT_TENANT' (want '$TENANT')"
fi
if ! echo "$GT_UPGRADE" | grep -qF 'getaxonflow.com/pricing'; then
  fail "axonflow_get_tenant_id: upgrade_url='$GT_UPGRADE' missing pricing path"
fi
[ "$GT_TENANT" = "$TENANT" ] && echo "  axonflow_get_tenant_id: $GT_TENANT + $GT_UPGRADE ✓"

{
  echo
  echo "Cursor V1 Plugin Pro MCP-tools-invocable runtime proof — $UTC_TS"
  echo "AGENT_URL=$AGENT_URL"
  echo "X-Axonflow-Client=$CLIENT_HEADER"
  echo "TENANT=$TENANT"
  echo "Result: $($PASS && echo PASS || echo FAIL)"
} | tee "$EVIDENCE/summary.txt"

if $PASS; then
  echo
  echo "PASS — Cursor's MCP wire path can invoke all 5 V1 Pro MCP tools end-to-end"
  exit 0
else
  echo
  echo "FAIL — see $EVIDENCE/ for evidence"
  exit 1
fi
