# Phase 0 Research: Lifecycle Cascade to Task-Phase Sub-Issues

**Feature**: `013-subissue-cascade`

**Date**: 2026-06-22

Phase 0 decisions for (P1) cascading a spec's terminal lifecycle to its
task-phase sub-issues and (P2) broadening the phase-header grammar to non-numeric
indices. Two clarifications resolved 2026-06-22 (terminal set; broaden vs
numeric-canonical) are encoded in D1 and D3.

**Unresolved NEEDS CLARIFICATION**: none.

---

## D1 — Cascade trigger: terminal phases `{ready_to_merge, merged}` → children Done

- **Decision**: When a spec's inferred `lifecycle_phase` ∈ {`ready_to_merge`,
  `merged`}, force every task-phase sub-issue's workflow state to `done`,
  overriding the `tasks.md` checkbox-ratio key. All other phases keep the
  checkbox-ratio key unchanged.
- **Rationale**: A merge PR isn't opened mid-implementation, so `ready_to_merge`
  (PR open/ready) effectively means the phases shipped — the board should heal the
  moment the PR is ready, not only post-merge (clarified). `merged` is
  unambiguous. The lifecycle is already authoritative for the **parent** (FR-013
  flips it to Merged + clears `phase:*`); this makes it authoritative for the
  **children** too, closing the exact gap that strands merged work in Todo.
- **Alternatives considered**: `merged` only (rejected by clarification — leaves a
  ready-to-merge board briefly dishonest); cascade on any phase ≥ implementing
  (rejected — implementing phases legitimately have incomplete work; the checkbox
  ratio is the right signal there).

---

## D2 — Thread `lifecycle_phase` into the sub-issue projector; override at both state sites

- **Decision**: Add a 4th arg `lifecycle_phase` to
  `reconcile::sync_task_phase_subissues` (`process_spec` already has it in scope at
  the call site). In the per-phase loop compute the state key as: terminal →
  `done`; else → `reconcile::subissue_state_key "$tasks_md" "$ordinal"` (today's
  behaviour). Apply this key on **both** the create-time `stateId` and the
  update-time state diff. `subissue_state_key` itself is unchanged.
- **Rationale**: The merge state is currently structurally invisible to the
  projector (signature is `<spec_issue_id> <feature_number> <spec_dir>`). Threading
  the already-computed phase is the minimal, low-risk change; overriding the key
  (not `subissue_state_key`) keeps the non-terminal path byte-identical and the
  override localized. `done` is an existing `default_state_uuids` key — no config
  change. Deterministic ⇒ zero-churn second run (SC-002).
- **Alternatives considered**: change `subissue_state_key` to take the phase
  (rejected — couples a pure checkbox helper to lifecycle; muddier and broader
  blast radius); a separate post-pass that closes children of merged specs
  (rejected — a second Linear round-trip + ordering complexity; the inline
  override heals on the normal reconcile).

---

## D3 — Broaden the grammar: digit-run OR single letter, separator-gated

- **Decision**: `split_phase_header` accepts a phase index that is either a
  **digit run** (`[0-9]+`, today) **or a single letter** (`[A-Za-z]`). The
  existing post-index gate is retained: the index must be followed by a separator
  (`:`, em-dash, hyphen), whitespace, or end-of-line — otherwise it is NOT a
  header. This keeps `## Phase one` (→ `o` then non-separator `n`), `## Phase
  1Setup`, and `## Phase AB` (→ `A` then non-separator `B`) all **rejected**, so
  the near-miss diagnostic still fires for them (FR-009 / SC-005).
- **Rationale**: A *single letter* is the observed real convention (specs 004–007
  used `## Phase A — …`), while a letter **run** would wrongly swallow English
  words like `one`/`two` — the exact malformations the near-miss must still catch.
  Single-letter + separator-gate is the tightest broadening that admits `A/B/C…`
  without regressing the diagnostic.
- **Alternatives considered**: `[A-Za-z0-9]+` (rejected — parses `## Phase one`,
  violating acceptance #3); roman numerals / arbitrary tokens (rejected — scope
  creep, ambiguous ordinal); keep numeric-canonical + loud error (rejected by
  clarification — letter specs would stay phase-less until renumbered).

---

## D4 — Ordinal is the single phase identifier (no display token)

- **Decision** (clarified 2026-06-22, refined post-analyze): `split_phase_header`
  sets a single value `out["idx"]` = the **ordinal** (numeric): a digit index used
  as-is; a single letter mapped by case-insensitive alphabet position
  (`A/a→1 … Z/z→26`). The ordinal is used for **everything** — the
  `task-phase:<ordinal>` label, inter-phase blocking order, `tasks_in_phase`
  match, AND the sub-issue title (`Phase <ordinal> — <name>`). There is **no
  separate display token** and **no change to the `parser::task_phases` output
  contract** (still `<idx>\t<name>`); the reconcile read loop is unchanged. A
  letter phase therefore renders `Phase 1 — Overlay`.
