# Feature Specification: Human-Readable Issue Titles

**Feature Branch**: `012-readable-titles`

**Created**: 2026-06-17

**Status**: Draft

**Input**: User description: "The Linear Issue title should be a human-readable name (e.g. `006 — Faithful projection`), not the directory slug `006-faithful-projection`. The readable name already lives in each spec's `# Feature Specification: <NAME>` H1, which the bridge currently ignores."

## Overview

Today the bridge titles each spec's Linear Issue with the spec **directory slug**
— `${feature_number}-${short_name}`, e.g. `001-fixtures`, `006-faithful-projection`.
In a Linear list or board that reads like a filename, not a feature. Meanwhile
every `spec.md` already carries a human name in its first line
(`# Feature Specification: <NAME>` — e.g. `# Feature Specification: Faithful
projection`) that the bridge throws away.

This feature makes the Issue title the **human-readable name, prefixed with the
spec number** for traceability — e.g. `006 — Faithful projection`. The number
keeps the Issue tied to its spec directory and `speckit-spec:NNN` label; Linear
shows its own `AML-5`-style identifier separately.

The readable title is derived **deterministically from filesystem content** — the
bridge mirrors what an author already wrote, it never summarizes with a model.
Summarization is an authoring-time concern (the spec's H1 is written when the
spec is authored); the bridge stays a deterministic, idempotent reconciler that
also runs headless in CI. The feature is **parity-locked** to the spec-kit-jira
sibling at the user-visible level (same `<NNN> — <human title>` shape, same
resolution order).

## Clarifications

### Session 2026-06-17

- Q: Title source — H1 feature name only, or H1 then a first-sentence-of-Input fallback? → A: **H1 → Input → slug.** Use the H1 `# Feature Specification: <NAME>`; when it is missing or the unfilled `[FEATURE NAME]` placeholder, fall back to the first sentence of the `**Input**:` line (via `_extract_input`) (clean-boundary truncated, length-capped); last resort the `<NNN>-<slug>`. (Richer for specs whose H1 is weak; every spec gets a readable title.)
- Q: Default-on or gated behind a config toggle? → A: **Default-on, no toggle.** Readable titles apply to every install — the bridge already owns the title field, so this is just a better computed value. Existing Issues re-title once on the next reconcile (slug → readable), then stay zero-churn. No config surface, no opt-out.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The board reads like features, not filenames (Priority: P1)

A stakeholder opens the team's Linear board. Each spec Issue shows a readable
title — `006 — Faithful projection`, `010 — Author-Based Attribution` — instead
of `006-faithful-projection`. They can scan the board and understand what each
spec is without opening it.

**Why this priority**: This is the entire point — a board titled with directory
slugs is the user-visible defect being fixed. It delivers value for every spec
immediately and retroactively (the readable name already exists in each spec).

**Independent Test**: Reconcile a repo whose specs have human H1 names; confirm
each spec Issue's title is `<NNN> — <H1 name>` and no longer the slug.

**Acceptance Scenarios**:

1. **Given** a spec whose `spec.md` H1 is `# Feature Specification: Faithful
   projection`, **When** the bridge reconciles it, **Then** the Issue title is
   `006 — Faithful projection`.
2. **Given** a repo of specs each with a distinct H1 name, **When** the bridge
   reconciles, **Then** each Issue title carries its own spec's number + name (no
   cross-contamination, no slug).
3. **Given** the Issue already exists with the old slug title, **When** the
   bridge reconciles after upgrade, **Then** the title updates once to the
   readable form.

---

### User Story 2 - Re-runs are stable; no title churn (Priority: P1)

After the board is populated, repeated reconciles (hooks firing, manual pushes,
CI) leave the titles untouched — the title is computed deterministically from the
unchanged spec, so it matches every time and never rewrites.

**Why this priority**: Idempotency is a hard constitutional invariant (Principle
II/III). A title that re-derived non-deterministically — or pulled from a model —
would churn on every reconcile, defeating zero-churn and breaking the headless CI
path. This story is what forces the deterministic-only design.

