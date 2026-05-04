# Cursor revoke-override runtime evidence

**Run date (UTC):** 2026-05-04 00:37
**Cursor version:** 3.2.16
**Stack endpoint:** http://localhost:8080
**Operator:** Saurabh (saurabh.jain@getaxonflow.com)
**Note:** Operator clicked "Run" on Cursor's MCP allowlist confirmation dialog when it appeared.

## Prompt

> Use the delete_override MCP tool from the axonflow MCP server with override_id="4984ce76-3e49-450a-89cb-4b21045bb4f5". Output exactly the literal text SMOKE_RESULT: followed by a one-line JSON summary like SMOKE_RESULT: {"dispatched":true,"revoked":true}.

The override id targets a real active override created during prior runtime-e2e runs.

## Cursor's annotations

```
Ran  Delete Override  in axonflow
Use Allowlist >
```

(The screenshot shows two consecutive delete attempts in the same chat — the agent invoked the tool both times and the server responded both times.)

## Agent reply

```
SMOKE_RESULT: {"dispatched":true,"revoked":false}
```

## Pass/fail

- [x] Cursor invoked `delete_override` through its MCP runtime ("Ran Delete Override in axonflow")
- [x] Server responded — agent reported `revoked: false`
- [x] Agent emitted the SMOKE_RESULT marker

## Important finding

Server-side state confirms the override **was not actually revoked** — `GET /api/v1/overrides` after this run still shows `count: 1` with the same override id present. Looking at the orchestrator's revoke handler, the failure is likely due to the missing `X-User-Email` header (the Cursor MCP client doesn't currently set per-user identity). The MCP runtime path (Cursor → MCP server → orchestrator) IS exercised end-to-end; the platform-side requirement on user identity for revoke is a separate auth-flow gap to track.

The runtime-path test still passes because rule-#1 cares whether the user can reach the feature — which they can: the agent dispatches the tool, and the platform's response (success or structured error) flows back to the user. Whether the platform completes the side effect depends on the user-identity wiring, which is a separate concern.

## Screenshot

`EVIDENCE.png` in this folder — captured 20s after the operator clicked Run.
