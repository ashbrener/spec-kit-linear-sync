# Implementation Plan: Lifecycle Cascade to Task-Phase Sub-Issues

**Branch**: `013-subissue-cascade` | **Date**: 2026-06-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-subissue-cascade/spec.md`

## Summary

Two coupled fixes so the Linear board stops misrepresenting merged work:

- **P1 — lifecycle cascade (the core fix).** Thread the spec's inferred
  `lifecycle_phase` into `reconcile::sync_task_phase_subissues` (it currently isn't
  passed) and, when the phase is **terminal** (`ready_to_merge` or `merged`),
  force every task-phase sub-issue's workflow state to **Done** — overriding the
  `tasks.md` checkbox-ratio key — on both the create and update state paths.
  Non-terminal specs keep today's checkbox-ratio behaviour exactly. Deterministic
  and zero-churn. Heals Mode 1 (numeric phases stuck Todo) on the next reconcile.

- **P2 — broaden the phase-header grammar.** Let a phase index be a **digit-run
  OR a single letter** (`## Phase A — …`), separator-gated exactly like the
  numeric rule so `## Phase one` / `## Phase 1Setup` / `## Phase AB` still fail
  (near-miss preserved). `split_phase_header` sets `out["idx"]` to an **ordinal**
  (digits as-is; `A→1 … Z→26`) — the **single** phase identifier already used for
  the `task-phase:<ordinal>` label, inter-phase blocking order, `tasks_in_phase`
  match, AND the sub-issue title (`Phase <ordinal> — …`). **No new output field,
  no `task_phases` contract change, no reconcile read-loop change** — a letter
  phase simply renders `Phase 1 — …`. Fixes Mode 2 (letter specs → zero
  sub-issues). (Clarified 2026-06-22: ordinal-only; the title normalizes A→1.)

Amends spec-001 FR-005 (sub-issue state) and FR-013 (merged handling); the
parent's `phase:*` clearing on merge is retained. Additive — no constitution
amendment.

## Technical Context

**Language/Version**: Bash (CI matrix: bash 4.4 + 5.2; ubuntu authoritative;
`LC_ALL=C awk` for the phase-header grammar — em-dash byte-safety already in place).

**Primary Dependencies**: `jq`, `curl` — **no new runtime deps**. Reuses
`parser::lifecycle_phase` (already authoritative for the parent), the
`PARSER_PHASE_HEADER_AWK` prologue, `config::get_default_state_uuid` (the existing
`done` key), and the existing sub-issue create/update flow.

**Storage**: none — reads `tasks.md` + inferred lifecycle from the filesystem;
writes only Linear sub-issue `stateId`. No config/schema change.

**Testing**: `bats` (unit, offline); `shellcheck --shell=bash --severity=style`
(all `src` in one invocation — the SC2120 lesson); `yamllint`; `markdownlint-cli2`.
Integration gated by `RUN_INTEGRATION_TESTS=0`.

**Target Platform**: macOS + Linux (CI: ubuntu-latest + macos-latest).

**Project Type**: single-project CLI / reconcile sync engine.

**Performance Goals**: correctness-bound; zero-churn idempotent re-runs (SC-002).

**Constraints**: idempotency, drift-awareness, fail-closed writes hold; cascade is
deterministic (terminal→done) and filesystem-derived (lifecycle inference,
Principle I); the sub-issue **description** (tasks.md mirror) is unchanged — only
state cascades (FR-006); the broadened grammar must NOT swallow real malformations
(FR-009); `task-phase:<ordinal>` label scheme + blocking order stay numeric/stable
(back-compat); `extension.id` stays `linear`; command surface unchanged.

