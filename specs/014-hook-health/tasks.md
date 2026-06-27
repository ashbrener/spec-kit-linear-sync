---

description: "Task list for 014-hook-health implementation"
---

# Tasks: Hook Self-Healing (auto-sync hook health check)

**Input**: Design documents from `/specs/014-hook-health/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/hookcheck.md ✓

**Tests**: INCLUDED — this repo is test-first (bats unit + integration); the spec,
plan, and quickstart all specify test coverage. Write each test FIRST and confirm it
FAILS before the implementing task.

**Organization**: by user story (US1 = reconcile warning + self-heal, P1; US2 = status
hook-health line, P2). Foundational builds the shared `src/hookcheck.sh` detection core
both stories depend on.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 (no label on Setup / Foundational / Polish)
- Exact file paths included.

## Path Conventions

Single Bash project: `src/*.sh` modules + `tests/{unit,integration}/*.bats` at repo root.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: test scaffolding the rest of the work builds on.

- [x] T001 [P] Add a reusable hookcheck fixture helper that writes sample
  `.specify/extensions.yml` variants (all-present, partial-missing, none-registered,
  `enabled: false`, malformed, file-absent) into a `mktemp` dir, in
  `tests/helpers/hookcheck_fixtures.bash` (sourced by the new bats files; follow the
  `mktemp -d` + heredoc pattern already used in `tests/unit/spec_h1_name.bats`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the shared `src/hookcheck.sh` detection core + safe-composition guards.

**⚠️ CRITICAL**: US1 and US2 both depend on this phase.

- [x] T002 Create `src/hookcheck.sh` with the idempotent include-guard
  (`[[ -n "${_HOOKCHECK_SH_LOADED:-}" ]] && return 0; readonly _HOOKCHECK_SH_LOADED=1`),
  the mirrored `readonly -a HOOKCHECK_AFTER_HOOK_NAMES=(after_specify after_clarify
  after_plan after_tasks after_implement after_analyze)`, and the
  `: "${HOOKCHECK_EXTENSIONS_YML:=.specify/extensions.yml}"` default (per
  contracts/hookcheck.md).
- [x] T003 [P] Add the idempotent include-guard to each shared lib —
  `src/summary.sh`, `src/git_helpers.sh`, `src/graphql.sh`, `src/config.sh`,
  `src/parser.sh`, `src/install.sh` — so re-sourcing during the self-heal causes no
  `readonly` double-declaration (research R3). Guard goes at the very top of each file
  after `set -euo pipefail`; existing single-source callers are unaffected.
- [x] T004 [P] Write FAILING unit tests in `tests/unit/hookcheck.bats`:
  `hookcheck::classify` returns present/disabled/absent for the fixture variants;
  `hookcheck::assess` yields the correct `overall` + `missing`/`disabled` lists;
  malformed file → `unverifiable`; absent file → `not_installed`; and a pin test
  asserting `HOOKCHECK_AFTER_HOOK_NAMES` is identical to `install.sh`
  `INSTALL_AFTER_HOOK_NAMES` (FR-007 / R6).
- [x] T005 Implement `hookcheck::classify <hook> [<yml>]` in `src/hookcheck.sh` — an
  `awk` block-walk using the SAME grammar as `install::_hook_already_registered`
  (`src/install.sh:1800`) extended to read the `enabled:` line; emits
  `present|disabled|absent`, exit 2 on unreadable/malformed (depends on T002).
- [x] T006 Implement `hookcheck::assess [<yml>]` in `src/hookcheck.sh` — aggregate over
  the six names into `overall=…`, `missing=…`, `disabled=…`; always exit 0;
  `not_installed` when file absent, `unverifiable` on malformed (depends on T005).

**Checkpoint**: detection green — `bats tests/unit/hookcheck.bats` passes.

---

## Phase 3: User Story 1 - A stripped hook set becomes a loud one-line fix (Priority: P1) 🎯 MVP

**Goal**: on a reconcile/`speckit.linear.push`, a missing `after_*` hook set produces a
single loud named warning + `/speckit.linear.install` remediation (never blocking), and
— interactively — an optional one-key consented self-heal.

**Independent Test**: in a repo whose `linear` `after_*` hooks were removed, run a
reconcile → it completes (not blocked) AND warns naming the missing hooks; all-present
and `enabled: false` sets produce no warning.

### Tests for User Story 1 ⚠️ (write first, must FAIL)

- [x] T007 [P] [US1] Write FAILING integration test
  `tests/integration/us1-hook-health-warn.bats`: stripped hooks → push warns exactly
  once naming missing hooks + remediation AND reconcile still completes (SC-001/SC-003);
  all six present → zero hook-health warnings (SC-002); a `enabled: false` hook → zero
  warnings (FR-004); `--all` over multiple specs → still exactly one warning (SC-006).
- [x] T008 [P] [US1] Write FAILING unit test `tests/unit/hookcheck_selfheal.bats` for
  `hookcheck::offer_selfheal`: interactive `y` → calls the install register path and
  re-assess reports present (SC-004); `n`/empty/EOF → no-op + warning stands;
  non-interactive (no TTY) → never prompts, never mutates the file (FR-009); a single
  consent re-registers ALL missing hooks at once; a `enabled: false` hook is preserved.

### Implementation for User Story 1

- [x] T009 [US1] Implement `hookcheck::warn_once <overall> <missing...>` in
  `src/hookcheck.sh` — `summary::add warned` naming count + hooks + remediation, gated
  by the `_RECONCILE_HOOKS_WARNED` latch; `unverifiable` → one informational row;
  `present`/`not_installed` → nothing (FR-002/FR-010, depends on T006).
- [x] T010 [US1] Implement `hookcheck::offer_selfheal <overall> <missing...>` in
  `src/hookcheck.sh` — interactive (`[[ -t 0 ]]`) y/N over `/dev/tty` (env-overridable
  `HOOKCHECK_TTY`, mirroring `RECONCILE_DRIFT_TTY`); on `y` lazy-`source install.sh`
  (guarded) and call `install::register_after_hooks`, then `summary::add updated` +
  re-assess; otherwise no-op; non-interactive returns immediately (depends on T003, T009).
- [x] T011 [US1] Wire into `src/reconcile.sh`: add `source "${SCRIPT_DIR}/hookcheck.sh"`
  beside the other sources (~L91), `declare -g _RECONCILE_HOOKS_WARNED=0` beside the
  existing latches (~L175/203), and call `assess` → `warn_once` → `offer_selfheal` once
  in `reconcile::main` after spec enumeration (before/around the per-spec loop) so an
  `--all` sweep checks once (depends on T009, T010).

**Checkpoint**: US1 fully functional — `bats tests/integration/us1-hook-health-warn.bats`
and `tests/unit/hookcheck_selfheal.bats` pass; reconcile is the MVP.

---

## Phase 4: User Story 2 - Check hook health on demand (Priority: P2)

**Goal**: `speckit.linear.status` reports hook-registration health as a first-class line
(present / partial-with-names / none) and, interactively, offers the same self-heal;
status's exit code is never changed.

**Independent Test**: run `speckit.linear.status` in repos with all / some / none of the
hooks registered → each reports the matching state and exits 0.

### Tests for User Story 2 ⚠️ (write first, must FAIL)

- [x] T012 [P] [US2] Write FAILING integration test
  `tests/integration/us2-status-hook-health.bats`: all present → "all present"; some
  missing → "partial" naming the missing hooks; none → "none registered" + remediation;
  AND `status` exits 0 in all three cases (SC-005 + clarification 2026-06-24). Also
  assert the status-path self-heal offer (FR-009): an INTERACTIVE status with missing
  hooks presents the y/N offer, while a NON-INTERACTIVE status reports but never prompts
  and never mutates `.specify/extensions.yml` (covers analysis finding C1).

### Implementation for User Story 2

- [x] T013 [US2] Implement `hookcheck::status_line <overall> <missing...> -- <disabled...>`
  in `src/hookcheck.sh` — human render of the health line; MUST NOT call
  `status::promote_exit` (exit code unchanged, R7) (depends on T006).
- [x] T014 [US2] Wire into `src/status.sh`: add `source "${SCRIPT_DIR}/hookcheck.sh"`
  (~L84), append the hook-health line in `status::emit_human` (~L780) and a
  `hook_health` field in `status::emit_json` (~L742), and call `offer_selfheal`
  interactively after emit; confirm no path mutates the status exit code (depends on
  T013, T010).

**Checkpoint**: US1 AND US2 both independently functional.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [x] T015 [P] Documentation (FR-011): in `README.md`, add the
  `specify extension add linear --from <release-zip> --force` install/update one-liner
  pinned to the latest release tag AND a note to re-run `/speckit.linear.install` after a
  `--force` update to restore the `after_*` hooks (point the workaround and the
  self-report at the same fix).
- [x] T016 Run `shellcheck --shell=bash --severity=style src/*.sh` in ONE invocation
  (cross-file SC2120 lesson) and resolve findings, including any from the new
  `src/hookcheck.sh` and the include-guard edits.
- [x] T017 Run the full `bats tests/unit tests/integration` suite; confirm green except
  the known env-only `config.bats` "resolve_operator_user_id NEVER reads identity from
  the committed config" case (fails locally due to the dogfood `linear-operator.local.yml`,
  passes in CI — not a regression).
- [x] T018 [P] Walk through `quickstart.md` end-to-end against the fixtures to confirm the
  six acceptance steps (SC-001..SC-006) behave as documented.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (P1)**: no dependencies.
- **Foundational (P2)**: depends on Setup; BLOCKS both user stories.
- **US1 (P3)** and **US2 (P4)**: both depend on Foundational. They edit the same file
  (`src/hookcheck.sh`) and distinct entrypoints (`reconcile.sh` vs `status.sh`); US1 is
  the MVP and is sequenced first because it also authors `offer_selfheal` (reused by US2).
- **Polish (P5)**: depends on the desired stories being complete.

### Critical same-file note

`src/hookcheck.sh` is touched by T002, T005, T006 (foundational), T009, T010 (US1), and
T013 (US2). These MUST be sequential (no `[P]` among them). Tasks marked `[P]` are only
those touching different files (fixtures, the six guard edits, the bats files, README).

### Within Each Story

- Tests (T007/T008, T012) are written FIRST and must FAIL before their implementation.
- Detection (assess) before presentation (warn_once / status_line) before wiring.

### Parallel Opportunities

- T003 (guards) and T004 (unit tests) run in parallel after T002.
- T007 and T008 (US1 test authoring) run in parallel.
- T015 and T018 (docs / quickstart validation) run in parallel in Polish.

---

## Parallel Example: Foundational

```bash
# After T002 (skeleton) exists, run in parallel:
Task: "Add include-guards to src/{summary,git_helpers,graphql,config,parser,install}.sh"  # T003
Task: "Write failing tests/unit/hookcheck.bats (classify/assess/pin)"                     # T004
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational (detection green) → 3. Phase 3 US1
   (reconcile warns + self-heal) → **STOP & VALIDATE** the loud-warning flow → this is
   the shippable MVP that kills the silent-drift pain.

### Incremental Delivery

- Foundational → US1 (MVP: warning on every sync) → US2 (on-demand status line) →
  Polish (docs one-liner + lint + full suite). Each step is independently testable and
  adds value without breaking the prior one.

---

## Notes

- `[P]` = different files, no incomplete dependency.
- Detection reuses install's grammar (FR-007) and the self-heal reuses
  `install::register_after_hooks` (idempotent, preserves `enabled: false`).
- Surface-don't-enforce: nothing here blocks a reconcile or changes `status`'s exit.
- Commit after each task or logical group; stage files explicitly (never `git add -A`).
