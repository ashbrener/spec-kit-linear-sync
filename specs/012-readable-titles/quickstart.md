# Quickstart: Human-Readable Issue Titles

**Feature**: `012-readable-titles` | **Date**: 2026-06-17

What changes for you: spec Issues in Linear get **readable titles** instead of
directory slugs. **No configuration, no action required** — it just happens on
the next reconcile.

## Before → after

| Before (slug) | After (readable) |
|---|---|
| `006-faithful-projection` | `006 — Faithful projection` |
| `010-author-attribution` | `010 — Author-Based Attribution` |
| `001-fixtures` | `001 — Establish the validated, internally-consistent seed-data contract…` |

The leading number ties the Issue to its `specs/NNN-…` directory and its
`speckit-spec:NNN` label. (Linear's own `AML-5`-style identifier still shows
separately.)

## Where the title comes from

Per spec, the bridge picks the first that resolves:

1. **Your spec's H1** — `# Feature Specification: <NAME>` (every spec written by
   `/speckit-specify` has one, e.g. `# Feature Specification: Faithful projection`).
2. **The first sentence of your `## Input`** — used when the H1 is still the
   unfilled `[FEATURE NAME]` placeholder (truncated to one clean line).
3. **The directory slug** — last resort, if there's no H1 and no Input.

It's derived entirely from your `spec.md` — no AI summarization at sync time — so
the title is identical whether the sync runs from a hook, a manual push, or CI,
and re-running never churns it.

## Want a nicer title?

Just edit your spec's H1: change `# Feature Specification: <NAME>` to the name you
want. The next reconcile mirrors it. (Keep it short — it's a one-line title; the
full Input/Overview already lives in the Issue description.)

## On upgrade (one-time)

The first reconcile after you update the bridge re-titles your existing spec
Issues once (slug → readable). After that, titles are stable — an unchanged spec
produces no title write.

## What doesn't change

- **Sub-issue titles** (`Phase N — <Name>`) — already readable, untouched.
- **The Issue description** — the inlined Input/Overview body is unchanged.
- **Manual renames in Linear** — the title is bridge-owned (as it always has
  been), so a manual rename is replaced by the computed title on the next
  reconcile.

## Verify

1. Reconcile (any `after_*` hook or `speckit.linear.push`).
2. Check a spec Issue: the title reads `<NNN> — <name>`.
3. Reconcile again with the spec unchanged → the title doesn't move (zero churn).