**Independent Test**: Reconcile twice over an unchanged spec; assert the second
run issues no title write (zero churn) and the title byte-matches the first.

**Acceptance Scenarios**:

1. **Given** a spec already titled `006 — Faithful projection`, **When** the
   bridge reconciles again with the spec unchanged, **Then** no title update is
   sent (zero churn).
2. **Given** the spec's H1 changes on disk, **When** the bridge reconciles,
   **Then** the title updates exactly once to reflect the new H1.
3. **Given** a reconcile from the headless CI path (no model available), **When**
   it runs, **Then** it produces the identical title to the interactive path.

---

### User Story 3 - Every spec gets a stable title, even imperfect ones (Priority: P2)

A spec whose H1 is still the unfilled `[FEATURE NAME]` placeholder (or missing)
must still get a sensible, stable title rather than a broken or empty one.

**Why this priority**: Graceful degradation (Principle VIII). Not every spec is
perfectly authored; the bridge must never produce an empty or placeholder title.
Important, but secondary to the main readable-title win in US1.

**Independent Test**: Reconcile a spec with an unfilled/missing H1; confirm the
title falls back deterministically (to the Input-derived name or the slug per the
resolved policy) and is never empty or `[FEATURE NAME]`.

**Acceptance Scenarios**:

1. **Given** a spec whose H1 is `# Feature Specification: [FEATURE NAME]`, **When**
   the bridge reconciles, **Then** the title does NOT contain `[FEATURE NAME]` and
   falls back per the resolved title-source policy.
2. **Given** a spec with no parseable H1 and no Input, **When** the bridge
   reconciles, **Then** the title is the `<NNN>-<slug>` (today's value) — stable,
   never empty.

---

### Edge Cases

- **Unfilled H1 placeholder** (`[FEATURE NAME]`): treated as absent → fall back.
- **Very long H1 / Input sentence**: the title is capped at a sane length with
  clean-boundary truncation so it stays one scannable line (never a paragraph).
- **H1 with trailing punctuation / markdown**: trimmed to a clean name.
- **Operator manually renamed the Issue in Linear**: overwritten on next
  reconcile — the title is a bridge-owned field today and remains so (Principle
  I); this feature changes only the computed value, not the ownership.
- **Spec number already implied by Linear's own id** (`AML-5`): the bridge still
  prefixes `<NNN>` because Linear's id is workspace-assigned and not the spec
  number; the `<NNN>` ties the Issue to `specs/NNN-…` and `speckit-spec:NNN`.
- **First reconcile after upgrade**: each existing Issue re-titles once
  (slug → readable), then stays zero-churn — a one-time intended migration.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The spec Issue title MUST be `<NNN> — <human title>`, where `<NNN>`
  is the spec's feature number and `<human title>` is derived deterministically
  from the spec's filesystem content (resolution order per the pinned
  clarification).
- **FR-002**: The bridge MUST parse the spec's `# Feature Specification: <NAME>`
  H1 and use `<NAME>` (trimmed) as the human title, treating an unfilled
  `[FEATURE NAME]` placeholder (or a missing H1) as absent.
- **FR-003**: When the H1 does not resolve (missing or `[FEATURE NAME]`
  placeholder), the bridge MUST fall back to the first sentence of the spec's
  `## Input` block (clean-boundary truncated, length-capped); when that too is
  absent, it MUST fall back to today's `<NNN>-<short_name>` slug. The resolution
  order is **H1 → Input-first-sentence → slug**, always yielding a non-empty,
  stable title.
- **FR-004**: The composed title MUST be capped at a sane maximum length using
  clean-boundary (word-boundary) truncation, so it remains a single scannable
  line; it MUST NOT reproduce the full Input/Overview paragraph.
- **FR-005**: Title derivation MUST be deterministic — the same spec content MUST
  produce the same title on every reconcile, with no dependence on a model or any
  non-filesystem input (so hook-fired, manual, and headless-CI reconciles produce
  identical titles).
