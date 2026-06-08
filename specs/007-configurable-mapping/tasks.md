---
description: "Task list for 007-configurable-mapping"
---

# Tasks: Configurable Artifact Mapping

**Input**: Design documents from `/specs/007-configurable-mapping/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — the constitution makes loud, observable failure the gate
(Principle VIII) and each contract (`mapping-config.md`,
`config-reconcile-interface.md`) defines bats obligations. Test tasks precede the
implementation they cover within each phase (the 001 pattern).

**Organization**: by user story (US1–US4 from spec.md) so each is an
independently testable increment. This feature is an **additive extension** of
the shipped 001 core bridge — all mapping / alias / validation lives in the
source-agnostic config layer (`src/config.sh`); `src/reconcile.sh` consumes a
*resolved* mapping and gains no Linear-specific mapping knowledge (FR-014).

**Scope note (narrower than the Jira port)**: the spec-kit-jira `--workstate`
direct-input seam, the status-rollup lever, and the available-issue-type probe
are **deferred / not needed** for Linear (spec Assumptions → Out of scope):
Linear's required-level artifacts are fixed primitives (Project / Issue /
sub-issue / checklist) needing no availability probe, and the only optional
artifact (the L0 Milestone) degrades gracefully. There is no separate "2-level
checklist mode" task family — `task→checklist` is already the Linear default.

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: parallelizable (different file, no dependency on an incomplete task)
- **[USx]**: the user story a task serves (story phases only)

---

## Phase 1: Setup

- [ ] T001 [P] Add the feature's fixture trees for the new modes under `tests/fixtures/linear_responses/`: `milestone_meta/` (Milestone-capability present + absent responses) and `mapping_configs/` (default / #17 spec→Project / partial / L0-on `linear-config.yml` variants), placeholders only — no real coordinates (FR-018)
- [ ] T002 [P] Add a committed placeholder `mapping:` block to the config template/docs example (per-level `artifact` + `relationship_to_parent`, optional L0 super-level, all defaults) mirroring `contracts/mapping-config.md` — no real coordinates

---

## Phase 2: Foundational (blocking prerequisites for ALL stories)

**Purpose**: the `mapping:` block parse, the alias-layer default synthesis,
per-level inheritance, the resolved-mapping accessor surface, and the config-load
validation gate — these underpin every story. All in `src/config.sh`; unit tests
first. Every validation rule is fail-closed at config-load (exit 2), before any
write.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 [P] Unit test `tests/unit/mapping_parse.bats` — parse the optional `mapping:` block from `linear-config.yml` (per-level `artifact`/`relationship_to_parent`, optional `super_level` with `on_absent`/`source`) per `contracts/mapping-config.md`; malformed enum values (`artifact` ∉ {Project,Issue,sub-issue,checklist}, `on_absent`≠`degrade`, `source`≠`spec_input`) are config errors (exit 2)
- [X] T004 [P] Unit test `tests/unit/mapping_alias.bats` — absent `mapping:` synthesizes the default block (repo→Project, spec→Issue, phase→sub-issue, task→checklist, L0 off) from existing binding keys; a pre-feature config loads byte-for-byte unchanged (no rewrite, no version bump); an explicit default block equals the synthesized one (alias equivalence, FR-002, US1 scenario 3)
- [X] T005 [P] Unit test `tests/unit/mapping_inherit.bats` — a partial `mapping:` block (only some levels specified) inherits the synthesized default per unspecified level; not an all-or-nothing error (FR-005, US3)
- [X] T006 [P] Unit test `tests/unit/mapping_validate.bats` — the relationship-validation matrix accepts `parent`/`none`/`checklist` and rejects `blocks`/`relates` as hierarchy links, `parent` on the top (repo/L0) level, and a `checklist` artifact paired with a non-`checklist` relationship; required-id presence for any Issue/Project-projected level; every reject is a single fail-closed gate (exit 2, nothing written) per `contracts/mapping-config.md` §validation order (FR-006, FR-007, FR-013)
- [X] T007 Implement `config::mapping_parse` in `src/config.sh` — parse the `mapping:` block into the loaded config; validate the enum fields fail-closed (exit 2) (FR-003)
- [X] T008 Implement `config::mapping_synthesize_default` + alias layer in `src/config.sh` — emit the default block when `mapping:` is absent, derived from the existing binding keys; apply per-level inheritance for unspecified levels; add the task-identity label default for Issue/Project-projected levels (FR-002, FR-005, FR-009)
- [X] T009 Implement the resolved-mapping accessors in `src/config.sh` per `contracts/config-reconcile-interface.md` — `config::resolved_artifact <level>`, `config::resolved_relationship <level>`, `config::resolved_identity_key <level>`, `config::is_top_level <level>`, and `config::super_level_state` — returning the resolved (or aliased) values for a given level
- [X] T010 Implement the config-load validation gate `config::mapping_validate` in `src/config.sh` — single fail-closed gate ordering required-id presence then the offline relationship matrix; collects to a workspace-level config error (exit 2) before any write (FR-007, FR-013, FR-017)

**Checkpoint**: the `mapping:` block parses, aliases to today's default, inherits
per level, exposes a resolved-mapping accessor surface, and validates
fail-closed — the foundation every story builds on.

---

## Phase 3: User Story 1 — A no-config upgrade changes nothing (P1) 🎯 MVP

**Goal**: An absent or explicit-default `mapping:` reproduces 001 behaviour
byte-for-byte — the regression anchor for the whole feature, and what lets #17 be
resolved as a configurable choice without disturbing the installed default.

**Independent test**: Reconcile a pre-feature config (no `mapping:` block) over
the mock and confirm the created/updated/skipped result is byte-identical to the
prior version's, including a zero-churn re-run.

- [ ] T011 [P] [US1] Integration test `tests/integration/mapping-us1-default-equivalence.bats` — a config with no `mapping:` block mirrors repo→Project / spec→Issue / phase→sub-issue / task→in-body checklist exactly as the shipped default; assert created counts + issue shapes + labels + workflow-state behaviour match the baseline (spec scenario 1)
- [ ] T012 [P] [US1] Integration test `tests/integration/mapping-us1-default-zerochurn.bats` — re-run the already-mirrored default corpus; assert zero writes (0 created / 0 updated, Project + Issues reused, no rewritten fields), and that an explicit default `mapping:` block produces the identical result to the no-block case (spec scenarios 2–3, SC-001)
- [X] T013 [US1] Route the existing `src/reconcile.sh` projection (the 001 repo-Project / spec-Issue / phase-sub-issue / task-checklist path) through the `config::resolved_*` accessors for the default-aliased mapping, with no behaviour change (FR-001, FR-014)
- [X] T014 [US1] Confirm `src/reconcile.sh` loads + aliases + validates the `mapping:` block before the write loop; default path unchanged from the shipped baseline (regression anchor)

**Checkpoint**: US1 delivers the safety promise — upgrade safely, opt in later.

---

## Phase 4: User Story 2 — Configure the mapping to resolve #17, safely (P1)

**Goal**: Mapping-driven per-level projection (artifact + relationship), with the
offline relationship-validation matrix and required-id presence checks — all
fail-closed at config-load — realising the #17 spec→Project shape (spec→Project,
phase→Issue, task→sub-issue) entirely through config.

**Independent test**: Configure the #17 alternative and confirm the mirror uses
those artifacts with the configured parent relationships; then configure a
nonsensical hierarchy relationship and confirm the run is rejected before any
write.

- [ ] T015 [P] [US2] Unit test `tests/unit/mapping_project_level.bats` — `reconcile::sync_level_artifact` creates/updates the configured artifact (Project / Issue / sub-issue) under the parent via the configured relationship; `reconcile::link_to_parent` applies `parent` (sub-issue nesting) and no-ops for `none`/`checklist`; idempotent match by the resolved identity key (`contracts/config-reconcile-interface.md` §projection)
- [ ] T016 [P] [US2] Unit test `tests/unit/mapping_identity_keys.bats` — a level projected to a standalone Issue or a Project (the #17 alternative) carries a stable filesystem-derived identity label so re-runs match/update rather than re-create (FR-009)
- [ ] T017 [US2] Implement `reconcile::sync_level_artifact` + `reconcile::link_to_parent` in `src/reconcile.sh` — mapping-driven create/update of the configured artifact with the configured relationship, reading artifact/relationship/identity from `config::resolved_*`; sub-issue nesting via `parent`; idempotent match by identity label (FR-003, FR-004, FR-009)
- [ ] T018 [US2] Wire `src/reconcile.sh` orchestration so `config::mapping_validate` (relationship matrix + required-id) runs before the write loop; a failure aborts the run with exit 2 and writes nothing (FR-007, FR-013, fail-closed)
- [ ] T019 [US2] Integration test `tests/integration/mapping-us2-spec-as-project.bats` — a `mapping:` block of spec→Project, phase→Issue, task→sub-issue creates a Project per spec, an Issue per task phase, and a sub-issue per task with the configured parent relationships (#17 shape realised, spec scenario 1), AND a re-run against the unchanged corpus asserts **zero churn** (0 created / 0 updated) — the non-default arm of SC-004
- [ ] T020 [US2] Integration test `tests/integration/mapping-us2-nonsensical-failclosed.bats` — a `mapping:` block with `blocks` used to nest a child, a `parent` on the top level, and a `checklist` artifact paired with a non-`checklist` relationship are each rejected at config-load with a clear error and zero writes (spec scenarios 2–3, SC-003)

**Checkpoint**: US2 delivers the core value — #17 resolved as a safe, validated,
configurable choice.

---

## Phase 5: User Story 3 — Partial mapping inherits the default per level (P2)

**Goal**: Overriding only one level (e.g. promote spec→Project) leaves the others
inheriting the synthesized default, so the #17 toggle is a one-line change and
partial blocks stay back-compatible.

**Independent test**: Configure a `mapping:` block specifying only `spec` and
confirm the unspecified `repo`, `phase`, and `task` levels mirror exactly as the
synthesized default would, with a zero-churn re-run.

- [ ] T021 [P] [US3] Integration test `tests/integration/mapping-us3-partial-inherit.bats` — a `mapping:` block specifying only the `spec` level mirrors with `repo`/`phase`/`task` inheriting the synthesized default (repo→Project, phase→sub-issue, task→checklist) and only `spec` reflecting the override; a re-run with no disk changes performs zero writes (spec scenarios 1–2, SC-005)
- [ ] T022 [US3] Confirm per-level inheritance (T008) drives the projection end-to-end through `src/reconcile.sh` — a partially-specified block resolves each unspecified level via `config::resolved_*` to the synthesized default; no all-or-nothing path remains (FR-005)

**Checkpoint**: US3 makes the grammar ergonomic — partial blocks just work, and a
partial block equals the full block with the same overrides (SC-005).

---

## Phase 6: User Story 4 — Optional narrative super-level above the repo (P3)

**Goal**: An off-by-default L0 narrative super-level that projects to a Linear
Milestone where Project Milestones are available and folds the narrative onto the
repo level (stable marker + grouping label) where they are not — never
hard-failing (FR-011).

**Independent test**: With the super-level on, run against a team that supports
Milestones and confirm a Milestone is created above the repo level with its
narrative populated only from the explicit source; run against one that does not
and confirm the narrative folds behind a stable marker with a grouping label and
no hard failure.

- [ ] T023 [P] [US4] Unit test `tests/unit/milestone_probe.bats` — `graphql::probe_milestone_support` returns `present`/`absent` from the Milestone-capability response; `graphql::ensure_milestone` creates the Milestone above the repo level with the narrative populated only from the explicit `spec_input` source, never inferred (FR-012), when present
- [ ] T024 [P] [US4] Unit test `tests/unit/milestone_degrade.bats` — `graphql::degrade_milestone_onto_repo` folds the narrative onto the repo level behind a stable marker and carries repo grouping via a grouping label when absent; never hard-fails; re-runs in the degraded state are zero-churn and a later re-home onto a real Milestone is churn-free (FR-011, SC-006); the spec level stays the sole backward-drift anchor (FR-010)
- [ ] T025 [US4] Implement `graphql::probe_milestone_support` + `graphql::ensure_milestone` in `src/graphql.sh` — gated on the resolved `super_level` state; populate narrative only from the explicit `spec_input` source (FR-011, FR-012)
- [ ] T026 [US4] Implement `graphql::degrade_milestone_onto_repo` (+ re-home) in `src/graphql.sh` — stable-marker fold onto the repo level + grouping label when Milestones are absent; idempotent degrade↔re-home (FR-011)
- [ ] T027 [US4] Wire the L0 super-level into `src/reconcile.sh` orchestration — when enabled, probe then create-or-degrade above the repo level; the super-level is NOT a new drift surface (FR-010); off by default leaves behaviour matching US1
- [ ] T028 [US4] Integration test `tests/integration/mapping-us4-milestone.bats` — super-level on + Milestones available ⇒ a Milestone is created above the repo level (narrative from the explicit source only); on + unavailable ⇒ narrative folds onto the repo level behind a marker, repo grouping becomes a label, run succeeds; off ⇒ behaviour matches US1 (spec scenarios 1–3, SC-006)

**Checkpoint**: US4 delivers the differentiating narrative super-level with
graceful degradation.

---

## Phase N: Polish & Cross-Cutting

- [ ] T029 [P] shellcheck `--shell=bash --severity=style` clean across all touched `src/*.sh` (`config.sh`, `reconcile.sh`, `graphql.sh`); fix findings (CI uses `--severity=style`)
- [ ] T030 [P] yamllint clean on the updated config template + any fixture YAML
- [ ] T031 [P] markdownlint-clean across `specs/007-configurable-mapping/**/*.md` (`npx markdownlint-cli2`)
- [ ] T032 [P] Extend `tests/unit/no-real-identifiers.bats` coverage over the new fixtures (`milestone_meta/`, `mapping_configs/`, the template `mapping:` block); confirm placeholders only (FR-018)
- [ ] T033 [P] Update `README.md` — reframe the mapping table (~L138) + cover line as the **default** mapping and document the opt-in `mapping:` block (the #17 spec→Project shape, partial inheritance, the L0 Milestone super-level); keep the auto-sync flow first (Principle VII) — constitution v2.1.0 propagation
- [ ] T034 [P] Update `CONTRIBUTING.md` (L8) — "locked data-model mapping" → "default data-model mapping (configurable per spec 007)" — constitution v2.1.0 propagation
- [ ] T035 [P] Update `CHANGELOG.md` (Unreleased: configurable artifact mapping — alias default, per-level mapping + relationship-validation matrix, #17 spec→Project shape, partial inheritance, optional L0 Milestone super-level; constitution v2.1.0)
- [ ] T036 [P] Validate `specs/007-configurable-mapping/quickstart.md` against the shipped behaviour (default, #17 shape, partial, L0) and correct any drift
- [ ] T037 Run the exact CI locally (shellcheck `--severity=style` + yamllint + markdownlint + bats unit + integration) and fix to green before pushing; ubuntu CI is authoritative over macOS for any GNU/BSD difference

---

## Dependencies & completion order

- **Setup (T001–T002)** → **Foundational (T003–T010)** block everything.
- **US1 (T011–T014)** depends only on Foundational → it is the regression-anchor
  MVP and ships alone.
- **US2 (T015–T020)** depends on Foundational (parse + alias + resolved accessors
  + validation gate) and adds the mapping-driven projection; independent of
  US3/US4.
- **US3 (T021–T022)** depends on Foundational (per-level inheritance, T008) + the
  US2 projection path; smallest slice.
- **US4 (T023–T028)** depends on Foundational + the repo-level path (US1) + the
  Milestone GraphQL helpers; the lowest-priority slice.
- **Polish (T029–T037)** last.

Story order: US1 → US2 → US3 → US4.

## Parallel execution examples

- Foundational tests: T003, T004, T005, T006 (separate test files) run together
  before implementing T007–T010 (all in `src/config.sh`, sequential).
- US2 tests: T015, T016 (separate test files) run together before the
  `src/reconcile.sh` implementation (T017–T018, same file, sequential).
- US4 tests: T023, T024 (separate test files) run together before the
  `src/graphql.sh` implementations.
- Implementation tasks in the same file (`src/config.sh`, `src/reconcile.sh`,
  `src/graphql.sh`) are sequential; cross-file `[P]` tasks are not.

## Implementation strategy

- **MVP = Phase 1 + 2 + US1** (T001–T014): the alias-layer regression anchor —
  prove the no-config upgrade changes nothing, byte-for-byte.
- Then layer US2 (the #17 configurable mapping + fail-closed validation),
  followed by US3 (partial inheritance) and US4 (L0 Milestone super-level).
- Tests precede implementation within each phase; the curl-shim keeps every unit
  and integration test offline. Idempotency / drift / fail-closed / privacy are
  threaded through every story. Run all gates before every push.
