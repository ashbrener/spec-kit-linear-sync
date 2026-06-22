<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

<!-- Everything below is OUTSIDE the SPECKIT-managed block on purpose, so
     `specify integration upgrade` cannot overwrite it. Keep project rules here. -->

The current plan is `specs/013-subissue-cascade/plan.md` (lifecycle cascade to
task-phase sub-issues — fix the board lying about merged work: when a spec's
inferred lifecycle is terminal (`ready_to_merge`/`merged`), force every
task-phase sub-issue to Done, overriding the tasks.md checkbox ratio (thread
`lifecycle_phase` into `sync_task_phase_subissues`); and broaden the phase-header
grammar to accept a single-letter index (`## Phase A —`, separator-gated so
`## Phase one`/`1Setup` still near-miss), exposing an ordinal (A→1…Z→26, for the
`task-phase:<ordinal>` label + blocking order + match key) and a display token
(raw, for the faithful `Phase A — …` sub-issue title). Additive; amends spec-001
FR-005/FR-013; sub-issue description/mirror unchanged; parity follow-up for the
jira sibling). It builds on `specs/012-readable-titles/plan.md` (readable Issue
titles), `specs/010-author-attribution/plan.md` (author attribution),
`specs/008-adr-mirroring/plan.md` (ADR / decision-record mirroring) and
`specs/007-configurable-mapping/plan.md` (configurable mapping, resolves #17).
It builds on the shipped baselines: `specs/006-faithful-projection/plan.md`,
`specs/005-team-scoped-seeding/plan.md`, `specs/004-config-identity-split/plan.md`,
the drift-aware write-authority redesign at `specs/003-drift-aware-authority/plan.md`,
the v0.1.1 install-ergonomics plan at `specs/002-install-ergonomics/plan.md`, and
the v0.1.0 baseline at `specs/001-spec-kit-linear-bridge/plan.md`.

Always check `.specify/memory/constitution.md` (v2.1.0, 8 principles) before
proposing implementation changes — the Constitution Check gate is
non-negotiable. (v2.1.0 amended the data-model-mapping clause: the spec-001
mapping is the frozen zero-config default; alternative mappings are
operator-configurable per spec 007, bounded by the fail-closed relationship
matrix.) Use canonical spec-kit vocabulary throughout (`task phase`,
`Phase N — <Name>`, never `wave / W0`).
