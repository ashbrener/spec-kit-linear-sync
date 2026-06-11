# Feature Specification: ADR / Decision-Record Mirroring

**Feature Branch**: `008-adr-mirroring`

**Created**: 2026-06-11

**Status**: Draft

**Input**: User description: "Mirror ADRs (architecture/decision records) from spec-kit specs into Linear, as the Linear sibling of the spec-kit-jira ADR-mirroring feature — parity-locked at the user-visible level. Today the bridge mirrors a spec's `## Clarifications` sessions as at-most-once comments on the spec's Linear Issue; it does NOT capture the formal ADRs in each spec's `research.md` (the Decision / Rationale / Alternatives blocks). Option A: mirror each ADR as one idempotent comment on the spec's Linear Issue, reusing the clarify-comment machinery. Keep the user-visible shape identical to the Jira sibling for cross-sink parity. Out of scope: Linear Documents as a richer doc-home (Option B); a docs/adr/ corpus as an alternate source; bidirectional sync."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Decisions show up on the spec's Linear Issue (Priority: P1)

A reviewer (PM, lead, or teammate) opens a spec's Linear Issue and can read the
key decisions that shaped the work — what was decided, why, and what was
rejected — without opening `research.md` in the repo. Today those decisions live
only in the filesystem; this surfaces them where the work is tracked.

**Why this priority**: This is the whole point of the feature — the decisions a
team most wants visible (the "why we did it this way") are exactly the ones that
never reach the tracker today. The clarify-session comments already prove the
pattern is valued; ADRs are the richer, more deliberate decisions. Shipping just
this slice — ADRs from `research.md` rendered as comments on the spec Issue — is
already a complete, valuable release.

**Independent Test**: Reconcile a spec whose `research.md` contains two ADR
blocks (Decision / Rationale / Alternatives) and confirm the spec's Linear Issue
gains exactly two ADR comments carrying the decision, rationale, alternatives,
and a back-reference to the source.

**Acceptance Scenarios**:

1. **Given** a spec whose `research.md` records two decisions as
   `Decision / Rationale / Alternatives` blocks, **When** the operator
   reconciles, **Then** the spec's Linear Issue gains exactly two comments, one
   per decision, each showing the decision id, title, status, decision,
   rationale, and alternatives, plus the source location.
2. **Given** a spec that has no `research.md` (or a `research.md` with no
   decision blocks), **When** the operator reconciles, **Then** no ADR comments
   are posted and the run completes normally (the absence is not an error).
3. **Given** a spec already mirrored with its clarify-session comments, **When**
   ADR mirroring runs, **Then** the ADR comments are added alongside the clarify
   comments without disturbing them.

---

### User Story 2 - Re-running never duplicates or churns (Priority: P1)

An operator (or an auto-firing hook) reconciles repeatedly as work proceeds. Each
ADR appears once and only once; an unchanged corpus produces no new comments and
no edits; a decision that was revised updates its single existing comment in
place rather than posting a second one.

**Why this priority**: Idempotency is constitutional and inseparable from US1 —
a feature that posts decisions but duplicates them on every sync is worse than
not having it. The clarify-comment path already guarantees at-most-once; ADRs
must inherit the identical guarantee.

**Independent Test**: Reconcile the same spec twice with no filesystem change and
confirm the second run posts zero comments and edits none; then change one ADR's
text on disk, reconcile, and confirm exactly one comment is updated and no new
comment is created.

**Acceptance Scenarios**:

1. **Given** a spec whose ADRs are already mirrored, **When** the operator
   reconciles again with no disk change, **Then** zero ADR comments are created
   and zero are edited (zero churn).
2. **Given** a mirrored spec, **When** one ADR's decision or rationale text
   changes on disk and the operator reconciles, **Then** exactly that ADR's
   existing comment is updated in place and no duplicate comment is created.
3. **Given** a mirrored spec, **When** a new ADR is added to `research.md` and
   the operator reconciles, **Then** exactly one new comment is created for it
   and the existing ADR comments are untouched.

---

### User Story 3 - Consistent with the Jira sibling (Priority: P2)

A team running both the Linear and Jira bridges (or a person reading one after
the other) sees ADRs presented the same way in both trackers — the same source,
the same per-decision-comment placement, and the same ADR layout — so knowledge
transfers between the two without relearning.

**Why this priority**: Cross-sink parity is an established project value (the
configurable-mapping feature was a faithful port for exactly this reason). It is
secondary to having the capability at all, but it is what keeps the two sinks a
coherent family rather than two divergent tools.

**Independent Test**: Compare the ADR comment a Linear spec Issue receives with
the ADR comment the equivalent Jira spec issue receives for the same
`research.md` and confirm the user-visible shape (fields, ordering, source
back-reference, one-comment-per-decision placement) matches.

**Acceptance Scenarios**:

1. **Given** the same `research.md` mirrored by both bridges, **When** an
   operator inspects the resulting comments, **Then** the decision fields shown
   (id, title, status, decision, rationale, alternatives, source) and their
   one-per-comment placement match between Linear and Jira.

### Edge Cases

- A `research.md` decision block is missing a sub-part (e.g. no explicit
  "Alternatives") — the comment still renders the parts that exist and omits the
  missing one, rather than failing.
- A decision block has no explicit status — a sensible default status is shown
  (see Assumptions) rather than leaving it blank or failing.
- An operator manually edits or deletes an ADR comment in Linear — the next
  reconcile re-asserts it from disk (the filesystem is the source of truth);
  manual edits are not a control surface.
- The spec's Linear Issue does not yet exist (first reconcile) — ADR mirroring
  runs after the spec Issue is created, in the same reconcile, so the comments
  land on the freshly-created Issue.
