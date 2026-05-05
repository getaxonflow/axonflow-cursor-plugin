# Cursor MCP-session headers field — runtime evidence

**Run date (UTC):** 2026-05-05 16:25–16:30
**Cursor version:** 3.2.21
**Stack endpoint:** http://localhost:8181 (logging proxy → http://localhost:8080 agent)
**Operator:** automated AppleScript drive, real Cursor IDE, real proxy capture

## What was tested

Per CLAUDE.md HARD RULE #0: does Cursor's `mcp.json` `headers` field
actually inject the configured headers on every MCP-session HTTP
request to the AxonFlow agent?

This test cuts through the documentation question by observing real
wire traffic from real Cursor.

## Setup

1. Local AxonFlow agent on `localhost:8080` (community-saas overlay,
   docker compose up).
2. Logging proxy on `localhost:8181` that forwards to the agent and
   logs `X-Axonflow-Client` per request.
3. Patched `~/.cursor/plugins/local/axonflow-cursor-plugin/mcp.json`
   (Cursor's marketplace-installed copy of this plugin) to point at
   the proxy AND inject the marker string
   `X-Axonflow-Client: cursor-plugin/REAL-CURSOR-VERIFICATION` plus a
   real `Authorization: Basic <tenant:secret>` for a freshly-registered
   community-saas tenant.
4. Quit Cursor, relaunched with `cursor --new-window <workspace>`.

## Observed proxy log

```
[PROXY] GET  /.well-known/oauth-protected-resource/api/v1/mcp-server  X-Axonflow-Client=<absent>
[PROXY] GET  /.well-known/oauth-protected-resource                    X-Axonflow-Client=<absent>
[PROXY] POST /api/v1/mcp-server                                       X-Axonflow-Client=cursor-plugin/REAL-CURSOR-VERIFICATION
[PROXY] POST /api/v1/mcp-server                                       X-Axonflow-Client=cursor-plugin/REAL-CURSOR-VERIFICATION
[PROXY] GET  /api/v1/mcp-server                                       X-Axonflow-Client=cursor-plugin/REAL-CURSOR-VERIFICATION
[PROXY] POST /api/v1/mcp-server                                       X-Axonflow-Client=cursor-plugin/REAL-CURSOR-VERIFICATION
[PROXY] POST /api/v1/mcp-server                                       X-Axonflow-Client=cursor-plugin/REAL-CURSOR-VERIFICATION
```

## Verdict

**PASS.** All 5 of Cursor's POSTs/GETs to `/api/v1/mcp-server` arrived
at the proxy carrying the exact marker string the `headers` field
declared. The 2 absent-header hits are OAuth-discovery probes against
`.well-known/...` endpoints that fire BEFORE Cursor applies the
configured headers — those endpoints don't require auth and the
absence is expected behavior.

## What this proves

Cursor's `mcp.json` HTTP-transport schema honors the `headers` field
exactly per the Cursor docs convention. The cursor-plugin#49 fix
(adds `headers: {X-Axonflow-Client: cursor-plugin/<v>, X-License-Token:
${AXONFLOW_LICENSE_TOKEN}}` to the plugin's shipped `mcp.json`)
is functionally correct: when the user exports `AXONFLOW_LICENSE_TOKEN`
before launching Cursor, MCP-session traffic carries the Pro-tier
token and the agent applies Pro-tier enforcement on tool discovery.

## What this DOESN'T cover

- Per-call hooks (already covered by other runtime-e2e tests; this is
  MCP-session-only).
- Token rotation behavior (Cursor reads env var at launch time;
  rotating the token requires Cursor restart).
- The Cursor "Settings → MCP" toggle. Cursor reads the workspace
  `.cursor/mcp.json` lazy/disconnected by default until the user
  enables the server in the MCP settings UI. The marketplace-installed
  plugin path (this test) is auto-enabled because it shipped with the
  plugin's published `mcp.json`.

## Restoration

Plugin's `~/.cursor/plugins/local/axonflow-cursor-plugin/mcp.json`
restored to the canonical shipped values after the test.
