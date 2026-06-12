# Feature Specification: Author-Based Attribution

**Feature Branch**: `010-author-attribution`

**Created**: 2026-06-11

**Status**: Draft

**Input**: User description: "Mirror spec authorship into Linear via author-based attribution — the Linear sibling of the spec-kit-jira author-attribution feature, parity-locked at the user-visible level."

## Overview

Today the bridge stamps every spec Issue (and its task-phase sub-issues) with the
**operator** as assignee — the person whose API key ran the install/reconcile
(spec 001, FR-034). The board therefore shows *who ran the sync*, never *who
authored the spec*. When a team shares one bridge install, every spec appears to
belong to one person.

This feature makes the Linear board reflect **who authored each spec**, using a
two-track approach that works even when the author is not a Linear member:

1. An account-independent **authorship label** (`author:<handle>`) is always
   stamped on the spec Issue.
2. The Linear **assignee** is set to the author *only when the author maps to a
   real Linear user*, and *only on create* — so manual reassignment in Linear's
   UI is never overwritten.

The whole behaviour is **opt-in** (default OFF): an install that does not enable
attribution behaves byte-for-byte as it does today. The feature is
**parity-locked** to the spec-kit-jira author-attribution feature at the
user-visible level (same `author:<handle>` label, same author-as-assignee-on-
create, same `Owner:`-line-then-git author resolution); the internal mechanism is
free to differ.

## Clarifications

### Session 2026-06-11

- Q: When attribution is ON and a spec's author cannot be mapped to a Linear user (unknown author, or a known author who is not a workspace member), what should the spec Issue's assignee be on create? → A: **Unassigned** (neutral mirror). The Issue is left unassigned rather than falling back to the operator; the authorship label is stamped either way. Operator-as-assignee survives only when attribution is OFF (FR-015).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Spec Issues show their real author (Priority: P1)

A team shares one bridge install. Alice authored specs 001–008; Bob authored
009–011. With attribution enabled, when the bridge reconciles, each spec Issue in
Linear carries an `author:<handle>` label identifying its true author, and — for
authors who are Linear members — is assigned to that author. The board now
reflects authorship instead of showing every spec under the operator.

**Why this priority**: This is the entire point of the feature — making the board
trustworthy as a record of who owns each spec. The label track alone delivers
value for the whole team, including non-members, so it is the MVP.

**Independent Test**: Enable attribution, reconcile a repo whose specs have two
distinct first-commit authors, and confirm each spec Issue carries the correct
`author:<handle>` label and (for the member author) the correct assignee — with
no change to any unrelated field.

**Acceptance Scenarios**:

1. **Given** attribution is enabled and a spec whose author maps to a Linear
   member, **When** the bridge creates that spec's Issue, **Then** the Issue is
   assigned to that member and carries the `author:<handle>` label.
2. **Given** attribution is enabled and a spec whose author is a known person
   with no Linear account, **When** the bridge creates that spec's Issue,
   **Then** the Issue carries the `author:<handle>` label and is not assigned to
   that person (assignee follows the unresolved-author rule).
3. **Given** attribution is enabled, **When** the bridge reconciles a repo with
   specs from two different authors, **Then** each spec Issue reflects its own
   author independently (no cross-contamination).

---

### User Story 2 - Manual reassignment and re-runs are respected (Priority: P1)

After the board is populated, a team lead manually reassigns a spec Issue in
Linear (e.g., to hand it off). On the next reconcile, that manual reassignment
survives, and re-running the bridge over an unchanged corpus produces no churn.

**Why this priority**: Idempotency and operator override are hard constitutional
invariants (Principle I drift-awareness; the existing FR-034 never-clobber rule).
A feature that re-stamped the author on every run, or fought a manual handoff,
would be unusable on a live board.

**Independent Test**: Reconcile (creating Issues), manually reassign one Issue in
Linear, reconcile again, and confirm (a) the manual assignee is unchanged and
(b) the `author:*` label is stable — exactly one author label, not duplicated.

**Acceptance Scenarios**:

1. **Given** an Issue the bridge already created and assigned to its author,
   **When** an operator manually reassigns it in Linear and the bridge
   reconciles again, **Then** the assignee is left as the operator set it
   (assignee is set on create only, never on update).
2. **Given** a spec whose author is unchanged, **When** the bridge reconciles a
   second time, **Then** the `author:<handle>` label is not duplicated and no
   write occurs for the author label (zero churn).
3. **Given** a spec whose author changed in the filesystem (e.g., an `Owner:`
   line was added), **When** the bridge reconciles, **Then** the stale
   `author:*` label is removed and the new `author:<handle>` label is set.

---

### User Story 3 - Authorship without leaking identity (Priority: P2)

An operator enables attribution but must not commit anyone's email or Linear user
ID into the repository. The bridge resolves authorship at runtime and keeps any
identity mapping in a gitignored file, so the committed tree never contains real
identifiers.