- **FR-006**: An unchanged spec MUST produce no title write on a subsequent
  reconcile (zero churn); a changed H1 (or fallback source) MUST update the title
  exactly once.
- **FR-007**: The title MUST never be empty and MUST never contain the literal
  `[FEATURE NAME]` placeholder.
- **FR-008**: Readable titles MUST apply to every install with **no config
  toggle and no opt-out** (default-on). The title is a bridge-owned computed
  field; on the first reconcile after upgrade each existing Issue re-titles
  exactly once (slug → readable), and every reconcile thereafter is zero-churn.
- **FR-009**: The feature MUST NOT change the Issue description, sub-issue
  (task-phase) titles, the `speckit-spec:NNN` identity label, or any
  matching/identity key; it changes only the spec Issue's title field.
- **FR-010**: The feature MUST preserve idempotency, drift-awareness, and
  fail-closed writes; MUST keep `extension.id` as `linear`; MUST NOT change the
  command surface; and MUST derive the title only from filesystem state
  (Principle I).

### Key Entities *(include if feature involves data)*

- **Human title**: the readable name rendered into the Issue title. Derived from
  the spec.md H1 feature name, or (per policy) the first sentence of the Input,
  trimmed and length-capped. Account-independent, deterministic.
- **Spec Issue title**: the composed `<NNN> — <human title>` string — a
  bridge-owned, reconciled field of the spec Issue.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of specs with a filled H1 produce an Issue title of the form
  `<NNN> — <H1 name>` (no directory slug).
- **SC-002**: A second reconcile over an unchanged spec produces zero title
  writes (verifiably idempotent).
- **SC-003**: The headless/CI reconcile path produces a title byte-identical to
  the interactive path for the same spec (no model dependence).
- **SC-004**: 0% of produced titles are empty or contain `[FEATURE NAME]`, across
  specs with unfilled or missing H1s.
- **SC-005**: 100% of produced titles are a single line within the length cap
  (no paragraph-length titles).
- **SC-006**: On first reconcile after upgrade, each previously-synced Issue
  re-titles exactly once; every reconcile thereafter is zero-churn on the title.

## Assumptions

- **Resolved title-source policy** (clarification 2026-06-17): H1 name → first
  sentence of Input (clean-boundary truncated, length-capped) → slug.
- **Resolved rollout** (clarification 2026-06-17): default-on, no toggle — the
  bridge already owns the title field; the one-time re-title on upgrade is
  intended.
- Length cap reuses the bridge's existing clean-boundary truncation used for
  inlined descriptions; a title cap on the order of ~70–80 characters keeps it
  scannable.
- The `<NNN>` prefix uses an em-dash separator (`<NNN> — <name>`) consistent with
  the `Phase N — <Name>` sub-issue convention already in the bridge.
- The spec.md H1 is the canonical human name; spec-kit already emits it for every
  spec, so no authoring change is required for the common case.

## Out of Scope

- LLM/model summarization of the title at sync time (deterministic-from-
  filesystem only — the idempotency + headless-CI constraint).
- Changing the Issue **description** (the inlined Input/Overview body is
  unchanged; only the title field changes).
- Sub-issue (task-phase) titles — `Phase N — <Name>` is already human-readable.
- Changing the `speckit-spec:NNN` identity label or any match/identity key.
- Bidirectional sync (Linear title edits flowing back to the filesystem).
- Authoring-side changes to how `/speckit-specify` writes the H1 (the bridge
  mirrors whatever name is on disk; improving H1 authoring is a separate concern).

## Parity Note

Parity-locked to the spec-kit-jira author-attribution/ADR precedent at the
**user-visible level**: the same `<NNN> — <human title>` shape and the same
H1-then-Input resolution order, so a board reads the same across both sinks. The
internal plumbing may differ. The spec-kit-jira sibling carries the identical
slug-title behaviour and SHOULD adopt the same readable-title resolution for
cross-sink parity (follow-up).