- Two decisions share a title but differ in id — each is mirrored as its own
  comment, distinguished by id, with no collision.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST read each spec's architecture/decision records from
  that spec's `research.md` — specifically its structured
  `Decision / Rationale / Alternatives` blocks — and treat each block as one ADR.
- **FR-002**: For each ADR, the system MUST mirror it as a single comment on that
  spec's Linear Issue, rendered in an ADR layout that includes the decision id,
  title, status, decision, rationale, alternatives, and a back-reference to the
  source location in the repo.
- **FR-003**: Each ADR comment MUST carry a stable, hidden idempotency marker
  derived from the spec and decision identity (a spec/decision key) so that
  re-runs locate the existing comment rather than posting a new one.
- **FR-004**: A reconcile against an unchanged corpus MUST create zero ADR
  comments and edit zero ADR comments (idempotent, zero-churn — the same
  at-most-once guarantee the clarify-session comments provide).
- **FR-005**: When an ADR's content changes on disk, the system MUST update that
  ADR's single existing comment in place; it MUST NOT create a second comment for
  the same decision.
- **FR-006**: When a new ADR is added on disk, the system MUST create exactly one
  new comment for it and leave existing ADR comments unchanged.
- **FR-007**: A spec with no `research.md`, or whose `research.md` contains no
  decision blocks, MUST be handled gracefully — no ADR comments, no error, the
  reconcile completes normally (Principle VIII: surface, don't fail).
- **FR-008**: ADR mirroring MUST NOT disturb the existing clarify-session
  comments or any other mirrored artifact; the two comment streams coexist on the
  same spec Issue.
- **FR-009**: The user-visible shape of the ADR mirror — the source
  (`research.md` decision blocks), the target (one comment per decision on the
  spec Issue), and the ADR layout (fields + ordering + source back-reference) —
  MUST match the spec-kit-jira ADR-mirroring feature, so the two sinks stay
  consistent for anyone reading both.
- **FR-010**: All existing safety guarantees MUST continue to hold: idempotency,
  drift-awareness, and fail-closed writes; ADRs are non-task artifacts and map to
  spec-Issue comments, consistent with the constitutional data-model.
- **FR-011**: `extension.id` MUST remain `linear` and the command surface
  (`/speckit.linear.*`) MUST be unchanged — this is an additive capability on the
  existing reconcile path, not a new command.
- **FR-012**: No real Linear coordinates, identifiers, names, or tokens may
  appear in any tracked file; real values live only in the gitignored credential
  and binding files.

### Key Entities *(include if feature involves data)*

- **ADR (decision record)**: one decision extracted from a spec's `research.md`
  decision block — its id, title, status, decision text, rationale, alternatives,
  and source location. The unit this feature mirrors.
- **Spec Issue**: the existing Linear Issue that mirrors a spec (per the 001
  data-model). The target the ADR comments attach to.
- **ADR comment + identity marker**: the mirrored comment on the spec Issue,
  carrying a stable hidden marker (spec + decision identity) that makes the
  mirror idempotent and at-most-once.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the `Decision / Rationale / Alternatives` blocks in a
  spec's `research.md` appear as ADR comments on that spec's Linear Issue —
  exactly one comment per decision, no decision missed, no duplicate.
- **SC-002**: A reconcile against an unchanged corpus produces zero ADR-comment
  writes (zero created, zero edited) — observable as no new comment timestamps.
- **SC-003**: Changing one ADR on disk and reconciling results in exactly one
  ADR comment updated and zero new ADR comments created.
- **SC-004**: A spec with no `research.md` decisions causes zero ADR comments and
  zero errors (graceful no-op).
- **SC-005**: For the same `research.md`, the ADR comment's user-visible shape
  (fields, ordering, source back-reference, one-per-decision placement) matches
  between the Linear and Jira bridges (a parity check passes).

## Assumptions

The following working defaults make the spec complete with no unresolved
clarification markers. The first is the one genuine fork the operator asked to
pin during `/speckit-clarify`.

- **ADR source = `research.md` (the clarify candidate).** The default and
  recommended source is each spec's `research.md` `Decision / Rationale /
  Alternatives` blocks — the structured ADRs spec-kit already produces. The open
  question to confirm in `/speckit-clarify` is whether to ALSO support a
  `docs/adr/NNNN-*.md` convention as an alternate/additional source. This spec
  assumes **`research.md` only** unless clarify decides to broaden it.
- **Decision id + title.** The ADR id and title are derived from the
  `research.md` decision-block heading (an `R5` / `D1`-style key and its title);
  when a block has no explicit id, a stable id is derived from its
  position/heading so the idempotency marker is deterministic.
- **Status default.** When a decision block states no explicit status, the
  comment shows a sensible default status (e.g. "Accepted") rather than blank.
- **Placement.** ADR comments attach to the same spec Issue the 001 bridge
  already creates/updates; this feature adds a comment stream, it does not create
  new Linear entities.
- **Reuse of existing machinery.** This is a near-clone of the existing
  clarify-session comment path (parse → render → at-most-once comment keyed by a
  hidden marker). The Linear bridge has no workstate floor (it reads
  `spec.md`/`research.md` directly), so — unlike the Jira sibling — no
  schema/workstate change is required; only the user-visible shape must match.
- **Dependencies.** Builds on the shipped 001 core bridge (spec Issue
  create/update + the comment + idempotency-marker machinery), the drift-aware
  write-authority model (003), and the gitignored credential/binding files.
- **Out of scope** (deliberate): Linear **Documents** as a richer doc-home for
  prose ADRs (the "Option B" / Confluence equivalent) — a later feature; a
  `docs/adr/` corpus as a source unless clarify adopts it; bidirectional sync;
  any change to the default mapping or to the 001 acceptance behaviour.
