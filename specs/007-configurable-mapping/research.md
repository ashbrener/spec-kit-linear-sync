# Phase 0 Research: Configurable Artifact Mapping

**Feature**: `007-configurable-mapping`

**Date**: 2026-06-08

This document records the Phase 0 research decisions for feature 007 — a
faithful port of the spec-kit-jira `specs/002-configurable-mapping` model to
Linear primitives. All decisions were either resolved in the 2026-06-08 spec
clarify session or carried over from the settled Jira design-draft decisions
(formalized here as Linear-adapted research decisions).

The §2 locked decisions inherited from the Jira model (frozen default mapping,
opt-in additive `mapping:` block, offline relationship-validation matrix,
fail-closed config-load gate, per-level inheritance, off-by-default narrative
super-level, alias-layer back-compat) are constraints, not re-litigated
questions.

**Deliberately out of scope for this Linear port** (see dedicated entries
below): the `--workstate` direct-input seam, the status-rollup lever, and any
runtime availability probe for required-level Linear artifacts. Each is
explicitly deferred with a one-line rationale.

**Unresolved NEEDS CLARIFICATION**: there are **none**. All four clarify-session
questions are resolved; the deferred items are formalized at their out-of-scope
boundaries below. Nothing remains blocking for Phase 1 design.

---

## D1 — Alias-layer default synthesis (byte-for-byte back-compat)

- **Decision**: When no `mapping:` block is present in `linear-config.yml`,
  an alias layer in `src/config.sh` synthesizes today's shipped default
  (repo→Project, spec→Issue, phase→sub-issue, task→checklist, L0 off) entirely
  from the existing binding keys already present in the file. This synthesis
  produces zero file rewrites, zero config-version bumps, and zero behaviour
  changes for any pre-007 install.
- **Rationale**: The frozen zero-config default is constitutional (v2.1.0
  Architectural Constraints); the safety promise that "a no-config upgrade
  changes nothing" is the regression anchor for the whole feature (spec US1,
  SC-001, FR-001/FR-002). Synthesizing the default from existing keys (rather
  than writing an explicit `mapping:` block) means a pre-007 config file
  continues to load unchanged — the same file that worked before 007 works after
  007, with zero migration cost. A file rewrite would silently break diffs, git
  blame, and the "additive and optional" contract (spec FR-005, Clarification
  2026-06-08).
- **Alternatives considered**: Write a default `mapping:` block to
  `linear-config.yml` on first post-007 load (rejected — the "no file rewrite"
  promise is explicit in the spec clarification and in the v2.1.0 constitution
  amendment; a file rewrite counts as observable behaviour change); require an
  explicit `mapping:` block to enable the feature (rejected — defeats the
  opt-in/additive model and forces operators to restate the frozen default just
  to get the same behaviour).

---

## D2 — Relationship-validation matrix

- **Decision**: Hierarchy (parent → child) links are restricted to three
  allowed types: `parent` (Linear's native sub-issue nesting), `none` (top
  level, no parent relationship), and `checklist` (the non-issue sentinel that
  renders into the parent body). Two relationship types are explicitly rejected
  as hierarchy links: `blocks` and `relates` (both are dependency/cross-issue
  links, not nesting). Validation is **offline** (requires no Linear API call)
  and runs at **config-load**, before any write. Any rejected combination
  hard-halts the run and writes nothing (fail-closed, Principle VIII).
- **Rationale**: Allowing dependency-style links as nesting would produce a
  mis-shaped Linear graph — the sub-issue graph becomes corrupt without any
  explicit write failure (spec FR-006/FR-007, Clarification 2026-06-08). Offline
  validation is the constitutional differentiator: the matrix can be resolved
  against the declared config with no network round-trip, so a misconfiguration
  is caught before any mutation occurs (Principle VIII, spec SC-003). Linear has
  a single native nesting primitive (sub-issue `parent`); there is no
  `Epic-link` analogue. The restricted set of hierarchy types exactly matches
  the Linear primitive set — nothing is left out and nothing speculative is
  included.
