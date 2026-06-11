---
description: "Task list for 008-adr-mirroring"
---

# Tasks: ADR / Decision-Record Mirroring

**Input**: Design documents from `/specs/008-adr-mirroring/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — idempotency is the constitutional gate (Principles II/III,
SC-002) and the contracts (`research-adr-grammar.md`, `adr-comment.md`) define
bats obligations. Test tasks precede the implementation they cover.

**Organization**: by user story (US1–US3). This is an **additive** extension of
the 001 bridge — a near-clone of the clarify-session comment path. No config or
schema change; the only new mutation is `commentUpdate` (update-in-place).

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: parallelizable (different file, no dependency on an incomplete task)
- **[USx]**: the user story a task serves (story phases only)

---

## Phase 1: Setup

- [X] T001 [P] Add a `research.md` ADR fixture set under `tests/fixtures/specs/`
  (a spec dir with `research.md` containing: a headed `## D1 — Title` block, a
  headed `## R2 — Title` block, an un-headed `Decision:/Rationale:/Alternatives:`
  block, a block missing the Alternatives sub-part, and two un-headed same-title
  blocks) — placeholders only, no real coordinates (FR-012)

---

## Phase 2: Foundational (blocking prerequisites for ALL stories)

**Purpose**: the `research.md` ADR reader and the `commentUpdate` wrapper — both
underpin every story. `parser::adr_records` in `src/parser.sh`; the mutation
wrapper in `src/reconcile.sh`. Unit tests first.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 [P] Unit test `tests/unit/adr_parser.bats` — `parser::adr_records`
  parses each `## D<N>/R<N> — Title` block (and un-headed `Decision:` prose) into
  one record with id/title/decision/rationale/alternatives/source per
  `contracts/research-adr-grammar.md`; key = heading id when present, else a
  title slug, with a positional suffix disambiguating same-title un-headed
  blocks; a missing sub-part is omitted (not an error); no `research.md` / no
  blocks → empty output (FR-001/FR-003/FR-007)
- [X] T003 Implement `parser::adr_records <spec_dir>` in `src/parser.sh` —
  read `research.md`, emit one record per ADR (tab-separated fields per the
  grammar contract), `LC_ALL=C awk` for GNU/BSD parity; deterministic key
  derivation; graceful-empty
- [X] T004 [P] Unit test `tests/unit/comment_update.bats` —
  `reconcile::mutate_comment_update <comment_id> <body>` issues `commentUpdate`,
  honours `ARG_DRY_RUN` (logs, no call), and surfaces a transport/`success`
  failure per the existing `mutate_*` convention (`contracts/adr-comment.md`)
- [X] T005 Implement `reconcile::mutate_comment_update` in `src/reconcile.sh` —
  `commentUpdate(id, input:{body})` wrapper mirroring `mutate_comment_create`'s
  dry-run + success-check + summary shape (the one new mutation)

**Checkpoint**: `research.md` ADRs parse into records, and a comment can be
updated in place — the foundation every story builds on.

---

## Phase 3: User Story 1 — Decisions show up on the spec's Linear Issue (P1) 🎯 MVP

**Goal**: Each ADR in a spec's `research.md` becomes one comment on that spec's
Linear Issue, in the ADR layout.

**Independent test**: Reconcile a spec whose `research.md` has two ADR blocks and
confirm the spec Issue gains exactly two ADR comments with the decision,
rationale, alternatives, and source.

- [X] T006 [P] [US1] Unit test `tests/unit/adr_comments_create.bats` —
  `reconcile::sync_adr_comments` renders one comment per ADR with the
  `<!-- spec-kit-linear: adr <NNN>-<key> -->` marker + the ADR body layout, and
  creates each when absent (stubbed transport); a missing sub-part is omitted
  from the body (spec scenario 1, `contracts/adr-comment.md`)
- [X] T007 [US1] Implement `reconcile::sync_adr_comments <spec_issue_id>
  <spec_dir>` in `src/reconcile.sh` — near-clone of `sync_clarify_comments`:
  for each `parser::adr_records` record, compose the marked body, look up the
  existing comment via `reconcile::query_existing_comment_body` (returns
  `{id,body}`), and create when absent (the create + render half; the
  skip/update half lands in US2)
- [X] T008 [US1] Wire `reconcile::sync_adr_comments` into
  `reconcile::process_spec` immediately after the `sync_clarify_comments` call,
  guarded `|| true` so an ADR failure never blocks the rest of the per-spec
  reconcile (FR-008, FR-024 precedent)
- [X] T009 [P] [US1] Unit test `tests/unit/adr_comments_absent.bats` — a spec
  with no `research.md` or no decision blocks posts zero ADR comments and the
  reconcile completes normally (FR-007, SC-004)

**Checkpoint**: US1 delivers the core value — decisions surface on the spec Issue.

