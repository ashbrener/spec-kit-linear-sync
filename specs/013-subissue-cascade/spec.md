# Feature Specification: Lifecycle Cascade to Task-Phase Sub-Issues

**Feature Branch**: `013-subissue-cascade`

**Created**: 2026-06-22

**Status**: Draft

**Input**: User description: "Merged specs show their task-phase sub-issues stranded in Todo (the board lies about completion). Sub-issue state is derived solely from the tasks.md checkbox ratio, with no coupling to the spec's merged/terminal lifecycle. Separately, letter-indexed phase headers (`## Phase A — …`) parse to zero sub-issues. Fix the board so a merged spec's phases read Done, and so every phase is represented regardless of how it's indexed."

## Overview

The bridge sets each task-phase **sub-issue's** Linear workflow state **only** from
its `tasks.md` checkbox completion ratio — with no link to the spec's inferred
**lifecycle phase**. So when a spec is merged, the parent spec Issue correctly
flips to **Merged** (and drops its `phase:*` label), but the **child** sub-issues
stay in whatever their (usually un-ticked) checkboxes imply — i.e. **Todo**. The
board then shows shipped, merged work as outstanding, which directly defeats the
bridge's promise that "Linear is the always-up-to-date view."

Two distinct on-board failure modes were observed on a real repo where all specs
are merged:

- **Mode 1 — numeric phases, sub-issues stuck in Todo** (specs that index phases
  `## Phase 1:`, `## Phase 2:`…): sub-issues exist but read Todo because the
  operator merged without hand-ticking every `- [ ]`.
- **Mode 2 — letter phases, zero sub-issues** (specs that index phases
  `## Phase A — …`): the phase-header parser requires a numeric index, so these
  produce **no sub-issues at all**, only a near-miss warning.

