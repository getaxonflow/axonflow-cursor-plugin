# explain-decision — runtime E2E

**Asserts (gate):** Cursor IDE present, AxonFlow stack reachable, MCP server advertises `explain_decision`, plugin's `mcp.json` well-formed, AND `EVIDENCE.md` from a recent (≤60 day) human-driven `MANUAL_RUNBOOK.md` run is checked in. Cursor's CLI is window-management only, so the runtime-path proof is human-driven; this gate refuses to pass without recent evidence.

**Prereqs:** Cursor IDE installed; `jq`; live AxonFlow stack reachable at `$AXONFLOW_ENDPOINT` (default `http://localhost:8080`).

**Run:**
```bash
AXONFLOW_ENDPOINT=http://localhost:8080 \
  bash runtime-e2e/explain-decision/test.sh
```

To produce `EVIDENCE.md`: follow `MANUAL_RUNBOOK.md` in this folder.
