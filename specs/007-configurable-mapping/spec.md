# Feature Specification: Configurable Artifact Mapping

**Feature Branch**: `007-configurable-mapping`

**Created**: 2026-06-08

**Status**: Draft

**Input**: User description: "Make the spec-kit→Linear artifact mapping operator-configurable instead of the hardcoded repo→Project / spec→Issue / phase→sub-issue / task→checklist default, while keeping today's behaviour as the frozen zero-config default. This resolves design issue #17 (should a spec become a Project or an Issue?) by making the mapping a configurable choice rather than a one-off decision. Port the spec-kit-jira configurable-mapping model (its `specs/002-configurable-mapping`) to Linear so the two sinks share the same workstate→sink grammar: the four ordinal workstate levels (repo→spec→phase→task), each level mapping to an artifact + a relationship_to_parent; an optional off-by-default narrative super-level above the repo; an optional + additive `mapping:` block with an alias layer that synthesizes today's default when absent; an offline relationship-validation matrix that rejects nonsensical hierarchy links (fail-closed); and all mapping/validation logic living in the source-agnostic config layer. Idempotency, drift-awareness, fail-closed reads, and `extension.id=linear` must hold in every mode."

## Clarifications

### Session 2026-06-08

- Q: When a configured Linear artifact cannot be created in the target workspace (e.g. the narrative super-level wants a Milestone but Project Milestones are unavailable on the plan/team), what happens? → A: For required levels (repo/spec/phase/task) the artifact set is fixed Linear primitives (Project, Issue, sub-issue, checklist) so absence is impossible; the only optional artifact is the L0 Milestone, which degrades gracefully (folds onto the repo level behind a stable marker + grouping label) rather than hard-failing — mirroring Jira's `on_absent: degrade`.
- Q: Which relationships may be used as a hierarchy (parent→child) link in Linear? → A: Only `parent` (native sub-issue nesting), `none` (top level), and `checklist` (renders into the parent body); `blocks` and `relates` are rejected as hierarchy links — all rejections hard-halt at config-load (fail-closed, Principle VIII).
- Q: How does an absent `mapping:` block stay byte-for-byte back-compatible? → A: An alias layer synthesizes today's default (repo→Project, spec→Issue, phase→sub-issue, task→checklist, L0 off) from the existing `linear-config.yml` binding keys, with no file rewrite and no version bump; a pre-feature config loads unchanged.
- Q: How does this relate to the Jira sink? → A: It is a faithful port of `spec-kit-jira`'s `specs/002-configurable-mapping` — same four-level grammar, same optional/additive alias layer, same offline relationship matrix shape, same fail-closed validation gate — with Linear primitives substituted for Jira issue types (see the cross-reference parity table in Assumptions).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A no-config upgrade changes nothing (Priority: P1)

An operator who already mirrors a repo into Linear upgrades to the version with
configurable mapping and changes no configuration. Their next reconcile produces
exactly the same Project / Issue / sub-issue / checklist result as before — no new
Projects or Issues, no rewritten fields, no surprises.

**Why this priority**: This is the safety promise and the regression anchor for
the whole feature. The flexibility is worthless if it silently changes existing
workspaces. Shipping just this slice — the alias layer that synthesizes today's
default mapping when no `mapping:` block is present — is already a viable,
valuable release: "upgrade safely, opt in later." It is also what lets #17 be
resolved as a *configurable choice* without disturbing the installed default.

**Independent Test**: Run a reconcile with an existing pre-feature
`linear-config.yml` (no `mapping:` block) and confirm the created/updated/skipped
result is byte-identical to the prior version's, including a zero-churn re-run.

**Acceptance Scenarios**:

1. **Given** a `linear-config.yml` with no `mapping:` block, **When** the operator
   reconciles, **Then** the bridge mirrors repo→Project, spec→Issue,
   phase→sub-issue, and tasks→an in-body checklist exactly as the shipped default
   does, with the same labels and workflow-state behaviour.