This feature makes the spec's **lifecycle inference the source of truth for the
children** (a merged spec's phases read Done, no checkbox hygiene required) and —
behind a pinned clarification — broadens the phase-header grammar so a spec never
silently shows zero phases. It amends FR-005 (sub-issue state) and FR-013 (merged
handling), preserving idempotency, drift-awareness, and fail-closed writes.

## Clarifications

### Session 2026-06-22

- Q: Which lifecycle phases force all child sub-issues to Done — only `merged`, or also `ready_to_merge`? → A: **Both** — `{ready_to_merge, merged}` are terminal and cascade every sub-issue to Done. (A merge PR isn't opened mid-implementation, so ready-to-merge effectively means the phases shipped; the board heals the moment the PR is ready.)
- Q: How should the letter-indexed phase parser fix be scoped (Mode 2)? → A: **Broaden the parser** to accept a non-numeric phase index (`## Phase A —`), deriving a **deterministic ordinal** (A→1, B→2…) used for the `task-phase:<ordinal>` identity label and the inter-phase blocking order. The identity label **stays `task-phase:<ordinal>`** (numeric) for back-compat. Genuine malformations (`## Phase one`, `## Phase:`, `## Phase 1Setup`) still raise the near-miss diagnostic.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A merged spec's phases read Done (Priority: P1)

A developer has merged a spec's PR to the default branch without hand-ticking
every checkbox in `tasks.md` (the normal case). On the next reconcile, the parent
spec Issue is Merged **and every one of its task-phase sub-issues reads Done** —
the board honestly shows the work as shipped, with no manual checkbox hygiene.

**Why this priority**: This is the core defect — the board misrepresents merged
work as outstanding, defeating the bridge's headline value. Fixing it restores
trust and is the must-have; it heals Mode 1 entirely on the next normal reconcile.

**Independent Test**: Merge a spec without ticking boxes, reconcile, and confirm
zero of its child sub-issues are in Todo/In-Progress — all Done — while the parent
is Merged.

**Acceptance Scenarios**:

1. **Given** a spec whose inferred lifecycle is `merged` and whose `tasks.md` has
   un-ticked boxes, **When** the bridge reconciles, **Then** every task-phase
   sub-issue's workflow state is Done (not Todo/In-Progress).
2. **Given** the same merged spec, **When** the bridge reconciles a second time,
   **Then** no sub-issue state write occurs (idempotent, zero-churn).
3. **Given** a spec still in a non-terminal phase (specifying…implementing),
   **When** the bridge reconciles, **Then** each sub-issue's state is the
   checkbox ratio exactly as today (no behaviour change off the terminal path).

---

### User Story 2 - Every phase is represented, however it's indexed (Priority: P2)

A spec indexes its phases with letters (`## Phase A — …`) rather than numbers.
On reconcile, the spec still gets one sub-issue per phase (or, if letter indices
are deemed unsupported, a loud error rather than a silent empty board) — a merged
spec never silently shows **zero** phases.

**Why this priority**: This is the second failure mode (specs 004–007 on the
reporting repo). It's real and on-board, but secondary to US1 — and the resolution
has a genuine design fork (broaden vs keep-numeric-canonical) pinned in clarify.

**Independent Test**: Reconcile a spec with `## Phase A —`/`## Phase B —` headers
and confirm the resolved behaviour from the clarification (one sub-issue per
letter phase, or a loud actionable error), never a silent zero-phase board.

**Acceptance Scenarios**:

1. **Given** a spec with `## Phase A — …` / `## Phase B — …` headers, **When** the
   bridge reconciles, **Then** the resolved policy applies: either one sub-issue
   per phase (broaden) **or** a loud, actionable error naming the unsupported
   index (keep-numeric) — never a silent empty phase section.
2. **Given** a genuinely unparseable header (`## Phase one`, `## Phase: x`,
   `## Phase 1Setup`), **When** the bridge reconciles, **Then** the near-miss
   diagnostic still fires (the broadening, if chosen, does not swallow real
   malformations).

---

### Edge Cases

- **Merged spec, zero checked boxes**: children → Done (US1) — the headline case.
- **Merged spec, letter phases**: children must be represented per US2's resolved
  policy (so a merged letter-indexed spec isn't both zero-phase *and* mis-stated).
- **Sub-issue checklist body vs state**: a Done sub-issue still mirrors the literal
  (possibly un-ticked) `tasks.md` checklist in its description — state reflects
  lifecycle truth, body remains the read-only `tasks.md` mirror (FR-006). This is
  intended and must be documented, not "fixed" by editing the body.
- **Non-terminal phase**: sub-issue state stays the checkbox ratio (no change).
- **Re-run after upgrade**: a previously-stranded merged board heals on the next
  normal reconcile (no special command required); the heal is a one-time state
  write per stranded sub-issue, then zero-churn.
- **Manual sub-issue state edit in Linear**: overwritten by the cascade on the next
  reconcile for a terminal spec (Principle I; the bridge owns sub-issue state).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When a spec's inferred lifecycle phase is **terminal** —
  `ready_to_merge` or `merged` — the bridge MUST set **every** task-phase
  sub-issue's workflow state to **Done**, overriding the `tasks.md` checkbox-ratio
  state.
- **FR-002**: When a spec's lifecycle phase is **non-terminal**, each sub-issue's
  workflow state MUST be derived from the `tasks.md` checkbox ratio exactly as
  today (no behaviour change off the terminal path).
- **FR-003**: The cascade MUST be deterministic and idempotent — a terminal spec
  resolves every sub-issue to Done on every run, so a second reconcile over
  unchanged state produces zero sub-issue state writes (zero-churn).
- **FR-004**: The spec's lifecycle phase MUST be available to the sub-issue
  projection (it is currently not passed in); the projection MUST consume it
  without otherwise changing the create/update sub-issue flow.
- **FR-005**: A merged spec MUST NOT require any manual `tasks.md` checkbox edits
  to make its board honest — lifecycle inference alone drives the children.
- **FR-006**: The sub-issue **description** (the read-only `tasks.md` checklist
  mirror) MUST remain unchanged by this feature; only the sub-issue workflow
  **state** is driven by the cascade. (State = lifecycle truth; body = mirror.)
- **FR-007**: The phase-header grammar MUST accept a **non-numeric phase index**
  (e.g. `## Phase A — …`, `## Phase B — …`) in addition to numeric indices,
  keeping the separator broadening from #34 (`:`, em-dash, hyphen, whitespace), so
  a spec MUST NOT silently produce **zero** task-phase sub-issues when its
  `tasks.md` contains valid phase-like headers — one sub-issue per phase is created
  regardless of index style.
- **FR-008**: For a non-numeric index the bridge MUST derive a **deterministic
  ordinal** (single letter → alphabet position, A→1, B→2…) that becomes the phase's
  **single identifier** — used for the `task-phase:<ordinal>` label, the
  inter-phase blocking order, the sub-issue title (`Phase <ordinal> — <name>`,
  e.g. `Phase 1 — Overlay`), and the in-phase task match. The phase-enumeration
  output contract is **unchanged** (no new field), so numeric specs and every
  existing consumer/test stay byte-identical; only letter indices gain a numeric
  ordinal. (Clarified 2026-06-22: ordinal-only — the title normalizes `A`→`1`; no
  separate display token.)
- **FR-009**: The genuine-malformation near-miss diagnostic MUST continue to fire
  for headers that are not valid phase headers (e.g. `## Phase one`, `## Phase:`,
  `## Phase 1Setup`); any broadening MUST NOT swallow real malformations.
- **FR-010**: The feature MUST preserve idempotency, drift-awareness, and
  fail-closed writes; MUST keep `extension.id` as `linear`; MUST NOT change the
  command surface; and MUST keep lifecycle inference filesystem-derived
  (Principle I). It amends FR-005/FR-013 of spec 001 (sub-issue state + merged
  handling) — the parent's `phase:*` clearing on merge is retained.

### Key Entities *(include if feature involves data)*

- **Lifecycle phase (per spec)**: the inferred phase (specifying…merged) already
  computed by the reconciler; the new source of truth for child state on terminal
  phases.
- **Task-phase sub-issue**: the per-phase child Issue; gains a lifecycle-aware
  workflow state (Done on terminal) in addition to its existing checkbox-ratio
  state and `tasks.md`-mirror description.
- **Phase index/ordinal**: the per-phase identifier driving the `task-phase:*`
  label and blocking order; today strictly numeric, possibly broadened to a
  letter token with a derived ordinal (per clarification).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After merging a spec **without** ticking any `tasks.md` checkbox and
  reconciling, **0%** of that spec's child sub-issues are in Todo/In-Progress —
  100% are Done.
- **SC-002**: A second reconcile over a fully merged repo writes **zero** sub-issue
  state changes (idempotent / SC-002 of spec 001 preserved).
- **SC-003**: A non-terminal spec's sub-issue states are byte-for-byte identical to
  pre-feature behaviour (checkbox ratio) — no regression off the terminal path.
- **SC-004**: **0** specs with phase-like headers produce a silent zero-sub-issue
  board: every such spec yields either one sub-issue per phase or a loud error.
- **SC-005**: Genuinely malformed phase headers still raise the near-miss warning
  (no loss of the existing diagnostic).

## Assumptions

- **Resolved terminal set** (clarification 2026-06-22): cascade on both
  `ready_to_merge` and `merged`.
- **Resolved parser policy** (clarification 2026-06-22): broaden to accept a
  single-letter index with a derived alphabet-position ordinal (A→1, B→2…),
  keeping the #34 separator broadening. The ordinal is the **single** phase
  identifier (label, blocking, title, match) — **no separate display token, no
  phase-enumeration contract change** (the sub-issue title for a letter phase
  normalizes to `Phase <ordinal>`, e.g. `Phase 1 — Overlay`).
- Lifecycle inference (`parser::lifecycle_phase`, incl. PR-merge detection) is
  already correct and authoritative for the parent; this feature reuses it for the
  children — it does not change how the phase is inferred.
- The parent spec Issue's existing merged handling (workflow state + `phase:*`
  clearing, FR-013) is correct and unchanged; the gap is only the children.

## Out of Scope

- Changing how the lifecycle phase itself is **inferred** (PR/merge detection,
  artifact ladder) — reused as-is.
- Editing the sub-issue **description**/checklist body (remains the read-only
  `tasks.md` mirror; only state is cascaded).
- The parent spec Issue's merged handling (already correct).
- A bidirectional flow (Linear sub-issue edits → filesystem).
- A standalone retroactive sweep command — the next normal reconcile already heals
  the board; a `--close-merged`-style one-shot is a possible later ergonomic, not
  this feature.

## Parity Note

The sibling spec-kit-jira bridge has the same sub-issue model and very likely the
same gap (sub-task/child state decoupled from the epic/parent merged state). This
feature should be mirrored there for cross-sink parity — a merged parent drives
its children Done in both sinks — as a follow-up.
