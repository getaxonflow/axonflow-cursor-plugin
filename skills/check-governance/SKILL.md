---
name: check-governance
description: Check if an action is allowed by AxonFlow governance policy before executing it
---

Use this skill when you want to verify whether a specific command, query, or file operation is allowed by the governance policies before running it.

Call the `check_policy` MCP tool with:
- `connector_type`: `cursor.Bash` (for commands), `cursor.Write` (for file writes), or the appropriate tool type
- `statement`: the command or content to check

If the response shows `allowed: false`, do NOT proceed with the action. Report the block reason to the user.
