# Tasks: Faithful projection (#34 + #42)

**Feature**: `006-faithful-projection` · **Plan**: [plan.md](./plan.md)

## Phase 1: Broaden phase-header parsing (#34)

- [x] T001 Broaden the separator in `parser::task_phases` (`src/parser.sh`) to
  accept `:` / `—` / `-` / whitespace after `## Phase <N>`; extract number + trimmed name.
- [x] T002 Apply the same broadened pattern in `parser::tasks_in_phase` so
  per-phase task extraction matches the enumeration.
- [x] T003 Apply it in `parser::malformed_task_lines` so orphan/near-miss
  accounting agrees; keep the #45 near-miss warning firing only for genuinely
  unparseable `## Phase` lines (e.g. worded numbers).
- [x] T004 Unit tests (`tests/unit/parser.bats`): em-dash / hyphen / bare headers
  parse to the correct phase count + names; a worded-number `## Phase one` stays a
  near-miss.
- [x] T005 Fixtures: `tests/fixtures/specs/006-emdash-phases/`,
  `tests/fixtures/specs/007-worded-phase/`; integration coverage in
  `tests/integration/us1-phase-header-nearmiss.bats`.

## Phase 2: Inline spec content into the issue description (#42)

- [x] T006 Add `RECONCILE_SPEC_CONTENT_MAX_CHARS` (6000) cap in `src/reconcile.sh`.
- [x] T007 Assemble inlined content (`**Input**` → `## Overview` → body sections,
  document order) into the description; keep the full-spec link.
- [x] T008 Clean-boundary truncation at the cap with a single `…` indicator;
  deterministic (bytes-only) so re-runs don't churn (idempotent).
- [x] T009 Preserve the memory-block fence + read-only-mirror semantics.
- [x] T010 Tests (`tests/unit/reconcile.bats`/integration): description contains
  Input+Overview; oversized spec truncates with link; idempotent re-run.

## Phase 3: Gates

- [x] T011 `shellcheck --severity=style` clean on `src/parser.sh`, `src/reconcile.sh`.
- [x] T012 `bats tests/unit/` green; relevant integration green.