**Why this priority**: The project has a standing privacy posture (spec 004
config/identity split; the identity-leak hardening). Attribution must not
regress it. Important, but the resolution + labelling in US1 can ship first using
runtime resolution alone; the override map is an enhancement.

**Independent Test**: Enable attribution with an authors override file present,
confirm the file is gitignored and only a `.sample` with placeholder IDs is
tracked, and confirm no real email or user ID appears in any tracked file or in
any label (labels carry a handle, not an email).

**Acceptance Scenarios**:

1. **Given** attribution is enabled and no override file exists, **When** the
   bridge resolves an author who is a Linear member, **Then** it maps the author
   to a Linear user without any committed identity data.
2. **Given** an operator adds an authors override file, **When** the bridge
   reconciles, **Then** the override file is gitignored and the committed tree
   contains only a placeholder `.sample`.
3. **Given** any enabled attribution run, **When** labels are written, **Then**
   the authorship label contains a non-PII handle, never a raw email address.

---

### Edge Cases

- **Unresolved author** (no `Owner:` line and no git history for the spec dir):
  author is *unknown* → no label, no assignee, and the reconcile does not fail.
- **Known author, not a Linear member** (e.g., a contractor): label is stamped;
  assignee follows the unresolved-author rule (the pinned clarification).
- **Git email ≠ Linear email** (author uses a different address in git than in
  Linear): resolved via the optional override map; without it, the author is
  treated as a non-member for assignee purposes but is still labelled.
- **Multiple authors touched the spec dir**: the *first* author to add the spec
  dir wins (or an explicit `Owner:`/`Author:` line overrides). No multi-assignee.
- **Attribution disabled** (default): no author label, and the assignee remains
  the operator per FR-034 (today's behaviour, unchanged).
- **Author label collision with a manual label**: the bridge owns the `author:*`
  namespace; a manually added `author:*` label is reconciled to the resolved
  value (strip-and-set), consistent with `phase:*` hygiene.
- **Sub-issue scoping**: task-phase sub-issues inherit the spec author's *label*
  (when sub-issue inheritance is enabled) but never the author *assignee*.

## Requirements *(mandatory)*

### Functional Requirements

#### Author resolution

- **FR-001**: The bridge MUST resolve a single author per spec, in priority
  order: (1) an explicit `Owner:` (or `Author:`) line in the spec's `spec.md`;
  (2) the first author to add the spec directory in version-control history;
  (3) if neither resolves, the author is *unknown*.
- **FR-002**: When the author is *unknown*, the bridge MUST NOT stamp an author
  label or set an author assignee for that spec, and MUST NOT fail the reconcile
  (graceful degradation, same posture as the absent-operator case in FR-034).
- **FR-003**: The bridge MUST surface the resolved author and the source that
  produced it (owner-line vs git vs unknown) in the structured run summary, so an
  operator can see how each spec was attributed.

#### Authorship label (always, account-independent)

- **FR-004**: When attribution is enabled, the bridge MUST stamp an authorship
  label of the form `author:<handle>` on the spec-level Issue for every spec with
  a resolved (non-unknown) author.
- **FR-005**: The `<handle>` MUST be a stable, non-PII token: an explicit handle
  from the authors override file when present, otherwise a deterministic token
  derived from the author identity (e.g., the local-part of the email). A raw
  email address MUST NEVER appear in a label.
- **FR-006**: The author label MUST be applied idempotently by strip-and-set: any
  stale `author:*` label is removed and the current one set, so re-runs do not
  duplicate labels and an author change is reflected exactly once — the same
  hygiene already used for `phase:*` and `speckit-spec:NNN` labels.

#### Assignee (create-only, never clobber)

- **FR-007**: When attribution is enabled and the resolved author maps to a
  Linear user, the bridge MUST set that user as the spec Issue's assignee **on
  create only**.
- **FR-008**: The bridge MUST NOT send an assignee on Issue **update**, so a
  manual reassignment made in Linear's UI persists across reconciles (preserving
  the existing FR-034 never-clobber invariant).
- **FR-009**: When attribution is enabled and the resolved author does **not**
  map to a Linear user (unknown author, or a known non-member), the spec Issue
  MUST be left **unassigned** on create — the bridge MUST NOT fall back to the
  operator. The authorship label is unaffected. (Operator-as-assignee survives
  only when attribution is disabled, per FR-015.)

#### Author → Linear user mapping

- **FR-010**: The bridge MUST be able to map a resolved author to a Linear user
  by matching the author's email against Linear workspace members at runtime, so
  that no committed configuration is required for members whose git email matches
  their Linear email.
- **FR-011**: The bridge MUST support an **optional** authors override file that
  maps an author email to an explicit handle and/or an explicit Linear user, used
  for aliasing (git email ≠ Linear email) and for pinning a handle for
  non-members. The override file MUST be gitignored; only a placeholder `.sample`
  is committed. No real email or Linear user ID may appear in any tracked file.
