# MCP-session header injection (cursor#47)

Verifies that Cursor's MCP-session traffic to the AxonFlow agent carries
`X-Axonflow-Client: cursor-plugin/<version>` and (when set)
`X-License-Token: ${AXONFLOW_LICENSE_TOKEN}`.

## What this asserts

Cursor reads the project's `.cursor/mcp.json` and, on first activation
of the MCP server, sends an HTTP request to the URL with the configured
`headers`. The plugin's shipped `mcp.json` declares both header names so
Cursor injects them on every MCP-session request.

Without this, Pro-tier customers using Cursor's MCP path get Free-tier
enforcement (the per-call hooks still cover actual policy enforcement,
but the agent's tool-discovery response uses the Free-tier tool list,
so Pro-only tools never appear in the MCP-session tool inventory).

## Prereqs

- Local AxonFlow agent running on `localhost:8080` (e.g. `docker compose
  -f docker-compose.yml -f docker-compose.community-saas.yml up -d` from
  `axonflow-enterprise/`).
- Logging proxy running on `localhost:8181` that forwards to the agent
  and logs `X-Axonflow-Client` per request to `/tmp/axonflow-e2e/proxy.log`.
- `cursor` CLI on PATH or `/Applications/Cursor.app` installed.

## How to run

```bash
export AXONFLOW_ENDPOINT=http://localhost:8181
# Optional: set Pro-tier token
# export AXONFLOW_LICENSE_TOKEN=AXON-...
./test.sh
```

## Expected output

```
PASS: <N> proxy hit(s) carrying X-Axonflow-Client=cursor-plugin/* — Cursor honored the headers field
```

## Why this can't run mocked

Per CLAUDE.md HARD RULE #0: a runtime test for a Cursor MCP-session
behavior MUST exercise the actual Cursor binary's MCP-config parser
+ HTTP client. Mocking Cursor's behavior with our own JSON-loader
proves nothing — the whole point of the test is "does Cursor actually
honor `headers` in `mcp.json`?".

## The capability handshake legs (cursor#95) — evidence-gated, OWED

`test.sh` also carries two legs for the ADR-065 capability handshake, run only with `AXONFLOW_E2E_CURSOR_HANDSHAKE=1`:

1. With `AXONFLOW_PEP_AUDIENCE` unset, Cursor, reading the shipped `mcp.json`, must send **no** `X-Axonflow-PEP-Handshake` header. An empty one is malformed, and the platform refuses the request (HTTP 400, `pep_handshake_malformed`).
2. After `scripts/configure-mcp-handshake.sh` has written the header for an audience, every MCP request Cursor sends must carry exactly that value.

They need a supervised Cursor launch and a logging proxy that records `X-Axonflow-PEP-Handshake=<value>` for each request where the header is present. **No run exists yet:** a Cursor IDE launch was not permitted for the change that added them, so this evidence is owed. What is proven without the IDE is wire-level stage 3 of `runtime-e2e/pep_capability_handshake/test.sh`. It expands `mcp.json` the way Cursor documents, against a live agent: no audience, allowed with a redaction; audience configured, refused with `unsupported_obligation`; an empty header, HTTP 400.
