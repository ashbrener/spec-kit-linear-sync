---
description: "Task list for feature 013 — lifecycle cascade to task-phase sub-issues"
---

# Tasks: Lifecycle Cascade to Task-Phase Sub-Issues

**Input**: Design documents from `/specs/013-subissue-cascade/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — the project's `bats` convention plus the spec's test-bearing
success criteria (SC-001 cascade, SC-002 idempotency, SC-003 non-terminal
regression, SC-004 letter phases, SC-005 near-miss preserved) make behavioural
tests required for acceptance.

**Branch**: `013-subissue-cascade` (off `origin/main`)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files / disjoint regions, no dep on incomplete tasks)
- **[Story]**: US1 (cascade, P1) / US2 (letter phases, P2)
- Exact file paths included per task

## Path Conventions

Single-project Bash bridge: `src/` (engine), `tests/unit` + `tests/integration` (bats).

> **Anchor on named functions, not line numbers.** Verified anchors on this
> branch's base (`origin/main`): `reconcile::sync_task_phase_subissues` (3-arg
> signature), its call site in `reconcile::process_spec` (passes 3 args),
> `reconcile::subissue_state_key`, `PARSER_PHASE_HEADER_AWK` / `split_phase_header`,
> `parser::task_phases` (emits `<idx>\t<name>`), `parser::tasks_in_phase`.

---

## Phase 1: Setup

- [X] T001 [P] Confirm `done` is a valid `default_state_uuids` key (it is — `config::get_default_state_uuid done`) and capture the exact `sync_task_phase_subissues` create-state site, update-state diff, sub-issue title, `task-phase:<idx>` label, and blocking-order sites in `src/reconcile.sh` (grep the function) so US1/US2 edits land on the right lines.

---

## Phase 2: User Story 1 — Merged spec's phases read Done (Priority: P1) 🎯 MVP

**Goal**: a terminal-phase spec forces every task-phase sub-issue to Done,
overriding the checkbox ratio. Fixes Mode 1 (numeric specs stuck Todo). Independent
of the parser change — works on today's numeric `task_phases` output.

**Independent test**: merge a numeric-phase spec without ticking boxes → all its
sub-issues Done; re-run zero-churn; a non-terminal spec unchanged.

- [X] T002 [US1] Thread `lifecycle_phase` into `reconcile::sync_task_phase_subissues` in `src/reconcile.sh` — add a 4th positional arg `local lifecycle_phase="${4:-}"`; update the call site in `reconcile::process_spec` to pass `"$lifecycle_phase"` (already in scope). (contracts/cascade.md §1)
- [X] T003 [US1] In the per-phase loop, compute the state key as terminal-aware in `src/reconcile.sh`: `case "$lifecycle_phase" in ready_to_merge|merged) state_key="done" ;; *) state_key="$(reconcile::subissue_state_key "$tasks_md" "$phase_index")" ;; esac`. Apply on **both** the create-time `stateId` site and the update-time state diff (`cur_state != state_uuid`). Leave `reconcile::subissue_state_key` unchanged. Depends on T002 (same function). (contracts/cascade.md §2)
- [X] T004 [P] [US1] Unit test `tests/unit/subissue_cascade.bats` — the terminal-aware state-key resolution: `ready_to_merge`→`done`, `merged`→`done`, `implementing`/`planning`→checkbox ratio (stub `subissue_state_key`/`tasks_in_phase`); idempotent (same key twice); a non-terminal spec's key is byte-identical to `subissue_state_key` (SC-003).

**Checkpoint**: US1 fixes Mode 1 — merged numeric specs read Done. MVP done.

---

## Phase 3: User Story 2 — Letter-indexed phases get sub-issues (Priority: P2)

**Goal**: `## Phase A — …` headers parse to one sub-issue per phase
(`task-phase:1`, title `Phase 1 — …`), without regressing the near-miss
diagnostic. Fixes Mode 2 (letter specs → zero sub-issues). Ordinal-only — no
`task_phases` contract change and no reconcile read-loop change (the title, label,
and blocking already use the ordinal `idx`).

**Independent test**: a spec with `## Phase A —`/`## Phase B —` → 2 sub-issues,
labels `task-phase:1`/`task-phase:2`, titles `Phase 1 —`/`Phase 2 —`; `## Phase one`
still warns.

