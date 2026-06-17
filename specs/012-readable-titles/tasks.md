---
description: "Task list for feature 012 — human-readable Issue titles"
---

# Tasks: Human-Readable Issue Titles

**Input**: Design documents from `/specs/012-readable-titles/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — the project's `bats` convention plus the spec's test-bearing
success criteria (SC-002 idempotency, SC-003 determinism/CI parity, SC-004
never-empty/never-placeholder, SC-005 single-line cap) make behavioural tests
required for acceptance.

**Branch**: `012-readable-titles` (off `origin/main`)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files / disjoint regions, no dep on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (maps to spec.md user stories)
- Exact file paths included per task

## Path Conventions

Single-project Bash bridge: `src/` (engine), `tests/unit` + `tests/integration` (bats).

> **Anchor on named functions, not line numbers.** The `~Lxxxx` hints derive from
> the current tree; grep for the function (e.g. the single `local title=` in
> `reconcile::sync_spec_issue`, ~L2863) rather than trusting the offset.

---

## Phase 1: Setup

- [X] T001 [P] Add the title length-cap constant `RECONCILE_SPEC_TITLE_MAX_CHARS` (≈80) to `src/reconcile.sh` near the other `RECONCILE_*` cap constants (e.g. beside `RECONCILE_SPEC_CONTENT_MAX_CHARS`), with a comment that it keeps the title to one scannable line (FR-004 / research D5).

---

## Phase 2: Foundational (the deterministic title-resolution layer — blocks US1)

- [X] T002 [P] Implement `parser::spec_h1_name <spec_md>` in `src/parser.sh` — match the first `^#[[:space:]]+Feature Specification:[[:space:]]*(.+)$` line, echo the trimmed name; emit empty when the file/heading is absent, the name is empty, or it is exactly `[FEATURE NAME]`. BSD-awk-safe (no gawk-isms), graceful (`name="$(…)" || name=""`). Add to the parser.sh public-functions header. (FR-002 / contracts §1 / research D3)
- [X] T003 [P] Implement `reconcile::_first_sentence <text>` in `src/reconcile.sh` — squeeze internal whitespace/newlines to single spaces, trim, cut at the first sentence terminator (a period followed by a space, or end-of-text); empty input → empty output. Pure-string, deterministic. (contracts §2 / research D4)
- [X] T004 Implement `reconcile::_compose_spec_title <feature_number> <spec_dir> <short_name>` in `src/reconcile.sh` — resolve H1 (T002) → first-sentence of `reconcile::_extract_input` (T003) → slug; for H1/Input compose `"<NNN> — <name>"` and clean-boundary length-cap to `RECONCILE_SPEC_TITLE_MAX_CHARS` (cut to cap, back up to last space, append `…`); slug last-resort returns `"<feature_number>-<short_name>"` verbatim. MUST never return empty / never contain `[FEATURE NAME]` (FR-003/FR-007). Depends on T001–T003 (same file + parser). (contracts §2 / research D1/D5)

### Foundational tests

- [X] T005 [P] Unit tests `tests/unit/spec_h1_name.bats` — real name extracted + trimmed; `[FEATURE NAME]` placeholder → empty; missing heading/file → empty; trailing markup/whitespace trimmed.
- [X] T006 [P] Unit tests `tests/unit/compose_spec_title.bats` — H1 wins → `"<NNN> — <name>"`; placeholder-H1 + Input → first-sentence-derived title; no H1 + no Input → `"<NNN>-<slug>"`; `_first_sentence` (period / newline / multi-line squeeze); length-cap clean-boundary + `…`; never empty / never `[FEATURE NAME]`; same input → byte-identical output twice (determinism, SC-003).

**Checkpoint**: resolution layer complete + unit-green — US1 can wire in.

---

## Phase 3: User Story 1 — Board reads like features (Priority: P1) 🎯 MVP

**Goal**: spec Issue title is `"<NNN> — <human title>"`, not the slug.

**Independent test**: reconcile a repo of H1-named specs → each Issue title is `<NNN> — <H1 name>`.

- [X] T007 [US1] In `src/reconcile.sh` `reconcile::sync_spec_issue`, replace the single `local title="${feature_number}-${short_name}"` (~L2863) with `local title="$(reconcile::_compose_spec_title "$feature_number" "$spec_dir" "$short_name")"`. Leave the create input (`title: $title`) and the update-path title-diff (`current_title != title → {title}`) unchanged. Depends on T004.
- [X] T008 [P] [US1] Unit test `tests/unit/title_projection.bats` — assert `sync_spec_issue` composes the title via `_compose_spec_title` for a filled-H1 spec (`<NNN> — <name>`), and that the slug fallback still yields `<NNN>-<slug>` for a bare spec. (Stub config/transport per the `tests/unit/reconcile.bats` harness; assert the composed `title` value, not a live mutation.)

**Checkpoint**: US1 demoable — readable titles on the board.

---

## Phase 4: User Story 2 — Idempotent, deterministic re-runs (Priority: P1)

**Goal**: unchanged spec ⇒ no title write; identical title across interactive/CI.