2. **Given** that same corpus already mirrored, **When** the operator reconciles
   again, **Then** zero writes occur (no duplicate Projects or Issues, no
   rewritten fields).
3. **Given** an explicit `mapping:` block that spells out today's default, **When**
   the operator reconciles, **Then** the result is identical to the no-block case.

---

### User Story 2 - Configure the mapping to resolve #17, safely (Priority: P1)

An operator chooses, per spec-kit level, which Linear artifact the level becomes
and how it links to its parent. In particular they can resolve design issue #17
by promoting a spec to a **Project** (spec→Project, phase→Issue, task→sub-issue)
instead of the default spec→Issue — selectable through the same `mapping:` grammar
the Jira sink uses. Before anything is written, the bridge validates the chosen
relationships against an offline matrix and refuses to start if a relationship is
nonsensical as a hierarchy link — so a corrupt Linear graph is rejected at
configuration time instead of being written.

**Why this priority**: This is the core value and the direct resolution of #17 —
the flexibility that lets one repo treat a spec as a Project (heavier, with its
own milestones and issue list) and another treat it as a single Issue, with no
code change. The relationship validation is inseparable from it: without it, a
configured `blocks`-as-nesting link would silently produce a mis-shaped Linear
hierarchy.

**Independent Test**: Configure the #17 alternative (spec→Project, phase→Issue,
task→sub-issue) and confirm the mirror uses those artifacts with the configured
parent relationships; then configure a nonsensical hierarchy relationship and
confirm the run is rejected before any write.

**Acceptance Scenarios**:

1. **Given** a `mapping:` block of spec→Project, phase→Issue, task→sub-issue,
   **When** the operator reconciles, **Then** the bridge creates a Project per
   spec, an Issue per task phase, and a sub-issue per task, with the configured
   parent relationships, and #17's spec-as-Project shape is realised.
2. **Given** a `mapping:` block with a relationship that is nonsensical as a
   hierarchy link (e.g. `blocks` used to nest a child under its parent), **When**
   the operator reconciles, **Then** validation rejects it at config-load with a
   clear error and writes nothing.
3. **Given** a `mapping:` block that pairs a `checklist` artifact with any
   relationship other than `checklist`, **When** the operator reconciles, **Then**
   validation rejects it before any write.

---

### User Story 3 - Partial mapping inherits the default per level (Priority: P2)

An operator who wants to override only one level (say, promote spec→Project) sets
just that level in the `mapping:` block and leaves the others unspecified. The
unspecified levels inherit the synthesized default rather than forcing the
operator to restate the whole hierarchy or hitting an all-or-nothing error.

**Why this priority**: Per-level inheritance is what makes the grammar ergonomic
and keeps the #17 toggle a one-line change. It is secondary to having a correct,
validated mapping at all, but it is the difference between a usable config and a
verbose one, and it preserves the back-compat promise for partially-specified
blocks.

**Independent Test**: Configure a `mapping:` block specifying only `spec` and
confirm the unspecified `repo`, `phase`, and `task` levels mirror exactly as the
synthesized default would, with a zero-churn re-run.

**Acceptance Scenarios**:

1. **Given** a `mapping:` block specifying only the `spec` level, **When** the
   operator reconciles, **Then** the unspecified levels inherit the synthesized
   default (repo→Project, phase→sub-issue, task→checklist) and only the `spec`
   level reflects the override.
2. **Given** a partial `mapping:` block, **When** the operator reconciles again
   with no disk changes, **Then** zero writes occur.

---

### User Story 4 - Optional narrative super-level above the repo (Priority: P3)