- **FR-012**: An author entry that resolves to "no Linear user" (a known author
  with no account, by absence or explicit null in the override) MUST yield a
  label but no author assignee — it MUST NOT fail the reconcile.

#### Level scoping

- **FR-013**: Author attribution MUST apply at the spec → Issue level (one author
  per spec). Task-phase sub-issues MUST NOT receive an author assignee.
- **FR-014**: Sub-issue inheritance of the spec author's **label** MUST be a
  configurable toggle; the default MUST be spec-level-only (sub-issues do not
  inherit the author label by default).

#### Configuration & backward compatibility

- **FR-015**: Attribution MUST be opt-in via configuration, **disabled by
  default**. When disabled or absent, behaviour MUST be byte-for-byte identical
  to today: no author label, and the operator remains the assignee per FR-034.
- **FR-016**: Configuration MUST independently control (a) whether attribution is
  enabled, (b) whether the author assignee is set when resolvable, (c) whether
  the author label is stamped, (d) the author-resolution source order, (e) the
  optional authors override file location, and (f) whether sub-issues inherit the
  author label.

#### Invariants (constitution v2.1.0)

- **FR-017**: The feature MUST preserve idempotency, drift-awareness, and
  fail-closed writes; MUST NOT change the command surface; MUST keep
  `extension.id` as `linear`; and MUST derive authorship only from filesystem
  state (the `Owner:` line or version-control history), honouring Principle I
  (filesystem is the source of truth).

### Key Entities *(include if feature involves data)*

- **Resolved author**: the identity attributed to a spec — an email plus the
  source that produced it (owner-line, git-first-add, or unknown). Account-
  independent.
- **Author handle**: a stable, non-PII token rendered into the `author:<handle>`
  label. Derived from the override file or the author email's local-part.
- **Authors override (optional, gitignored)**: a mapping from author email to an
  explicit handle and/or Linear user, plus a value meaning "no Linear account".
  Used for aliasing and non-member handles. Committed only as a placeholder
  sample.
- **Attribution configuration block**: the opt-in settings governing enablement,
  assignee, label, resolution source order, override-file location, and sub-issue
  label inheritance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With attribution enabled, 100% of specs that have a resolvable
  author show an `author:<handle>` label matching that author on their spec
  Issue.
- **SC-002**: With attribution enabled, every spec whose author is a Linear
  member has that member as the spec Issue assignee on first creation.
- **SC-003**: A second reconcile over an unchanged corpus produces zero author-
  related writes (no label re-stamp, no assignee change) — verifiably idempotent.
- **SC-004**: A manual reassignment of a spec Issue in Linear survives every
  subsequent reconcile (0 overwrites).
- **SC-005**: With attribution disabled or absent, the run output is identical to
  the pre-feature baseline (no author labels, operator assignee unchanged).
- **SC-006**: No real email address or Linear user ID appears in any tracked
  file, and no label contains a raw email — verified by the repository's
  identity-leak / no-real-identifiers checks remaining green.
- **SC-007**: A known author with no Linear account is labelled but never errors
  the reconcile (graceful degradation), across 100% of such authors.

## Assumptions

- **Resolved (clarification 2026-06-11)**: when attribution is ON and the author
  is unresolved, the spec Issue is left **unassigned** (neutral mirror), not kept
  on the operator (FR-009).
- The author label namespace `author:*` is owned by the bridge, mirroring how
  `phase:*` and `speckit-spec:NNN` are already owned and reconciled.
- Linear workspace members are discoverable with their email at runtime, so
  member email→user mapping needs no committed configuration (this is the key
  divergence from the Jira sibling, where a static map is mandatory).
- The default author handle, absent an override entry, is the email local-part.
- Default sub-issue label inheritance is OFF (spec-level attribution only).
- The existing operator-identity store and its gitignore guarantees are reused as
  the model for the authors override file (gitignored; `.sample` committed).

## Out of Scope

- Auto-provisioning Linear accounts for non-members (operators invite people
  manually).
- Changing the Issue **creator/reporter** — inherently the API-token owner; not
  changeable without per-developer tokens.
- Multi-author attribution beyond first-add or an explicit `Owner:`/`Author:`
  override (no multi-assignee, no co-author labels).
- Bidirectional sync (Linear → filesystem authorship).
- Writing the author into the Issue **description body** (label + assignee only;
  a richer human-visible author block is a possible later feature).
- Any change to the 001 acceptance behaviour or the default artifact mapping.

## Parity Note

This feature is parity-locked to the spec-kit-jira author-attribution feature at
the **user-visible level**: the same `author:<handle>` label, the same
author-as-assignee-on-create semantics, and the same `Owner:`-line-then-git
author resolution. The **internal mechanism may differ** — Linear resolves
members dynamically at runtime, so its identity override map is *optional*,
whereas the Jira sibling's static map is *mandatory* (Jira's email search is
GDPR-restricted). This mirrors the precedent set by the ADR-mirroring sibling
(spec 008), where the user-visible shape matched across sinks while the internal
plumbing differed.