- **Alternatives considered**: Allow `blocks`/`relates` as hierarchy links
  (rejected — these are cross-issue dependency semantics, not nesting; a
  `blocks` link between parent and child would silently mis-shape the graph);
  warn-and-continue on a rejected combination (rejected — violates fail-closed;
  a warning still permits a corrupt write; Principle VIII is explicit that the
  failure must be observable and must NOT write anything); runtime matrix
  validation via a live probe (rejected — couples config validation to a network
  call; offline is specifically required by FR-007).

  **Linear-vs-Jira note**: The Jira matrix allows `Epic-link` as a third
  hierarchy type (Epic-link is a Jira-specific parent relationship for classic
  projects). Linear has no equivalent — `parent` covers all nesting levels.
  Similarly Jira rejects `Implements` as a hierarchy link; Linear has no
  `Implements` primitive, so that rejection collapses into the two Linear
  dependency types (`blocks`, `relates`). The matrix shape is identical; the
  allowed-set contents are narrower.

---

## D3 — Per-level inheritance for partial `mapping:` blocks

- **Decision**: A `mapping:` block that specifies only some levels is valid.
  Each unspecified level independently inherits the alias-synthesized default
  for that level. A partial block is not an all-or-nothing validation error; it
  is treated identically to spelling out the full block with those levels set to
  their defaults.
- **Rationale**: Per-level inheritance is consistent with the optional/additive
  alias philosophy (D1) and directly satisfies the spec edge case (FR-005, spec
  US3, SC-005). The canonical ergonomics case is the #17 toggle: an operator
  overrides only the `spec` level (spec→Project) and leaves repo, phase, and
  task at their defaults — without per-level inheritance that requires restating
  three unchanged levels. Per-level fallback also preserves the back-compat
  promise on the partially-specified levels (the safe default fills the rest,
  exactly as if no block were present for those levels).
- **Alternatives considered**: All-or-nothing — require every level whenever
  `mapping:` is present (rejected — hostile to the additive/opt-in model,
  forces operators to restate the frozen default verbatim for levels they do not
  intend to override, and increases the chance of accidental divergence from
  today's behaviour; equivalent to the same rejection in the Jira research Q4).

---

## D4 — Design issue #17: spec-as-Project alternative

- **Decision**: The #17 spec-as-Project mapping (spec→Project, phase→Issue,
  task→sub-issue) is supported as a first-class alternative selectable
  entirely through the `mapping:` grammar, with no code change. It is not
  the default. The same grammar that configures any other level combination
  can express the #17 shape; no special-casing is required.
- **Rationale**: Making the mapping configurable resolves #17 as a choice rather
  than a one-off decision — the core framing of the feature (spec FR-004). Under
  the #17 shape, a spec becomes a Project (heavier, with its own milestone list
  and issue list), and its task phases become top-level Issues inside that
  Project. The grammar can express this without any structural divergence from
  the four-level workstate model. Identity keying (D7) handles the new
  Project-projected spec level correctly.
- **Alternatives considered**: Hard-code the #17 shape as a separate mode flag
  (rejected — would bifurcate the config surface and prevent the grammar from
  generalising further); make the #17 shape the new default (rejected —
  constitutionally forbidden without a MAJOR version bump; changing the default
  is reserved for MAJOR per v2.1.0 Architectural Constraints).

---

## D5 — Optional L0 narrative super-level → Linear Milestone