- [X] T005 [US2] Broaden `split_phase_header` in the `PARSER_PHASE_HEADER_AWK` prologue (`src/parser.sh`) — accept INDEX = digit-run **or** a single `[A-Za-z]`, keeping the existing separator/whitespace/EOL gate so `## Phase one` / `## Phase 1Setup` / `## Phase AB` / `## Phase :` still fail. Set `out["idx"]` = ordinal (digits as-is; single letter → case-insensitive alphabet position A→1…Z→26). **No new output field** — `out["name"]` unchanged. `parser::task_phases` / `tasks_in_phase` / `phase_estimate` are UNCHANGED (still `<idx>\t<name>`, still match on `idx` — now numeric for letter phases). The reconcile read loop, sub-issue title (`Phase <idx> — <name>`), `task-phase:<idx>` label, and blocking order are all UNCHANGED (a letter phase renders `Phase 1 — …` for free). (contracts/phase-header-grammar.md)
- [X] T006 [P] [US2] Unit test `tests/unit/phase_header_grammar.bats` — `split_phase_header`: digit (`idx=1`); single letter `A`→`idx=1`, `b`→`idx=2`; reject `## Phase one`, `## Phase 1Setup`, `## Phase AB`, `## Phase :` (ok=0); em-dash separator with a letter index parses (`## Phase A — X` → idx=1, name=X).
- [X] T007 [P] [US2] Unit test `tests/unit/letter_phase_enumeration.bats` — `parser::task_phases` on a letter-indexed fixture emits `1\t<name>` / `2\t<name>` (2-field, ordinal); `parser::tasks_in_phase <fixture> 1` returns the tasks under `## Phase A`; `parser::phase_header_near_misses` still flags `## Phase one`. Confirms the existing 2-field contract is preserved (numeric `tests/unit/parser.bats` assertions stay valid).

**Checkpoint**: US2 fixes Mode 2 — letter specs produce sub-issues; near-miss intact; numeric specs byte-identical.

---

## Phase 4: Polish & Cross-Cutting

- [X] T008 [P] Lint: `shellcheck --shell=bash --severity=style` over ALL `src/**/*.sh` in one invocation (SC2120 cross-file lesson), plus `bash -n`; fix findings.
- [X] T009 [P] Docs: `README.md` — note that a merged spec's task-phase sub-issues read Done and that phase headers accept a single-letter index (`## Phase A —`, rendered `Phase 1 —`); add a `CHANGELOG.md` `[Unreleased]` entry (amends FR-005/FR-013).
- [X] T010 [P] Docs: ensure `specs/013-subissue-cascade/quickstart.md` matches the final behaviour/names if anything was renamed during implementation.
- [X] T011 [P] Integration test (gated `RUN_INTEGRATION_TESTS`) `tests/integration/subissue-cascade.bats` — merged **numeric** spec (un-ticked boxes) → every sub-issue Done; merged **letter** spec → one sub-issue per phase, all Done, labels `task-phase:1..N`; re-run zero-churn (no sub-issue state writes on the 2nd pass).
- [X] T012 Full suite: `bats tests/unit` (+ shellcheck/yamllint/markdownlint) green on this branch; confirm the existing `tests/unit/parser.bats` numeric `task_phases` assertions still pass unchanged (ordinal-only design preserves the 2-field contract); confirm pre-existing macOS integration flakes unaffected; verify SC-001..SC-005 each covered; confirm `extension.yml` `id` still `linear` and no command/hook surface changed (FR-010).

---

## Dependencies & Execution Order

- **Setup (T001)** → **US1 (T002-T004)** → **US2 (T005-T007)** → **Polish (T008-T012)**.
- **US1 (cascade) is the MVP** and is independent of the parser change — it ships
  the Mode-1 fix on its own.
- **US2 (parser)** is a single, localized `split_phase_header` change (T005);
  because the design is ordinal-only there is **no** `task_phases`/read-loop edit,
  so US2 does not touch `sync_task_phase_subissues` and is independent of US1.
- `subissue_state_key` and the `task_phases` output contract are never modified.

## Parallel Execution Examples

- **US1**: T004 (test) alongside T002→T003 authoring (separate file).
- **US2**: T005 (parser), then T006 ∥ T007 (separate bats files).
- **Polish**: T008 ∥ T009 ∥ T010 ∥ T011.

## Implementation Strategy

- **MVP = Phase 1 + 2 (US1)**: the cascade alone heals Mode 1 (merged numeric
  specs stuck Todo) — the headline defect. Independently shippable.
- **Increment 2 = US2**: one parser-grammar change heals Mode 2 (letter specs →
  zero sub-issues), ordinal-only, with no contract churn.
- **Polish**: lint, docs, gated integration, full-suite green.

## Coverage map (success criteria → tasks)

| SC | Covered by |
|---|---|
| SC-001 merged → children Done | T003, T011 |
| SC-002 idempotent zero-churn | T003 design, T004, T011 |
| SC-003 non-terminal unchanged | T003, T004 |
| SC-004 letter specs → sub-issues | T005, T007, T011 |
| SC-005 near-miss preserved | T005, T006, T007 |