**Independent test**: compose twice over an unchanged spec → byte-identical; assert the update diff fires no title write when `current_title == composed`.

- [X] T009 [P] [US2] Unit test `tests/unit/title_idempotency.bats` — `_compose_spec_title` is byte-stable across repeated calls for the same spec (SC-002/SC-003); and the update-path guard semantics hold: when `current_title` equals the composed title, no `{title}` key is added to the update input (zero churn); when the H1 changes, the title updates exactly once.
- [X] T010 [P] [US2] Unit test `tests/unit/title_migration.bats` — given a current title of the old slug form `<NNN>-<slug>` and a filled H1, the composed title differs ⇒ exactly one re-title; a second pass with the new title present ⇒ zero churn (SC-006).

**Checkpoint**: idempotency + migration proven.

---

## Phase 5: User Story 3 — Every spec gets a stable, non-broken title (Priority: P2)

**Goal**: placeholder/missing H1 never yields an empty or `[FEATURE NAME]` title.

**Independent test**: compose for a placeholder-H1 spec and a no-H1/no-Input spec → Input-derived and slug respectively; never empty, never `[FEATURE NAME]`.

- [X] T011 [P] [US3] Unit test `tests/unit/title_graceful.bats` — placeholder-H1 (`[FEATURE NAME]`) + Input → Input-first-sentence title (no `[FEATURE NAME]`, SC-004); no H1 + no Input → `<NNN>-<slug>` (stable, non-empty); long H1 → capped to one line within `RECONCILE_SPEC_TITLE_MAX_CHARS` (SC-005).
- [X] T012 [P] [US3] Scope-guard unit test `tests/unit/title_scope.bats` — assert sub-issue `Phase N — <Name>` title composition and the `speckit-spec:NNN` identity label are NOT routed through `_compose_spec_title` (structural: the composer is referenced only at the spec-Issue title site, not the sub-issue title sites). (FR-009 / contracts I7)

**Checkpoint**: graceful degradation + scope containment proven.

---

## Phase 6: Polish & Cross-Cutting

- [X] T013 [P] Lint: `shellcheck --shell=bash --severity=style` over ALL `src/**/*.sh` in one invocation (the SC2120 cross-file lesson from 010), plus `bash -n`; fix findings.
- [X] T014 [P] Docs: add a short "Readable titles" note to `README.md` (the `What lands in Linear` title row + a one-liner that titles come from the spec H1, default-on) and a `CHANGELOG.md` `[Unreleased]` entry.
- [X] T015 [P] Docs: ensure `specs/012-readable-titles/quickstart.md` matches the final function/constant names if any were renamed during implementation.
- [X] T016 [P] Integration test (gated `RUN_INTEGRATION_TESTS`) `tests/integration/readable-titles.bats` — a fixture repo with one filled-H1 spec and one placeholder-H1 spec → titles `<NNN> — <name>` and `<NNN> — <input sentence…>`; a re-run produces zero title churn.
- [X] T017 Full suite: `bats tests/unit` (+ shellcheck/yamllint/markdownlint) green on this branch; confirm pre-existing macOS integration flakes unaffected; verify SC-001..SC-006 each covered by a passing test; confirm `extension.yml` `id` is still `linear` and no command/hook surface changed (FR-010).

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002–T006)** → **US1 (T007–T008)** → US2 (T009–T010) / US3 (T011–T012) → **Polish (T013–T017)**.
- **US1 depends on Foundational** (the composer). US1 is the MVP and is demoable once T007 lands.
- **US2/US3** are mostly tests over the foundational composer + the existing update-diff; they depend on US1's wiring.
- Same-file ordering: T002 (parser.sh) ∥ T001/T003 (reconcile.sh) → T004 (reconcile.sh, needs T002+T003) → T007 (reconcile.sh title site).

## Parallel Execution Examples

- **Foundational**: T002 (parser.sh) ∥ T003 (reconcile.sh) ∥ T005 (test) → then T004 → T006.
- **US2/US3 tests**: T009 ∥ T010 ∥ T011 ∥ T012 (separate bats files) after US1.
- **Polish**: T013 ∥ T014 ∥ T015 ∥ T016.

## Implementation Strategy

- **MVP = Phase 1 + 2 + 3 (US1)**: the resolution layer + the one-line swap in
  `sync_spec_issue`. Delivers readable titles for every spec, retroactively.
- **Increment 2 = US2**: lock idempotency/determinism/migration with tests (low
  code, high assurance — the update-diff already exists).
- **Increment 3 = US3**: graceful degradation + scope-containment tests.
- **Polish**: lint, docs, gated integration, full-suite green.

## Coverage map (success criteria → tasks)

| SC | Covered by |
|---|---|
| SC-001 readable title from H1 | T004, T007, T008, T016 |
| SC-002 idempotent zero-churn | T004 design, T009 |
| SC-003 deterministic / CI parity | T004, T006, T009 |
| SC-004 never empty / never `[FEATURE NAME]` | T004, T011 |
| SC-005 single-line length cap | T004, T011 |
| SC-006 one-time re-title migration | T010, T016 |
