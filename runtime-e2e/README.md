# Runtime End-to-End Tests — Cursor plugin

Tests in this directory MUST invoke the plugin through Cursor's IDE plugin runtime — installed via the marketplace path, loaded by Cursor, and triggered through Cursor's tool/skill/command dispatch. Importing the plugin's TypeScript modules directly is not a runtime test — that's a unit test, which lives under `tests/`.

If Cursor can't expose your feature yet, the feature isn't ready to ship.

## Why this directory exists

A May 3, 2026 audit found multiple AxonFlow capabilities (audit search, decision explain, override CRUD) where the platform endpoint and SDK method existed for months but no plugin tool/skill ever wired them up. Users running Cursor with the AxonFlow plugin could not reach the capability. The fix: every user-facing AxonFlow feature exposed via this plugin must have a test in this directory that invokes through Cursor's runtime.

The single rule:

> **If a user cannot reach the feature from their runtime, we did not ship a feature, we shipped a library.**

See `axonflow-business-docs/engineering/E2E_EXAMPLES_TESTING_WORKFLOW.md` Policy section for the full methodology.

## What "runtime" means here

The runtime is Cursor's IDE plugin host. A test must:

- Install the plugin via Cursor's plugin/marketplace install path — not by symlinking from a relative source path.
- Load it inside a real (or scripted-headless) Cursor session.
- Trigger the capability through Cursor's surface — tool call from agent chat, skill invocation, or registered command — rather than importing the plugin's TypeScript classes.

If a test imports from `src/` and calls the AxonFlow client class, it is a unit test or an integration test against the AxonFlow stack. That belongs under `tests/`, not here.

## Layout

```
runtime-e2e/
  README.md                    # this file
  <feature-name>/              # one folder per feature
    test.sh                    # bash runner; invokes through cursor
    README.md                  # 5 lines: prereqs, what it asserts, how to run
```

## Running

Each test folder has its own README with prereqs and run instructions. Most tests assume:

- An AxonFlow community-saas-style stack is reachable (default endpoint or via env var).
- A working Cursor install with plugin support enabled.
- The plugin is built locally so the marketplace install path can resolve it.

## Adding a test

1. Confirm you can invoke the feature through Cursor — install the plugin, then trigger via tool/skill/command. If you can't, the answer is to fix the plugin's tool/skill registration, not to write a TypeScript-import test.
2. Create the folder, write `test.sh` and `README.md`.
3. Update `axonflow-business-docs/engineering/FEATURE_RUNTIME_COVERAGE.md` to mark the new green cell under the Cursor column.
4. Reference the test in the PR that wires the feature.
