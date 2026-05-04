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

## Second blocker (2026-05-04): Cursor Pro required

After the macOS permissions were granted and I retried the automation:
Cursor activated, the Agent panel opened, the prompt was sent — and
Cursor returned a "Cursor Pro upgrade needed" prompt instead of
invoking the agent. **The Cursor Agent surface (the user-facing path
this runtime test is supposed to verify) requires a paid Pro
subscription.** Without Pro, no agent invocation happens regardless of
how well my automation drives the IDE.

This is a Cursor product policy, not a wiring problem on our side.
Implication for the W2 release: Cursor v1.1.0 runtime evidence
requires a Pro account. The `EVIDENCE.md` files in each feature folder
need to be produced by a human who is logged in to Cursor with Pro.
The gates in this directory remain fail-closed without that evidence.

## What this means for the bump PRs

The per-feature `test.sh` files in this directory still **fail-closed**
on missing `EVIDENCE.md`. That keeps rule #1 honest — Cursor v1.1.0
cannot be tagged until a human with a Cursor Pro account runs each
`MANUAL_RUNBOOK.md` and commits real evidence. This file documents the
attempt so future runs don't repeat the same dead-end before grabbing
the human + Pro account.

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