- **Decision**: The narrative super-level (L0, above the repo level) is
  **off by default**. When enabled (`super_level.enabled: true`), it projects to
  a Linear **Milestone** where the target team supports Project Milestones, and
  degrades gracefully when Milestones are unavailable. Degradation: the
  narrative folds onto the repo level behind a stable marker line, and repo
  grouping is carried as a label (`on_absent: degrade`). This degradation is
  idempotent — a team that later gains Milestone support can re-home the
  narrative without churn; a re-run in the degraded state produces zero writes.
  Narrative is populated only from an explicit source (`source: spec_input`,
  the spec's input description) and never inferred or fabricated (FR-012).
- **Rationale**: The L0 super-level is the narrative "what are we building"
  requirement above the per-repo Project, off by default so a no-config upgrade
  is unaffected. Linear's Milestone is the correct primitive: it is free-form,
  narrative-shaped, and was reserved-but-unused in the 001 baseline — adopting
  it here introduces no conflict with the default mapping. Graceful degradation
  matches the Jira `on_absent: degrade` policy for Initiatives (Jira research
  Q5) and mirrors the spec clarification (Clarification 2026-06-08): "never
  hard-fail because the team lacks Milestone support." The stable marker (not a
  free prepend) makes the fold idempotent and safely re-homeable. Milestone
  GraphQL helpers go in `src/graphql.sh` (the existing direct-GraphQL edge path,
  consistent with Principle VI seed-step fallback).

  **Linear-vs-Jira note**: Jira detects Initiative availability via an
  issue-type-metadata probe (Jira research Q5). For Linear, availability
  detection is simpler: the only optional artifact is the L0 Milestone (the
  required-level artifacts — Project, Issue, sub-issue, checklist — are fixed
  Linear primitives that cannot be absent). A lightweight Milestone-capability
  check at config-load (probing whether the target team's plan supports Project
  Milestones) gates the create path without touching the required-level
  validation matrix.

- **Alternatives considered**: Hard-fail when Milestones are unavailable
  (rejected — the clarification is explicit: the team-capability gap must not
  prevent the run; Principle VIII surfaces, does not block); operator config
  flag for availability instead of a probe (rejected as the primary mechanism —
  drifts from workspace reality; a probe is always authoritative); allow the L0
  narrative to be inferred from surrounding content (rejected — FR-012
  explicitly requires an explicit source only; inference violates the read-only
  mirror contract of Principle I).

---

## D6 — Milestone capability check vs required-level availability probe (deferred)

- **Decision**: A runtime availability probe for the **required-level** Linear
  artifacts (Project, Issue, sub-issue, checklist) is **out of scope** for this
  port and is not implemented.
- **Rationale**: The Jira sink requires an issue-type-metadata probe because
  Jira project templates ship different available issue types (Kanban simplified
  may lack Story; Jira research Q10). Linear has no equivalent — the required
  artifacts (Project, Issue, sub-issue, checklist) are fixed primitives present
  in every Linear workspace; there is nothing to probe. The only optional
  artifact is the L0 Milestone (D5), which has its own lightweight capability
  check. Adding a probe for required-level artifacts would be dead code and
  would needlessly couple config-load to a network call.
- **Alternatives considered**: Port the full Jira available-issue-type
  detection + per-level `on_absent` fallback for required levels (rejected —
  Linear's required-level artifacts cannot be absent, so the mechanism has no
  target; adding it would be speculative scope expansion, not a faithful port).

---

## D7 — Identity keying for Issue-projected and Project-projected levels

