# Cursor list-recent-decisions runtime evidence — wire-level baseline

**Run date (UTC):** 2026-05-07 14:39
**Stack endpoint:** http://localhost:8080
**Operator:** wire-level baseline (automated curl drive against the platform's MCP server)
**Cursor IDE proof:** pending — operator drives the MANUAL_RUNBOOK during release validation; this file is the wire-level reference the operator's IDE-driven run is compared against.

## tools/list — list_recent_decisions advertised

```json
{
  "name": "list_recent_decisions",
  "description": "List recent governance decisions made by AxonFlow for the current user/tenant. Useful for surfacing 'what just got blocked' UX, appealing a block, or tracing a workflow's decision history. Tier-throttled per the platform's Free/Pro window+limit.",
  "inputSchema": {
    "properties": {
      "decision": {
        "description": "Filter to decisions of this kind.",
        "enum": [
          "allow",
          "deny",
          "require_approval"
        ],
        "type": "string"
      },
      "limit": {
        "description": "Max rows to return. Caller-supplied limits exceeding the tier's max page emit the V1 upgrade envelope at 429 instead of capping silently.",
        "maximum": 1000,
        "minimum": 1,
        "type": "integer"
      },
      "policy_id": {
        "description": "Filter to decisions matching this policy_id.",
        "type": "string"
      },
      "since": {
        "description": "Optional RFC3339 lower bound (e.g. 2026-05-01T00:00:00Z). Silently clamped to the tier's lookback window when reaching further back.",
        "format": "date-time",
        "type": "string"
      },
      "tool_signature": {
        "description": "Filter to decisions scoped to this tool signature.",
        "type": "string"
      }
    },
    "type": "object"
  }
}
```

## tools/call list_recent_decisions {"limit": 3} — happy path

```json
{
    "jsonrpc": "2.0",
    "id": 3,
    "result": {
        "content": [
            {
                "type": "text",
                "text": "{\n  \"decisions\": [\n    {\n      \"decision\": \"require_approval\",\n      \"decision_id\": \"dec-com-2\",\n      \"policy_id\": \"pol-pii\",\n      \"timestamp\": \"2026-05-07T13:21:37.708715Z\",\n      \"tool_signature\": \"slack.send_message\"\n    },\n    {\n      \"decision\": \"deny\",\n      \"decision_id\": \"dec-com-1\",\n      \"policy_id\": \"pol-sqli\",\n      \"timestamp\": \"2026-05-07T12:21:37.708715Z\",\n      \"tool_signature\": \"postgres.query\"\n    }\n  ]\n}"
            }
        ]
    }
}
```

## tools/call list_recent_decisions {"limit": 10} — over-cap V1 envelope

```json
{
    "jsonrpc": "2.0",
    "id": 4,
    "result": {
        "content": [
            {
                "type": "text",
                "text": "{\n  \"envelope\": {\n    \"error\": \"Free tier shows the last 5 decisions in 24h. Pro raises this to 100 decisions in the last 30 days.\",\n    \"limit\": 5,\n    \"limit_type\": \"decision_list_size\",\n    \"remaining\": 0,\n    \"tier\": \"Community\",\n    \"upgrade\": {\n      \"buy_url\": \"https://buy.stripe.com/bJe28qbztcdVchjdkw8k800\",\n      \"compare_url\": \"https://getaxonflow.com/pricing/\",\n      \"tier\": \"Pro\",\n      \"wording\": \"Free tier shows the last 5 decisions in 24h. Pro raises this to 100 decisions in the last 30 days.\"\n    }\n  },\n  \"upgrade_required\": true\n}"
            }
        ]
    }
}
```

## Pass/fail — wire baseline

- [x] MCP server advertises `list_recent_decisions` with the locked V1.1 input schema
- [x] Happy-path tool result is a `decisions` array (possibly empty on a fresh stack)
- [x] Over-cap tool result carries `upgrade_required: true` + `envelope.limit_type=decision_list_size` + `envelope.upgrade.buy_url` + `envelope.upgrade.compare_url` — locks in feedback_429_no_upgrade_hint_is_conversion_gap.md at the wire level

## IDE-driven proof (deferred to release validation)

Cursor's CLI is window-management only. A maintainer drives the MANUAL_RUNBOOK in the IDE before release tagging and replaces this file with the IDE-driven evidence (Cursor's tool annotations + the agent's SMOKE_RESULT marker). The wire-level shape above is what the IDE-driven run should match.
