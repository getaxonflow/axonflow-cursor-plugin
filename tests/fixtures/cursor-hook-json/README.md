# Cursor hook input fixtures

**UNVERIFIED AGAINST THE WIRE.**

These files are the hook input the unit suite (`tests/test-hooks.sh`) feeds to
`scripts/pre-tool-check.sh` and `scripts/post-tool-audit.sh`. They were built
from Cursor's documentation only: https://cursor.com/docs/hooks, read
2026-09-16. No Cursor IDE session was captured, because launching the IDE was
not permitted for this work. Every value is a placeholder (paths under
`/home/user/project`, `user_email` null, zeroed ids); only the field names and
the value types come from the documentation.

When a real Cursor session is captured, replace these files with the captured
JSON and remove the marker above.

## Where each field came from

| Field(s) | Documented section |
|---|---|
| `conversation_id`, `generation_id`, `model`, `model_id`, `model_params`, `hook_event_name`, `cursor_version`, `workspace_roots`, `user_email`, `transcript_path` (every file) | "Common schema", Input (all hooks) |
| `tool_name`, `tool_input`, `tool_use_id`, `cwd`, `agent_message` (`pre-shell.json`, `pre-write.json`, `pre-edit.json`) | "Hook events", preToolUse, input example |
| `tool_input.command`, `tool_input.working_directory` (`pre-shell.json`) | preToolUse input example (tool_name `Shell`) |
| `tool_name`, `tool_input`, `tool_output` (a JSON-STRINGIFIED result such as `"{\"exitCode\":0,\"stdout\":\"...\"}"`), `tool_use_id`, `cwd`, `duration` in milliseconds (`post-shell.json`, `post-write.json`) | "Hook events", postToolUse, input example |
| `command`, `cwd`, `sandbox` (`before-shell-execution.json`) | "Hook events", beforeShellExecution / beforeMCPExecution, input |
| `command`, `output`, `duration`, `sandbox` (`after-shell-execution.json`) | "Hook events", afterShellExecution, input |
| `file_path`, `edits[] {old_string, new_string}` (`after-file-edit.json`) | "Hook events", afterFileEdit, input |

## What the documentation does NOT give

- **The `tool_input` of `Write` and `Edit`.** The documentation shows a
  `tool_input` only for `Shell`. `pre-write.json` / `post-write.json` use
  `{file_path, content}` and `pre-edit.json` uses
  `{file_path, old_string, new_string}`: the fields the hooks read, not a
  documented shape. `Edit` is also not in the documented tool-name list
  (Shell, Read, Write, Grep, Delete, Task, `MCP:<tool_name>`); it is in
  `hooks/hooks.json`'s matcher.
- **The `tool_output` of `Write`.** Only the `Shell` result is documented;
  `post-write.json` carries `"{}"`, a placeholder with no exit status.
- **The `hook_event_name` values' spelling on the wire.** The files use the
  event names as the documentation headings spell them (`preToolUse`,
  `postToolUse`, `beforeShellExecution`, `afterShellExecution`,
  `afterFileEdit`); the hooks do not read this field.

## The legacy shape

The object-shaped `tool_response` (`{"stdout": "...", "exitCode": 0}`) that the
repository's older tests send is the LEGACY shape: it is not what the
documentation describes for postToolUse (a stringified `tool_output`). The
post hook still reads it, and the suite keeps legs for it, but it is not a
fixture here.