- **Rationale**: A separate `display` token (to render the author's literal
  `Phase A`) would force `task_phases` from 2→3 fields — a public output-contract
  change that **breaks 5 assertions in the CI unit test `tests/unit/parser.bats`**
  (`[ "${lines[0]}" = $'1\tSetup' ]`) — for a minor fidelity gain on a
  non-canonical letter convention. Analyze surfaced this; the clarification chose
  the simpler ordinal-only path: no contract churn, no CI-test edits, smaller
  diff, and a clean consistent numeric phase display across all specs.
  Alphabet-position (not document order) keeps a letter's ordinal stable under
  reordering and matches the clarified `A→1`.
- **Alternatives considered**: 3-field `task_phases` with a `display` token for a
  faithful `Phase A` title (rejected — breaks the `task_phases` contract + 5
  CI-unit-test assertions; the fidelity gain is marginal and only affects
  non-canonical letter specs); document-order ordinal (rejected — reorder-
  sensitive; alphabet-position is stable and matches `A→1`); generalize the label
  to `task-phase:<token>` (rejected — breaks back-compat with numeric labels and
  the seeded `task-phase:1..9` set).

**Back-compat invariant**: for a numeric phase, `idx ==` the authored
number, so every numeric spec's labels, titles, blocking, and matching are
**byte-identical** to today. The only new behaviour is for letter indices.

---

## D5 — Sub-issue description (tasks.md mirror) is unchanged; only state cascades

- **Decision**: The cascade drives only the sub-issue workflow **state**. The
  sub-issue **description** remains the read-only `tasks.md` checklist mirror
  (FR-006), so a Done sub-issue of a merged spec may still show literally un-ticked
  `- [ ]` boxes in its body. This is intended and documented.
- **Rationale**: State reflects the spec's lifecycle truth (merged = shipped);
  the body faithfully mirrors `tasks.md` (Principle I — the markdown is canonical;
  editing the body to fake ticks would violate the read-only-mirror contract).
  The two answer different questions ("is this shipped?" vs "what did the plan
  say?") and are both honest.
- **Alternatives considered**: also tick the boxes in the mirrored body on merge
  (rejected — would imply the bridge edits task content; Linear body is a mirror,
  not a control surface; the disk `tasks.md` is unchanged so the mirror must match
  it).

---

## D6 — Idempotency & back-compat

- **Decision**: Terminal→`done` is a pure function of the inferred phase, so a
  merged spec resolves identically every run (zero-churn after the one-time heal,
  SC-002). Numeric specs are byte-identical (D4 invariant). The first reconcile
  after upgrade heals a stranded board (one state write per stranded sub-issue),
  then stays churn-free.
- **Rationale**: Matches the project's idempotency contract and the 012 migration
  pattern (one-time heal, then stable). No new config/flag — heals on the normal
  reconcile path.
- **Alternatives considered**: a `--close-merged` one-shot (deferred — out of
  scope; the normal reconcile already heals).

---

## D7 — Testing strategy

- **Decision**: Unit-first, offline. `split_phase_header`: digit; single-letter
  `A→1`/`b→2`; reject `one`/`1Setup`/`AB`/`Phase:`; `out["idx"]` is the ordinal.
  `task_phases` output **unchanged** (2-field `<idx>\t<name>`; numeric assertions
  in `tests/unit/parser.bats` stay valid); `tasks_in_phase` matches a letter
  phase by ordinal. Cascade state-key: terminal (`ready_to_merge`,`merged`)→`done`;
  non-terminal→ratio; applied on create + update; idempotent (twice → same).
  Sub-issue title renders `Phase <ordinal> — <name>`. Gated integration: merged
  numeric spec → all Done; merged letter spec → one sub-issue per phase, all Done;
  re-run zero-churn.
- **Rationale**: All behaviour is deterministic pure-string / state-key logic,
  unit-checkable offline — the proven pattern; keeps CI hermetic.
- **Alternatives considered**: integration-only (rejected — slow, needs a live
  workspace, gated off in CI).

---

## D8 — Cross-sink parity

- **Decision**: Document that the spec-kit-jira sibling has the same sub-issue
  model and almost certainly the same gap (child/sub-task state decoupled from the
  parent's merged state). Mirror the cascade there for parity — a merged parent
  drives its children Done in both sinks — as a follow-up.
- **Rationale**: Same precedent as specs 008/010/012 — keep the user-visible
  behaviour aligned across sinks.
- **Alternatives considered**: fix only Linear (acceptable now; the parity
  follow-up keeps the sinks from diverging).
