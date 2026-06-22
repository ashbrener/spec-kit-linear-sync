# Quickstart: Lifecycle Cascade to Task-Phase Sub-Issues

**Feature**: `013-subissue-cascade` | **Date**: 2026-06-22

What changes: a **merged spec's task-phase sub-issues now read Done**, and specs
that index phases with **letters** (`## Phase A — …`) now get sub-issues. No
configuration, no action — it heals on the next sync.

## The problem this fixes

On a board where every spec is merged, the parent Issues correctly read **Merged**
but their per-phase sub-issues were scattered across **Todo/Done** — because a
sub-issue's state came *only* from how many `tasks.md` checkboxes you'd hand-ticked.
And specs that wrote `## Phase A —` (letters) got **no sub-issues at all**.

## What you'll see after the next reconcile

- **Merged / ready-to-merge specs:** every task-phase sub-issue reads **Done** —
  no need to hand-tick `tasks.md`. The board finally matches reality.
- **Letter-indexed phases:** `## Phase A — Overlay` now creates a sub-issue titled
  `Phase A — Overlay` (faithful to your heading), labelled `task-phase:1`,
  `## Phase B —` → `task-phase:2`, and so on.
- **Specs still in progress:** unchanged — sub-issue state is still the checkbox
  ratio (todo / in-progress / done).

## How to apply it

Nothing special — just run a sync in the repo:

```bash
speckit.linear.push          # the explicit reconcile (heals every spec)
# or just run your next /speckit-* command — the after_* hook does it
```

It's a **one-time heal**: each stranded sub-issue flips to Done once, then re-runs
are zero-churn.

## Notes

- **State vs. checklist body.** A Done sub-issue of a merged spec may still show
  literally un-ticked `- [ ]` boxes in its description — that's intentional. The
  **state** reflects the spec's lifecycle (merged = shipped); the **body** stays a
  faithful, read-only mirror of your `tasks.md`. The bridge never edits your task
  content.
- **Letter ordinals.** A letter phase's label/order uses its alphabet position
  (A→1, B→2…) so identity and blocking stay stable; the **title** keeps your
  letter (`Phase A — …`). Numeric specs are completely unchanged.
- **Genuinely malformed headers** (`## Phase one`, `## Phase 1Setup`) still raise
  the "phase-like heading not parsed" warning — the broadening only adds single
  letters, it doesn't swallow typos.
- **Heads-up if you merged via `--force` reinstall:** that can strip the `after_*`
  hooks (see the hook-restore note); re-run `speckit.linear.install` if your
  auto-sync stopped firing, then push.