---

## Phase 4: User Story 2 — Re-running never duplicates or churns (P1)

**Goal**: At-most-once per ADR; unchanged corpus = zero churn; a changed ADR
updates its single comment in place; a new ADR adds exactly one comment.

**Independent test**: Reconcile twice unchanged (zero writes), then change one
ADR (exactly one comment updated, no duplicate), then add one ADR (exactly one
new comment).

- [X] T010 [P] [US2] Unit test `tests/unit/adr_comments_idempotent.bats` —
  re-running against an unchanged corpus performs zero creates and zero updates
  (existing body == rendered body → skip); the rendered body is byte-stable for
  an unchanged ADR (no timestamps; LF-only; trimmed) (FR-004, SC-002)
- [X] T011 [P] [US2] Unit test `tests/unit/adr_comments_update.bats` — when an
  ADR's content changes, `sync_adr_comments` calls
  `reconcile::mutate_comment_update` on the matched comment id and creates NO
  duplicate (matched by marker key, not content) (FR-005, SC-003)
- [X] T012 [US2] Complete the `reconcile::sync_adr_comments` state machine in
  `src/reconcile.sh` — on a marker match, compare body: identical → skip
  (zero churn); differ → `mutate_comment_update` in place; a newly-added ADR →
  create exactly one (FR-004/FR-005/FR-006). (Update-in-place is the deliberate
  delta from the clarify path's warn-don't-overwrite — Principle I.)

**Checkpoint**: US2 makes the mirror idempotent + update-in-place — the
constitutional safety promise.

---

## Phase 5: User Story 3 — Consistent with the Jira sibling (P2)

**Goal**: The ADR comment's user-visible shape (fields, ordering, source
back-reference, one-per-decision placement) matches the spec-kit-jira ADR
feature.

**Independent test**: Compare the rendered ADR comment body against the
documented parity shape and confirm the fields + ordering + source line match.

- [X] T013 [P] [US3] Unit test `tests/unit/adr_comments_parity.bats` — assert the
  rendered ADR comment body matches the byte-stable parity layout documented in
  `contracts/adr-comment.md` (heading `ADR <key> — <title>  [<status>]`, then
  Decision / Rationale / Alternatives sections, then `Source:` line) — a golden
  shape so a future drift from the Jira sibling is caught (FR-009, SC-005)

**Checkpoint**: US3 locks the cross-sink parity shape.

---

## Phase N: Polish & Cross-Cutting

- [X] T014 [P] shellcheck `--shell=bash --severity=style` clean across the
  touched `src/*.sh` (`parser.sh`, `reconcile.sh`); fix findings
- [X] T015 [P] markdownlint-clean across `specs/008-adr-mirroring/**/*.md`
- [X] T016 [P] Extend `tests/unit/no-real-identifiers.bats` over the new
  `research.md` ADR fixtures; confirm placeholders only (FR-012)
- [X] T017 [P] Update `README.md` — a short note that a spec's `research.md`
  decisions are mirrored as ADR comments on the spec Issue (additive; keep the
  auto-sync framing per Principle VII)
- [X] T018 [P] Update `CHANGELOG.md` (Unreleased: ADR / decision-record mirroring
  — research.md Decision/Rationale/Alternatives → at-most-once, update-in-place
  comments on the spec Issue; parity with the spec-kit-jira ADR feature)
- [X] T019 Run the exact CI locally (shellcheck `--severity=style` + yamllint +
  markdownlint + bats unit) and fix to green before pushing; ubuntu CI is
  authoritative over macOS for any GNU/BSD difference

---

## Dependencies & completion order

- **Setup (T001)** → **Foundational (T002–T005)** block everything.
- **US1 (T006–T009)** depends on Foundational (parser + comment query/create) →
  the MVP; ships the create + render half.
- **US2 (T010–T012)** depends on US1's `sync_adr_comments` → adds the skip/update
  state machine; independent of US3.
- **US3 (T013)** depends on US1's render → a parity assertion on the body shape.
- **Polish (T014–T019)** last.

Story order: US1 → US2 → US3.

## Parallel execution examples

- Foundational tests T002 + T004 (separate files) run together before T003/T005.
- US1 tests T006 + T009 run together before/with T007.
- US2 tests T010 + T011 (separate files) run together before T012.
- Implementation tasks in the same file (`src/reconcile.sh`: T005, T007, T008,
  T012) are sequential; cross-file `[P]` tasks are not.

## Implementation strategy

- **MVP = Phase 1 + 2 + US1** (T001–T009): decisions surface on the spec Issue.
- Then US2 (idempotency + update-in-place) and US3 (parity shape).
- Tests precede implementation within each phase; all new logic is offline
  (stubbed transport). Idempotency / drift / fail-closed are threaded through.
  Run all gates before pushing.