An operator turns on an optional narrative level above the repo — the human "what
are we building" requirement (the §16 / L0 super-level) — which maps to a Linear
**Milestone** (Linear's free, narrative-shaped primitive) where the team supports
Project Milestones, and otherwise folds onto the repo level behind a stable marker
with a grouping label rather than failing.

**Why this priority**: A differentiating capability for teams that track a
narrative above the per-repo Project, but it is off by default, narrative-only,
and depends on workspace capability — so it is the lowest-priority slice, exactly
as the Initiative super-level is in the Jira sink.

**Independent Test**: With the super-level on, run against a team that supports
Milestones and confirm a Milestone is created above the repo level with its
narrative populated only from the explicit source; run against one that does not
and confirm the narrative folds behind a stable marker with a grouping label and
no hard failure.

**Acceptance Scenarios**:

1. **Given** the super-level on and Milestones available, **When** the operator
   reconciles, **Then** a Milestone is created above the repo level and its
   narrative is populated only from the explicit source (the spec's input
   description), never inferred.
2. **Given** the super-level on and Milestones unavailable, **When** the operator
   reconciles, **Then** the narrative folds onto the repo level behind a stable
   marker, repo grouping becomes a label, and the run succeeds (no hard failure).
3. **Given** the super-level off (the default), **When** the operator reconciles,
   **Then** no narrative level is created and behaviour matches User Story 1.

### Edge Cases

- A `mapping:` block specifies only some levels — unspecified levels fall back to
  the synthesized default (per-level inheritance), not an all-or-nothing error.
- The target team supports Project Milestones at first but the operator later
  loses that capability (or vice versa) — degradation/upgrade must re-home the
  narrative without churn.
- A configured relationship is valid in isolation but invalid for the level
  boundary it is placed on (e.g. `parent` declared on the top `repo` level, which
  has no parent) — rejected at validation.
- A level whose `artifact: "checklist"` is paired with a relationship other than
  `checklist` — rejected at validation (the checklist sentinel is non-issue and
  must render into its parent's body).
- The drift anchor: even with the super-level on, the spec-level work unit remains
  the backward-drift anchor; the narrative level is not a new drift surface.
- A pre-feature `linear-config.yml` with no `mapping:` block — loads unchanged and
  projects byte-identically (no file rewrite, no version bump).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST keep today's shipped mapping (repo→Project,
  spec→Issue, phase→sub-issue, task→in-body checklist, lifecycle phase→workflow
  state) as the default behaviour when no `mapping:` configuration is present.
- **FR-002**: The system MUST synthesize that default mapping from the existing
  `linear-config.yml` binding keys via an alias layer, so configurations written
  before this feature keep working unchanged with no file rewrite and no version
  bump.
- **FR-003**: The system MUST let an operator configure, per spec-kit level
  (repo, spec, phase, task), which Linear artifact the level projects to
  (`Project`, `Issue`, `sub-issue`, or the `checklist` sentinel) and the
  relationship that links it to its parent level.
- **FR-004**: The system MUST support, as an opt-in alternative to the default,
  the #17 spec-as-Project shape (spec→Project, phase→Issue, task→sub-issue),
  selectable entirely through the `mapping:` grammar with no code change.
- **FR-005**: The system MUST treat a `mapping:` block that specifies only some
  levels as valid, with each unspecified level inheriting the synthesized default
  (per-level inheritance), not an all-or-nothing error.
- **FR-006**: The system MUST validate configured relationships against a matrix
  of allowed (level-boundary × relationship-type) combinations and reject these
  semantically nonsensical combinations before any write: dependency-style links
  (`blocks`, `relates`) used as hierarchy links; a `parent` relationship on a
  level that has no parent (the top level); and a `checklist` artifact paired with
  any relationship other than `checklist`.
- **FR-007**: All relationship-matrix validation MUST be offline (require no
  Linear call) and run at config-load before any write; any failure is a
  workspace-level configuration error that writes nothing for the run (fail-closed,
  Principle VIII).
- **FR-008**: The system MUST preserve idempotency in every mapping mode: a re-run
  against unchanged state performs zero observable writes, including where a level
  projects to an in-body checklist (the rendered checklist MUST re-render
  byte-identically, keyed by each item's workstate task identity so unrelated body
  edits do not trigger a rewrite).
- **FR-009**: Each created artifact MUST carry a stable, filesystem-derived
  identity (via labels) so re-runs match and update rather than re-create —
  including a defined identity key for a level that projects to a standalone Issue
  or a Project under the #17 alternative.
- **FR-010**: The system MUST preserve backward-drift detection on the spec-level
  work unit in every mode; an enabled narrative super-level MUST NOT become a new
  drift surface.
- **FR-011**: The system MUST offer an optional, off-by-default narrative
  super-level (L0) above the repo that projects to a Linear **Milestone** where
  Project Milestones are available and degrades gracefully (fold the narrative onto
  the repo level behind a stable marker and carry repo grouping as a label) where
  they are not — never hard-failing because the team lacks Milestone support.
- **FR-012**: The narrative for the super-level MUST be populated only from an
  explicit source (the spec's input description) — never inferred or fabricated.
- **FR-013**: All configuration validation (relationship matrix, required-id
  presence for any configured artifact that projects to an Issue or Project) MUST
  run before any write; any failure is a workspace-level error that writes nothing.
- **FR-014**: The mapping, alias-layer, and validation behaviour MUST live entirely
  in the source-agnostic configuration layer (the shared workstate→sink grammar);
  the vendor-neutral reconcile engine MUST remain free of Linear-specific mapping
  knowledge, exactly as the equivalent logic lives in `config.sh` in the Jira sink.
- **FR-015**: The `mapping:` grammar (level names, `artifact` /
  `relationship_to_parent` field shape, the optional super-level block, the
  optional/additive alias semantics, and the relationship-matrix shape) MUST match
  the spec-kit-jira `mapping:` grammar so the two sinks stay consistent and a
  reader of one config understands the other.
- **FR-016**: `extension.id` MUST remain `linear` and the command surface
  (`/speckit.linear.*`) MUST be unchanged.
- **FR-017**: All existing safety guarantees — idempotency, drift-awareness, and
  fail-closed writes — MUST continue to hold unchanged in every mapping mode.
- **FR-018**: No real Linear coordinates, identifiers, names, or tokens may appear
  in any tracked file; real values live only in the gitignored credential and
  binding files.

### Key Entities *(include if feature involves data)*

- **Mapping configuration** (`mapping:` block in `linear-config.yml`, optional and
  additive): describes, per spec-kit level, the Linear `artifact` and the
  `relationship_to_parent`, plus the optional narrative super-level (its on/off
  state, degrade policy, and narrative source). Absent ⇒ the alias layer
  synthesizes today's default. Mirrors the Jira `mapping:` block shape.
- **workstate level**: the four neutral, ordinal structural units the mapping
  consumes — repo → spec → phase → task — independent of any spec-kit on-disk
  concept; the shared grammar both sinks project from.
- **Linear artifact vocabulary**: the artifacts a level may project to — `Project`,
  `Issue`, `sub-issue`, and the non-issue `checklist` sentinel — plus the optional
  L0 `Milestone` super-level artifact.
- **Relationship-validation matrix**: the offline allow/reject table of
  (level-boundary × relationship-type) combinations that guards against corrupt
  Linear graphs. Allowed hierarchy links: `parent`, `none`, `checklist`. Rejected:
  `blocks`, `relates` (dependency links, not nesting).
- **Narrative source**: the explicit origin of the L0 super-level narrative (the
  spec's input description); never an inference.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A no-config upgrade produces zero behavioural change — 100% of the
  existing default-mapping acceptance scenarios still pass, and a re-run is zero
  churn.
- **SC-002**: An operator can switch a repo from spec→Issue to the #17
  spec→Project shape (spec→Project, phase→Issue, task→sub-issue) entirely through
  the `mapping:` block, with no code change.
- **SC-003**: 100% of `mapping:` blocks containing a nonsensical hierarchy
  relationship (dependency link as nesting, `parent` on the top level, or
  `checklist` artifact with a non-`checklist` relationship) are rejected at
  config-load before any Project, Issue, or sub-issue is created or modified (no
  partial mirrors).
- **SC-004**: Every non-default mode (the #17 spec→Project shape, a partial
  mapping, and the narrative super-level) re-runs against unchanged state with
  zero observable writes.
- **SC-005**: A `mapping:` block that specifies only some levels mirrors
  identically to one that spells out the full block with the same overrides
  (per-level inheritance equivalence).
- **SC-006**: A team lacking Project Milestone support never causes a hard failure
  when the narrative super-level is on — the narrative always lands (folded onto
  the repo level) and the run succeeds.
- **SC-007**: The Linear `mapping:` grammar is structurally equivalent to the
  spec-kit-jira `mapping:` grammar — a level-by-level parity check (level names,
  field shape, alias semantics, relationship-matrix shape) passes — so the two
  sinks stay consistent.

## Assumptions

The following working defaults are taken so the spec is complete with **zero
[NEEDS CLARIFICATION] markers**; they port the resolved decisions from the
spec-kit-jira `specs/002-configurable-mapping` spec and adapt them to Linear
primitives.

- **Port parity (cross-reference)**: This spec is a faithful port of the
  spec-kit-jira `specs/002-configurable-mapping` model. The level grammar
  (repo→spec→phase→task, each with `artifact` + `relationship_to_parent`), the
  optional/additive `mapping:` block with an alias-synthesized default, the offline
  relationship-validation matrix, the off-by-default narrative super-level, and the
  fail-closed config-load gate are all carried over unchanged in shape. The
  level-by-level artifact parity table is:

  | workstate level | Jira default | Linear default | Linear #17 alternative |
  |-----------------|--------------|----------------|------------------------|
  | L0 (narrative)  | Initiative (off) | Milestone (off) | Milestone (off) |
  | repo            | Epic         | Project        | Project        |
  | spec            | Story        | Issue          | **Project**    |
  | phase           | Subtask      | sub-issue      | **Issue**      |
  | task            | checklist    | checklist      | **sub-issue**  |

  The relationship vocabulary maps Jira's `parent`/`Epic-link`/`none`/`checklist`
  hierarchy links to Linear's `parent`/`none`/`checklist` (Linear has a single
  native nesting primitive — the sub-issue `parent` — so there is no `Epic-link`
  analogue), and Jira's rejected dependency links `Blocks`/`Relates`/`Implements`
  map to Linear's rejected `blocks`/`relates`.

- **Relationship matrix**: Hierarchy links are restricted to `parent` (native
  sub-issue nesting), `none` (top level), and `checklist` (renders into the parent
  body); `blocks` and `relates` are rejected as hierarchy links; all rejections
  hard-halt at config-load. Linear's blocking/relating links remain available for
  inter-task-phase ordering as today (FR-001), separate from the hierarchy.

- **Narrative super-level (§16 / L0)**: Off by default, narrative-only, `source:
  spec_input`. It projects to a Linear Milestone where the team supports Project
  Milestones and otherwise folds onto the repo level behind a stable marker with a
  grouping label (`on_absent: degrade`), idempotently. Milestone is Linear's
  free-form narrative-shaped primitive and was reserved-but-unused in the 001
  baseline, so adopting it here introduces no conflict with the default mapping.

- **Partial mapping**: An incomplete `mapping:` block inherits the synthesized
  default per unspecified level (not all-or-nothing).

- **Identity + provenance**: A standalone-Issue or Project-projected level (under
  the #17 alternative) carries a stable filesystem-derived identity label so it
  matches/updates on re-run; the read-only-mirror provenance header renders as a
  single stable marker line above any in-body checklist, as today.

- **Out of scope**: bidirectional sync; any change to the default mapping or to the
  001 acceptance behaviour; a runtime/live probe of Linear artifact availability
  beyond the Milestone capability degrade path (the required-level artifacts are
  fixed Linear primitives and need no availability probe); a workstate-direct input
  seam and a status-rollup lever (both present in the Jira spec) are deferred to a
  later Linear feature and are not part of this port.

- **Dependencies**: Builds on the shipped 001 core bridge (its create / idempotent
  update / drift / fail-closed paths), the drift-aware write-authority model
  (003), the config/identity split (004), and the gitignored credential + binding
  files; targets a single Linear team/project binding per run.
