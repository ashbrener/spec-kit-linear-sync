# Implementation Plan: Faithful projection (#34 + #42)

**Feature**: `006-faithful-projection` · **Spec**: [spec.md](./spec.md) · **Created**: 2026-06-07

## Summary

Two changes that make the spec→Linear projection more faithful, sharing no code
but shipped together as one "the issue reflects the spec" theme:

- **Part A — broaden phase-header parsing (#34).** The `tasks.md` phase parser
  was colon-only (`^## Phase N:`), silently producing zero sub-issues for
  em-dash / hyphen / bare headers. Broaden it to accept `:`, `—`, `-`, or
  whitespace as the number→name separator, extracting the same phase number +
  trimmed name. Keep the near-miss warning (from #45) for *genuinely*
  unparseable `## Phase` lines (e.g. a worded number).
- **Part B — inline spec content (#42).** The Linear issue description carried
  only an Overview excerpt + a "read full spec" link. Inline the spec's own
  authored content (its `**Input**` line, `## Overview`, and further body
  sections in document order) up to a total cap, so the issue is
  self-contained, while still linking to the full spec.

## Design

### Part A — parser (`src/parser.sh`)

- The separator after `## Phase <N>` becomes any of `:` / `—` / `-` /
  whitespace, applied **consistently** across `parser::task_phases`,
  `parser::tasks_in_phase`, and `parser::malformed_task_lines` so phase
  enumeration, per-phase task extraction, and the orphan/near-miss accounting
  all agree on what counts as a phase header.
- The phase **number** is the load-bearing token; the **name** is the trimmed
  remainder after the separator. A `## Phase` line whose number is not a digit
  run (e.g. `Phase one`) remains a near-miss and still triggers the #45 warning.

### Part B — description (`src/reconcile.sh`)

- Assemble inlined content in document order: `**Input**` → `## Overview` →
  remaining body sections, into the issue description (the read-only mirror),
  bounded by `RECONCILE_SPEC_CONTENT_MAX_CHARS` (6000).
- **Truncation (FR-010/FR-013):** when the assembled content exceeds the cap it
  is cut at a **clean line boundary** (never mid-line), a single `…` indicator
  line is appended, and the always-present full-spec link follows. Truncation is
  a pure function of the on-disk bytes (no timestamps), so re-reconciling an
  unchanged oversized spec never flips between truncated/untruncated (idempotent,
  SC-005).
- The memory-block fence and read-only-mirror semantics are preserved; this
  block does not touch operator annotations.

## Constitution Check (v2.0.0, 8 principles)

- **I Filesystem-is-truth** — inlined content is a read-only mirror of `spec.md`;
  no write-back. PASS
- **II Reconcile/idempotent** — deterministic truncation; re-run does not churn
  the description. PASS
- **III Spec-driven** — broader headers + inlined content come straight from the
  spec artifacts. PASS
- **IV Drift-aware authority** — unchanged. PASS
- **V Self-describing** — unchanged. PASS
- **VI OAuth-first** — unchanged. PASS
- **VII Reversible/least-surprise** — broadening only *adds* accepted header
  forms; existing colon headers behave identically. PASS
- **VIII No silent failure** — the #45 near-miss warning is preserved for true
  misses; broadening turns prior silent skips into parsed sub-issues. PASS

Result: **8 conform / 0 drift.**

## Files

- `src/parser.sh` — broaden the three phase regexes.
- `src/reconcile.sh` — inline spec content + capped clean-boundary truncation.
- Tests: `tests/unit/parser.bats`, `tests/integration/us1-phase-header-nearmiss.bats`,
  fixtures `tests/fixtures/specs/006-emdash-phases/`, `tests/fixtures/specs/007-worded-phase/`.
