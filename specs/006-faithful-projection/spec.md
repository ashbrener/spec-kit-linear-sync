# Feature Specification: Faithful projection

**Feature Branch**: `006-faithful-projection`

**Created**: 2026-06-07

**Status**: Draft

**Input**: User description: "Make the spec→Linear projection more faithful in two ways: (1) broaden the tasks.md phase-header parser so headers written with an em-dash, hyphen, or bare whitespace separator still produce sub-issues instead of being silently skipped (#34); and (2) inline the spec's own content (Input/Overview, and more of the body up to a sane cap) into the Linear issue description so an issue is self-contained for operators who feed a full markdown file to /speckit.specify, instead of relying only on a 'read full spec' link (#42) — without churning the description on re-runs."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Phase headers produce sub-issues regardless of separator style (Priority: P1)

An operator writes a `tasks.md` using the spec-kit canonical em-dash phase
headers (`## Phase 1 — Setup`). They reconcile and expect each phase to become a
Linear sub-issue, exactly as it would have if they had written a colon. Instead,
zero sub-issues are created because the parser only recognises the colon form.
This story makes every reasonable separator — colon, em-dash, hyphen, or bare
whitespace — yield the same sub-issues.

**Why this priority**: This is the core defect (#34). The canonical spec-kit
heading style uses an em-dash (`Phase N — <Name>`), so a faithful operator
following the project's own vocabulary gets a silently empty projection — the
single highest-impact correctness gap in the feature.

**Independent Test**: Take a `tasks.md` whose phase headers all use the em-dash
separator (`## Phase 1 — Setup`), reconcile, and confirm one sub-issue is created
per phase, with the same phase number and name that the colon form would have
produced — with no warning emitted for those (now-valid) headers.

**Acceptance Scenarios**:

1. **Given** a `tasks.md` with `## Phase 1 — Setup` (em-dash), **When** reconcile
   runs, **Then** a sub-issue is created for that phase with number `1` and name
   `Setup`.
2. **Given** a `tasks.md` with `## Phase 2 - Core` (hyphen) and
   `## Phase 3 Polish` (bare whitespace), **When** reconcile runs, **Then**
   sub-issues are created for both, named `Core` and `Polish` respectively.
3. **Given** the same `tasks.md` re-expressed with a colon (`## Phase 1: Setup`),
   **When** reconcile runs, **Then** the resulting sub-issues are identical to the
   em-dash, hyphen, and bare-whitespace forms (same number, same name).

---

### User Story 2 - A genuinely malformed phase header still warns (Priority: P2)

An operator mistypes a phase header in a way no separator rule can rescue (for
example `## Phase one: Setup`, with the number written as a word). The tool does
not silently drop it: it surfaces the same near-miss warning that ships today,
so the operator can fix the header rather than wonder where their sub-issue went.

**Why this priority**: Broadening the parser must not blunt the existing safety
net (#45's near-miss WARNING). Keeping the warning for the residue of truly
unparseable `## Phase` lines preserves the "no silent skips" guarantee that made
the broadening worth doing.

**Independent Test**: Take a `tasks.md` containing one unparseable `## Phase`
line (no extractable number), reconcile, and confirm exactly one near-miss
warning is emitted for that line and no warning is emitted for any header that
the broadened parser now accepts.

**Acceptance Scenarios**:

1. **Given** a `## Phase` line with no extractable phase number, **When**
   reconcile runs, **Then** a near-miss warning naming that line is emitted and no
   sub-issue is created for it.
2. **Given** a `tasks.md` whose every `## Phase` header is now accepted by the
   broadened parser, **When** reconcile runs, **Then** no near-miss warning is
   emitted.

---

### User Story 3 - The issue carries the spec's own content (Priority: P1)

An operator drives `/speckit.specify` with a full markdown file describing the
feature. They open the resulting Linear issue and find the spec's own content
(its Input and Overview, and more of the body when it fits) inlined in the
description, so the issue is self-contained — a reader does not have to leave
Linear and open the file to understand the work.

**Why this priority**: This is the core of #42. Today the description carries only
a short Overview excerpt plus a link, so an issue born from a rich spec file is
nearly empty of the very content the operator authored. Inlining the spec's own
content makes the projection faithful to what was specified.

**Independent Test**: Run `/speckit.specify` with a spec that has both an Input
and an Overview, reconcile, and confirm the resulting issue description contains
the spec's Input and Overview content (not merely a link), with a link to the
full spec still present.

**Acceptance Scenarios**:

1. **Given** a spec with an `Input` and an `## Overview`, **When** reconcile runs,
   **Then** the issue description inlines that Input and Overview content.
2. **Given** a spec whose body fits under the size cap, **When** reconcile runs,
   **Then** more of the spec body beyond Input/Overview is inlined, and a link to
   the full spec is still present.
3. **Given** an issue produced by this feature, **When** the description is
   inspected, **Then** it remains a read-only mirror (bridge-owned, not a place
   for operators to hand-edit content the bridge will overwrite).

---

### User Story 4 - Re-running does not churn the description (Priority: P1)

An operator reconciles the same unchanged spec twice. The second run reports no
change to the description: inlining the spec's content does not introduce
re-write churn, false drift, or a needless update on every reconcile.

**Why this priority**: Idempotency and drift-awareness are non-negotiable
guarantees of the bridge. A larger, content-rich description must not become a
source of spurious updates; otherwise the feature trades faithfulness for noise.

**Independent Test**: Reconcile an unchanged spec, reconcile it again, and
confirm the second run makes no description update (no drift, no churn); then edit
the spec's content and confirm the next reconcile does update the description.

**Acceptance Scenarios**:

1. **Given** an already-reconciled, unchanged spec, **When** reconcile runs again,
   **Then** the issue description is not updated (no churn).
2. **Given** an edit to the spec's inlined content, **When** reconcile runs,
   **Then** the description updates to reflect the new content exactly once.

---

### User Story 5 - Oversized specs truncate sanely with a link (Priority: P2)

An operator feeds in a very large spec. The description inlines content up to a
sane size cap, then truncates cleanly and points to the full spec via a link, so
the issue stays readable and within tracker limits without losing access to the
complete document.

**Why this priority**: A self-contained description must still respect tracker
description limits and readability. Sane truncation plus a link keeps the feature
robust for the largest inputs without failing the sync.

**Independent Test**: Reconcile a spec whose content exceeds the size cap, and
confirm the description is truncated at a clean boundary, carries a truncation
indication, and includes a working link to the full spec.

**Acceptance Scenarios**:

1. **Given** a spec whose content exceeds the size cap, **When** reconcile runs,
   **Then** the description is truncated at a clean boundary and includes a link
   to the full spec.
2. **Given** an oversized spec, **When** reconcile runs twice unchanged, **Then**
   the truncated description does not churn between runs (idempotent under
   truncation).

---

### Edge Cases

- **`## Phase` with no extractable number** (e.g. number written as a word, or no
  number at all): not accepted by the broadened parser; the existing near-miss
  warning fires and no sub-issue is produced (US2).
- **Empty separator already covered by the colon form**: a header that already
  uses the canonical colon (`## Phase 1: Setup`) MUST behave identically to the
  newly accepted forms — broadening adds forms, it never changes the colon
  result.
- **Phase name absent** (e.g. `## Phase 1 —` or `## Phase 1`): the phase is
  accepted with its number and an empty/whitespace-only name handled the same way
  the colon form handles a missing name today (no regression).
- **Multi-character / spaced separators** (e.g. `## Phase 1  —  Setup` with extra
  whitespace around the em-dash): leading/trailing whitespace around the
  separator and name is trimmed, yielding the same name as the tight form.
- **Spec with no `## Overview`**: the description still inlines what it can (the
  Input) and degrades gracefully, matching today's graceful "no Overview" warning
  behaviour rather than failing.
- **Spec exactly at the size cap**: treated as within the cap (no truncation at
  the boundary), with deterministic behaviour so re-runs do not flip between
  truncated and untruncated.
- **Bridge-owned region only**: inlining writes only the bridge-owned portion of
  the description; any operator/memory-fenced regions the bridge already preserves
  remain untouched, so idempotency of those regions is unaffected.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tasks.md phase-header parser MUST accept a colon (`:`), an
  em-dash (`—`), a hyphen (`-`), or whitespace as the separator between the phase
  number and the phase name, extracting the same phase number and trimmed phase
  name in every case.
- **FR-002**: For a given phase number and name, the sub-issues produced from the
  em-dash, hyphen, bare-whitespace, and colon header forms MUST be identical
  (same number, same name) — broadening the parser MUST NOT change the result of
  the existing colon form.
- **FR-003**: The broadened separator handling MUST apply consistently across all
  phase-parsing paths (phase enumeration, per-phase task collection, and any
  phase-estimate/aggregation path that depends on phase headers), so no path is
  left on the colon-only grammar.
- **FR-004**: A `## Phase` line from which no phase number can be extracted MUST
  NOT silently disappear: the existing near-miss warning MUST still be emitted for
  it.
- **FR-005**: No near-miss warning MUST be emitted for a `## Phase` header that
  the broadened parser now accepts (the warning is reserved for genuinely
  unparseable lines).
- **FR-006**: The phase name MUST be trimmed of leading/trailing whitespace (and
  of whitespace surrounding the separator), matching the trimming the colon form
  applies today.
- **FR-007**: The Linear issue description MUST inline the spec's own content —
  at minimum the spec's `Input` and `## Overview` — rather than relying only on a
  link to the full spec.
- **FR-008**: When the spec body fits within a defined size cap, the description
  MUST inline more of the spec body beyond Input/Overview (up to that cap).
- **FR-009**: The description MUST always include a link to the full spec, whether
  or not the content was truncated.
- **FR-010**: When the spec's content exceeds the size cap, the description MUST
  truncate at a clean boundary, carry an indication that it was truncated, and
  retain the link to the full spec.
- **FR-011**: Inlining the spec content MUST be idempotent: reconciling an
  unchanged spec MUST NOT update or churn the issue description.
- **FR-012**: An edit to the spec's inlined content MUST cause the next reconcile
  to update the description exactly once (drift is detected and resolved, not
  re-applied repeatedly).
- **FR-013**: Truncation MUST be deterministic, so an oversized spec reconciled
  twice unchanged does not flip between truncated and untruncated states (no churn
  under truncation).
- **FR-014**: The issue description MUST remain a read-only, bridge-owned mirror:
  inlining writes only the bridge-owned portion and does not invite hand-editing
  of content the bridge re-derives from the spec.
- **FR-015**: Inlining MUST NOT disturb any operator/memory-fenced regions the
  bridge already preserves in the description; their idempotency MUST be
  unaffected.
- **FR-016**: A spec lacking an `## Overview` MUST still produce a valid
  description (inlining what content it can) and degrade gracefully, consistent
  with today's "no Overview" handling.
- **FR-017**: All existing safety guarantees — idempotency, drift-awareness,
  fail-closed writes, and read-only-mirror semantics — MUST continue to hold
  unchanged.
- **FR-018**: The command surface (`/speckit.linear.*`) and `extension.id`
  (`linear`) MUST be unchanged; this feature alters only the faithfulness of the
  projection, not the interface.

### Key Entities *(include if feature involves data)*

- **Phase header**: a `## Phase <N> <sep> <Name>` heading in `tasks.md`, where
  `<sep>` is now any of colon, em-dash, hyphen, or whitespace; it carries the
  phase number and name that drive sub-issue creation.
- **Near-miss warning**: the existing diagnostic for a `## Phase` line that looks
  like a phase header but cannot be parsed; after broadening it fires only for
  lines with no extractable number.
- **Issue description (bridge-owned mirror)**: the spec Issue's body, fully owned
  and re-derived by the bridge, now inlining the spec's own content (Input,
  Overview, and more up to a cap) plus a link to the full spec.
- **Size cap**: the maximum inlined-content size before the description truncates
  at a clean boundary and falls back to the link.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A `tasks.md` using em-dash, hyphen, or bare-whitespace phase
  headers produces the same number of sub-issues as the colon form — 0 phases
  silently dropped for separator style.
- **SC-002**: Across colon, em-dash, hyphen, and bare-whitespace forms of the
  same headers, 100% of resulting sub-issues match in number and name.
- **SC-003**: Genuinely unparseable `## Phase` lines still raise exactly one
  near-miss warning each, and accepted headers raise 0 warnings.
- **SC-004**: An issue produced from a spec with Input and Overview contains that
  Input and Overview content inline (not merely a link) in 100% of cases.
- **SC-005**: Reconciling an unchanged spec twice produces 0 description updates
  on the second run (no churn), including for specs that are truncated.
- **SC-006**: Specs exceeding the size cap produce a description within the cap
  that is truncated at a clean boundary and retains a working link to the full
  spec.

## Assumptions

- The separator set is exactly colon, em-dash, hyphen, and whitespace; other
  exotic separators are out of scope and fall to the near-miss warning if they
  cannot be parsed for a number.
- "Phase number" remains a digit sequence; a number written as a word (e.g.
  `Phase one`) is intentionally NOT accepted and remains a near-miss (US2),
  preserving a clear, testable grammar.
- The size cap reuses the bridge's existing description/Overview cap convention
  (the exact byte/character limit is an implementation detail for the plan); the
  spec only requires that a cap exists, truncation is clean, and a link remains.
- "The spec's own content" means the spec document's authored body — primarily
  its Input and Overview, then additional body sections in document order up to
  the cap — not bridge-generated tables or memory blocks.
- Idempotency is measured against the bridge-owned portion of the description;
  operator/memory-fenced regions continue to be governed by their existing
  preservation rules and are unaffected by this feature.
- This is a projection-faithfulness change only: it bundles #34 and #42, adds no
  new tracker capability, and does not alter the spec→Issue→sub-issue mapping
  beyond making more phase headers parse and more spec content appear.
- The near-miss warning behaviour referenced here is the one already shipped via
  #45; this feature narrows when it fires (only truly unparseable lines), it does
  not introduce a new warning mechanism.