**Scale/Scope**: a handful of phases per spec; a few dozen specs per repo.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution **v2.1.0**. All eight principles hold; this feature is **additive**
and needs **no amendment**. It does not change the data-model mapping (a task
phase still → a sub-issue); it changes how a sub-issue's **state** is computed
(lifecycle-aware) and **broadens** the phase-header grammar (a strict superset of
today's numeric grammar).

| Principle | Verdict | Why |
|---|---|---|
| I Filesystem is the source of truth | PASS | The cascade derives from `parser::lifecycle_phase` (PR/merge + artifact ladder — filesystem-evident); a terminal spec's sub-issues read Done because the **filesystem** says the spec shipped. The sub-issue **description** stays the read-only `tasks.md` mirror; only state reflects lifecycle truth. No Linear→fs flow. |
| II Reconcile, never event-push | PASS | State recomputed from full filesystem state each run; `terminal→done` is deterministic ⇒ second run is zero-churn (SC-002). Phase identity (ordinal) is filesystem-derived, not a sidecar. |
| III Layered idempotency (D + E) | PASS | A Layer-D concern (sub-issue state on reconcile). **Layer E is untouched** — it flips only the parent spec Issue's workflow state; it never touched sub-issues and still won't. |
| IV Write-authority follows the filesystem (drift-aware) | PASS | Runs inside the existing per-spec reconcile; no new drift surface, no new gate. |
| V UUID-based binding, per-repo config | PASS | Reuses `default_state_uuids.done`; no new binding. The `task-phase:<ordinal>` label stays numeric/UUID-resolved as today. |
| VI OAuth-first, keys-at-the-edges | PASS | No new credential surface; reuses the existing sub-issue mutation. |
| VII Memory-just-works | PASS | Additive on the existing `after_*` reconcile; no new command, no hook change. |
| VIII Surface, don't enforce — observable failure | PASS | Broadening accepts a real index style and keeps the near-miss diagnostic for genuine malformations (FR-009); canonical vocabulary (`task-phase:N`, `Phase N — <Name>`). A merged letter-spec no longer silently shows zero phases. |
| Architectural Constraints (data-model; layers; no backend) | PASS | The frozen mapping (task phase → sub-issue) is unchanged. Grammar broadening is a superset; state-source change is opt-out-free but behaviour-preserving off the terminal path. No backend/daemon/db. |

**Post-design re-check (after Phase 1)**: re-evaluated **PASS**. `data-model.md`
and `contracts/` keep all logic on the parser (`split_phase_header` ordinal/display
+ broadened, separator-gated grammar) and reconcile (`lifecycle_phase` threading +
terminal-state override) layers, with no config/schema/mapping change, no Layer-E
change, no new command. The only Linear field newly driven is the sub-issue
`stateId` on terminal specs (and sub-issues now exist for letter specs). No new
violations.

## Project Structure

### Documentation (this feature)

```text
specs/013-subissue-cascade/
├── plan.md          # this file
├── research.md      # Phase 0 — cascade trigger, terminal override, grammar broadening, ordinal/display split
├── data-model.md    # Phase 1 — lifecycle phase, sub-issue state source, phase index/ordinal/display
├── quickstart.md    # Phase 1 — what heals + how (merged board → Done; letter specs → phases)
├── contracts/       # Phase 1 — cascade contract + broadened phase-header grammar contract
│   ├── cascade.md
│   └── phase-header-grammar.md
├── checklists/requirements.md
└── tasks.md         # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
├── parser.sh        # ~ PARSER_PHASE_HEADER_AWK / split_phase_header: accept a
│                    #   digit-run OR a SINGLE letter as the index, separator-gated
│                    #   (so `## Phase one`/`1Setup`/`AB` still fail → near-miss).
│                    #   Set out["idx"] = ordinal (digits as-is; A→1…Z→26).
│                    #   out["name"] unchanged. NO new output field.
│                    # ~ parser::task_phases / tasks_in_phase / phase_estimate:
│                    #   UNCHANGED — still `<idx>\t<name>`, still match on idx
│                    #   (the ordinal now numeric for letter phases too).
├── reconcile.sh     # ~ sync_task_phase_subissues: add 4th arg `lifecycle_phase`;
│                    #   per-phase state key = (terminal? "done" : subissue_state_key
│                    #   …) applied on the CREATE state site AND the UPDATE state
│                    #   diff. Read loop, sub_title (`Phase <idx> — <name>`),
│                    #   task-phase label + blocking are UNCHANGED (all use the
│                    #   ordinal idx — a letter phase renders `Phase 1 — …`).
│                    # ~ process_spec call site: pass "$lifecycle_phase" (in scope).
│                    #   subissue_state_key itself is UNCHANGED (non-terminal path).
└── (config.sh, graphql.sh, summary.sh, install.sh)  # UNCHANGED

tests/
├── unit/            # split_phase_header (digit / single-letter A→1 / reject
│                    #   `one`,`1Setup`,`AB`; ordinal in idx); task_phases still
│                    #   2-field (numeric assertions unchanged); tasks_in_phase
│                    #   matches a letter phase by ordinal; cascade state key
│                    #   (terminal→done; non-terminal→ratio, applied create+update);
│                    #   idempotency (terminal→done twice).
└── integration/     # (gated) merged numeric spec → all sub-issues Done; merged
                     #   letter spec → one sub-issue per phase, all Done; re-run zero-churn.
```

**Structure Decision**: A single-project **additive** bug-fix. P1 (cascade) is a
small, low-risk change isolated to `sync_task_phase_subissues` + its one call site
+ `subissue_state_key` left intact. P2 (grammar) is contained to the shared
`split_phase_header` prologue (so `task_phases`, `tasks_in_phase`, `phase_estimate`,
and the near-miss diagnostic all move together via `out["idx"]`) — with **no
`task_phases` output-contract change** and **no reconcile read-loop change** (the
sub-issue title, label, and blocking already use the ordinal `idx`, so a letter
phase renders `Phase 1 — …` for free). No config, schema, mapping, command, or
Layer-E change.

## Complexity Tracking

> No constitution violations — this section is intentionally empty.
