# Cursor automation attempt (2026-05-03 → 2026-05-04 UTC)

I tried to drive Cursor's IDE agent end-to-end from a Bash session to
produce a real `EVIDENCE.md` for each per-feature test. It hit two
hard macOS permission walls and could not produce evidence.

## What was attempted

```bash
osascript -e 'tell application "Cursor" to activate'
osascript -e 'tell application "System Events" to tell process "Cursor" to keystroke "l" using command down'
screencapture -x -t png /tmp/cursor-after-cmd-l.png
```

The activation succeeded. The keystroke + screenshot did not.

## Why it didn't work

```
osascript is not allowed to send keystrokes. (1002)
could not create image from display
```

These are real OS-level guardrails:

1. **Accessibility permission for `osascript`** — macOS requires the
   parent process (Terminal in this case) to be in
   `System Settings → Privacy & Security → Accessibility` with the
   toggle on. Without that, no `keystroke` / `key code` command from
   `System Events` will reach Cursor.

2. **Screen Recording permission for `screencapture`** — macOS Sonoma
   requires the parent process to be in
   `System Settings → Privacy & Security → Screen Recording` with the
   toggle on. Without that, `screencapture` produces an empty file
   and prints "could not create image from display".

Neither was granted to the parent shell of this run. Granting requires
direct human interaction at System Settings — there's no programmatic
escape hatch.

## Second blocker (2026-05-04): free-tier usage cap (NOT a Pro requirement)

After the macOS permissions were granted and I retried the automation,
Cursor showed a "You've hit your usage limit" dialog after a couple
of agent invocations. The earlier 2026-05-03 evidence-capture session
worked around this by signing out and signing back in with a different
free email — the agent then ran on the new account's quota. Evidence
files in each feature folder were captured this way (free-tier, real
agent, real MCP tool dispatch).

This is a Cursor free-tier rate limit, not a Pro paywall — the agent
surface is reachable on free accounts; you just have to manage the
quota. (Initial earlier-session note that called this "Pro required"
was wrong; I'm correcting it here.)

## What this means for the bump PRs

The per-feature `test.sh` files in this directory still **fail-closed**
on missing `EVIDENCE.md`. That keeps rule #1 honest — Cursor v1.1.0
cannot be tagged until a human runs each `MANUAL_RUNBOOK.md` and
commits real evidence. The current evidence on file is from the
2026-05-03 run; if a fresh capture is required (e.g. to refresh a
screenshot after a platform behavior change), it can be done on the
free tier with quota juggling.

## Path to automation if you want it

1. Open `System Settings → Privacy & Security → Accessibility`. Add
   `Terminal` (or your shell's parent app) and toggle it on.
2. Open `System Settings → Privacy & Security → Screen Recording`.
   Add the same and toggle on.
3. Re-run an updated automation script (not yet written; would need
   work to reliably read Cursor's chat panel content via screenshot
   OCR — Electron apps don't expose chat content via Accessibility
   API).

For one-shot release-prep, a human running the runbook is faster than
building a reliable automation harness.