- **Decision**: Every level that projects to a standalone Issue or a Project
  (including under the #17 alternative where the spec becomes a Project) carries
  a stable, filesystem-derived identity label so reconcile re-runs match and
  update rather than re-create. Label key prefix assignments:
  - `speckit-repo:` — repo level (Project, as today)
  - `speckit-spec:` — spec level (Issue default; Project under #17)
  - `task-phase:N` — phase level (sub-issue default; Issue under #17)
  - `speckit-task:` — task level (checklist default; sub-issue under #17)

  A level configured to `artifact: "checklist"` has no standalone identity
  label — the checklist is keyed by workstate task identity within the parent
  body (D8). Required-id presence for any configured level that projects to an
  Issue or Project is validated before any write (FR-013).

- **Rationale**: FR-009 requires a defined identity key for every level
  projecting to a standalone artifact so the bridge converges on re-run rather
  than duplicating. Under the #17 alternative the spec-level artifact changes
  (Issue → Project), but the identity label prefix (`speckit-spec:`) and the
  filesystem-derived key do not change — the same label set describes the same
  spec regardless of which artifact it projects to. This is what makes the #17
  toggle zero-churn: the identity is portable across artifact types. A dedicated
  `speckit-task:` prefix for task-level standalone artifacts (sub-issues under
  #17) mirrors the Jira `task_prefix` decision (Jira research Q9) and avoids
  collisions with phase-level identity.
- **Alternatives considered**: Reuse the phase-level label prefix for
  task-level standalone artifacts (rejected — collides with `task-phase:N`
  and breaks unambiguous re-matching when both phase and task project to Issues);
  omit identity labels for Project-projected levels (rejected — FR-009 is
  explicit; the reconcile engine must match existing resources).

---

## D8 — Checklist re-render keyed by workstate task identity (zero-churn)

- **Decision**: Each checklist item rendered into a parent body is keyed by its
  **workstate task identity** (the stable filesystem-derived task code). The
  rendered checklist sub-tree is compared byte-for-byte against the existing
  body sub-tree; the body is updated **only when the checklist sub-tree has
  changed** — unrelated edits to the surrounding description do not trigger a
  rewrite. Reorder, completion-toggle, and rename are handled by re-rendering
  the keyed items so no item is duplicated. The read-only-mirror provenance
  header is rendered as a single stable marker line above the checklist
  sub-tree.
- **Rationale**: Idempotency in checklist-projected modes is the constitutional
  differentiator (Principles II/III, FR-008). The in-body checklist lives in the
  parent Issue body (Markdown), so it must re-render byte-identically for the
  content diff to be empty — a full-body compare would trigger rewrites on any
  unrelated description edit, breaking the zero-churn promise (SC-004). Keying
  by workstate task identity (rather than task text or ordinal position)
  prevents duplication on rename or reorder. The single stable marker line is
  present (Principle I read-only-mirror contract) without visually dominating
  the issue or perturbing the stable sub-tree compare.
- **Alternatives considered**: Key checklist items by task display text
  (rejected — a rename would create a duplicate or orphan the old item); key by
  ordinal position (rejected — a reorder would churn every item downstream of
  the move); full-body byte compare (rejected — unrelated description edits
  would force a checklist rewrite, breaking zero-churn); no provenance header
  in checklist mode (rejected — Principle I requires the read-only-mirror marker
  to be present).

  **Linear-vs-Jira note**: The Jira checklist renders into ADF (Atlassian
  Document Format); the Linear checklist renders into Markdown. The keying
  strategy and sub-tree compare logic are identical in shape; the serialisation
  format differs.

---

## D9 — `--workstate` direct-input seam (deferred — out of scope)

- **Decision**: The `--workstate` direct-input flag (a flag on the reconcile
  entrypoint that accepts a pre-parsed workstate document directly, skipping the
  parser stage) is **out of scope** for this Linear port.
- **Rationale (one-line)**: The Jira sink's `--workstate` seam targets
  non-spec-kit producers that cannot emit a `spec.md`; the Linear bridge has no
  such documented producer at this time — deferring keeps the scope honest.
- **Reference**: Jira research Q8 (resolved in the Jira 2026-06-03 clarify
  session); flagged deferred in spec 007 Assumptions → Out of scope.

---

## D10 — Status-rollup lever (deferred — out of scope)

- **Decision**: A configurable rollup lever that transitions parent-level
  workflow states when all children complete is **out of scope** for this
  Linear port.
- **Rationale (one-line)**: Status rollup is an additive behavioural concern
  orthogonal to the mapping grammar; deferring it keeps 007 focused on the
  configurable-mapping port without expanding the scope to state-machine logic.
- **Reference**: Jira research Q11 (formalized at its documented default in the
  Jira research); flagged deferred in spec 007 Assumptions → Out of scope.

---

## Jira-parity cross-reference

### Level grammar parity

The four-level workstate grammar is shared between the Jira and Linear sinks:

| workstate level | role | Jira research ref |
|---|---|---|
| L0 (narrative super-level, off) | narrative above the repo | Q5, Q6 |
| repo | root grouping unit | — (frozen default) |
| spec | per-spec work unit, drift anchor | — (frozen default) |
| phase | task-phase grouping | — (frozen default) |
| task | atomic task / checklist item | Q7, Q9 |

Each level carries `artifact` + `relationship_to_parent`. An absent `mapping:`
block synthesizes the frozen default via the alias layer (D1). A partial block
inherits per level (D3, Jira Q4). The `mapping:` grammar (level names, field
shape, alias semantics, relationship-matrix shape) matches the Jira sink so that
a reader of one config understands the other (FR-015, SC-007).

### Artifact parity table

| workstate level | Jira default | Linear default | Linear #17 alternative |
|---|---|---|---|
| L0 (narrative, off) | Initiative | Milestone | Milestone |
| repo | Epic | Project | Project |
| spec | Story | Issue | **Project** |
| phase | Subtask | sub-issue | **Issue** |
| task | checklist | checklist | **sub-issue** |

### Relationship vocabulary parity

| role | Jira | Linear | notes |
|---|---|---|---|
| Native nesting | `parent` | `parent` | identical |
| Epic-level nesting | `Epic-link` | — | no Linear analogue; collapses into `parent` |
| Top level (no parent) | `none` | `none` | identical |
| In-body render | `checklist` | `checklist` | identical |
| Rejected: dependency | `Blocks`, `Relates`, `Implements` | `blocks`, `relates` | no `Implements` primitive in Linear |

### Research decision parity map

| Jira Q# | topic | Linear D# | adaptation |
|---|---|---|---|
| Q2 | Relationship-validation matrix | D2 | Narrower allowed set (`Epic-link` collapses to `parent`; `Implements` absent) |
| Q3 | Project-style detection / probe | D6 (deferred) | Linear required-level artifacts are fixed primitives — no probe needed |
| Q4 | Per-level inheritance | D3 | Identical decision |
| Q5 | Initiative degradation mechanics | D5 | Linear Milestone replaces Jira Initiative; detection is a lightweight plan probe |
| Q6 | Initiative scope (per-repo 1:1) | D5 | Milestone is per-repo 1:1; same rationale |
| Q7 | Checklist keying + zero-churn | D8 | Same keying strategy; Markdown not ADF |
| Q8 | `--workstate` direct-input seam | D9 (deferred) | Out of scope for this Linear port |
| Q9 | Task-identity label prefix + provenance | D7 | `speckit-task:` label prefix; single stable marker |
| Q10 | Absent-type detection + `on_absent` | D6 (deferred) | Linear required-level artifacts cannot be absent |
| Q11 | Status-rollup lever | D10 (deferred) | Out of scope for this Linear port |

---

## Technical context

- **Language / runtime**: Bash, targeting the CI matrix (bash 4.4 and bash
  5.2). No new runtime dependencies are introduced.
- **External tooling**: `jq` (JSON), `curl` (Linear GraphQL API) — both already
  in use by the 001 core bridge; nothing new is added.
- **Source layout**: all mapping/alias/validation logic lives in
  `src/config.sh` (the source-agnostic config layer); `src/reconcile.sh`
  consumes a resolved mapping and gains no Linear-specific mapping knowledge
  (FR-014); Milestone GraphQL helpers (query/create/attach) go in
  `src/graphql.sh` using the existing edge GraphQL path (Principle VI).
- **Testing**: `bats` (unit + integration); `shellcheck --shell=bash
  --severity=style`; `yamllint`; `markdownlint-cli2`.
- **Unresolved NEEDS CLARIFICATION**: none. All decisions are resolved or
  formally deferred; nothing blocks Phase 1 design.
