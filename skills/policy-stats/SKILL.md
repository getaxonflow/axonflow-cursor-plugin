---
name: policy-stats
description: Get AxonFlow governance activity summary — total checks, blocks, allows, and top triggered policies
---

Use this skill to get an overview of governance activity and compliance posture.

Call the `get_policy_stats` MCP tool. Optionally provide:
- `from`: start date (ISO 8601)
- `to`: end date (ISO 8601)
- `connector_type`: filter by tool type (e.g., `cursor.Bash`)

Present the results showing total events, compliance score, and any policies that were triggered.
