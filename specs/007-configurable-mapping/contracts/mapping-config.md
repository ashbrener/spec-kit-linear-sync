# Contract — `mapping:` configuration block

The new, optional `mapping:` block layers over the existing `team_id`,
`project_id`, `labels`, and `phase_status` binding keys (their meaning is
unchanged from 001 `data-model.md` §2). It describes, per `workstate` level,
the Linear **artifact** to project to and the **relationship** that links the
level to its parent. This contract governs `src/config.sh`: the schema, the
alias layer, the relationship-validation matrix, and the config-load
validation order (FR-002–FR-007, FR-013–FR-015, FR-018). All values here are
placeholders (FR-018 — no real Linear coordinates in tracked files).

**Parity statement (FR-015 / SC-007)**: This contract is structurally
equivalent to the spec-kit-jira `specs/002-configurable-mapping/contracts/
mapping-config.md` (FR-015). Level names, `artifact` + `relationship_to_parent`
field shape, optional/additive alias semantics, and relationship-matrix shape
are carried over unchanged. Three deliberate Linear adaptations are called out
where they occur:
  1. No `project_style` field — Linear has a single native nesting primitive
     (`parent`, the sub-issue link), so the team-managed vs. classic distinction
     does not exist.
  2. No `on_absent` per-level fallback and no available-type probe — the
     required four levels project to fixed Linear primitives (Project, Issue,
     sub-issue, checklist), whose availability is guaranteed; only the optional
     L0 Initiative degrades gracefully via `on_absent: "degrade"`. (Linear
     Milestones live *inside* a Project and cannot serve as an above-Project
     container; the real above-Project container is the Initiative — used by
     both the Linear and Jira sinks for L0, improving Jira parity.)
  3. No `status_rollup` field — that lever is deferred to a later Linear
     feature (spec Assumptions → Out of scope).

## Schema

```yaml
# linear-config.yml (committed, per-repo binding file)
# All values below are PLACEHOLDERS only (FR-018).

extension:
  id: linear                   # unchanged; MUST remain "linear" (FR-016)

linear:
  team_id:   "<PLACEHOLDER_TEAM_ID>"      # gitignored credential/binding
  project_id: "<PLACEHOLDER_PROJECT_ID>" # gitignored credential/binding

  mapping:                     # NEW — optional. Absent => alias-synthesized default.
    l0:                        # OPTIONAL narrative super-level above repo. OFF by default.
      enabled: false
      artifact: "Initiative"   # Linear Initiative — above-Project narrative container
      on_absent: "degrade"     # degrade => fold narrative onto repo level + grouping label
      source: "spec_input"     # spec.md "Input:" line; NEVER inferred (FR-012)
    levels:
      repo:   { artifact: "Project",   relationship_to_parent: "none" }
      spec:   { artifact: "Issue",     relationship_to_parent: "parent" }
      phase:  { artifact: "sub-issue", relationship_to_parent: "parent" }
      task:   { artifact: "checklist", relationship_to_parent: "checklist" }
```

*The `#17 spec-as-Project` alternative (FR-004, US2) uses:*

```yaml
  mapping:
    l0:
      enabled: true
      artifact: "Initiative"
      on_absent: "degrade"
      source: "spec_input"
    levels:
      repo:  { artifact: "Initiative", relationship_to_parent: "none" }
      spec:  { artifact: "Project",    relationship_to_parent: "parent" }
      phase: { artifact: "Issue",      relationship_to_parent: "parent" }
      task:  { artifact: "sub-issue",  relationship_to_parent: "parent" }
```

*(In the `#17` shape: `repo→Initiative/none`, `spec→Project/parent`,
`phase→Issue/parent`, `task→sub-issue/parent`. Unspecified levels inherit the
synthesized default per the per-level inheritance rule below.)*

### Field reference

| Path | Type | Required | Default |
|------|------|----------|---------|
| `mapping` | map | no | absent ⇒ alias layer synthesizes the block below |
| `mapping.l0.enabled` | bool | no | `false` |
| `mapping.l0.artifact` | enum `Initiative` | no | `"Initiative"` |
| `mapping.l0.on_absent` | enum `degrade` | no | `"degrade"` |
| `mapping.l0.source` | enum `spec_input` | no | `"spec_input"` |
| `mapping.levels.<level>.artifact` | enum (see vocabulary below) | yes, when the level is present | per default below |
| `mapping.levels.<level>.relationship_to_parent` | enum (see matrix below) | yes, when the level is present | per default below |

`<level>` ∈ `{repo, spec, phase, task}` (plus `l0` as the optional
narrative super-level above `repo`).

**Linear artifact vocabulary**: `Initiative`, `Project`, `Issue`, `sub-issue`,
`checklist` (the non-issue render sentinel). `Initiative` is the only valid
artifact for the `l0` block; it is also available in the regular levels array
for the `#17` shape where repo maps to an Initiative. *Linear adaptation 2*:
these are fixed primitives; no available-type probe is needed or performed for
the four required levels. (Linear Milestones live inside a Project; they are
not a valid above-Project container and are not part of the artifact vocabulary.)

**`relationship_to_parent` vocabulary**: `parent`, `none`, `checklist` — the
three allowed hierarchy links (see matrix below). *Linear adaptation 1*: there
is no `Epic-link` analogue because Linear has a single native nesting
primitive (sub-issue `parent`).

### Default mapping (synthesized when `mapping:` is absent)

| workstate level | artifact | relationship_to_parent |
|-----------------|----------|------------------------|
| L0 (`l0`)       | Initiative | — (off by default) |
| repo | Project | `none` |
| spec | Issue | `parent` |
| phase | sub-issue | `parent` |
| task | checklist | `checklist` |

## Alias layer (absent `mapping:` ⇒ synthesize today's default)

When `mapping:` is **absent**, `config.sh` synthesizes the default block above
(`repo→Project`, `spec→Issue`, `phase→sub-issue`, `task→checklist`,
`l0` off) from the existing `team_id` / `project_id` / `labels` /
`phase_status` binding keys. No file rewrite, no version bump (FR-002).

- **Back-compat guarantee**: a pre-feature `linear-config.yml` (no `mapping:`
  block) loads **byte-for-byte unchanged** and projects identically to the
  prior version — zero behavioural change on a no-config upgrade (US1, SC-001,
  FR-001 / FR-002).
- **Partial block (per-level inheritance)**: when `mapping:` is present but a
  level is unspecified, that level **inherits the synthesized default per
  level** — a partial block is valid and is not an all-or-nothing error
  (FR-005, US3). Unspecified levels mirror as if the default were explicit for
  those levels (SC-005).
- **Equivalence**: an explicit block that spells out the full default mapping
  is equivalent to the absent-block case (US1 scenario 3, FR-002 edge case).

## Relationship-validation matrix (FR-006 / FR-007)

Hierarchy (parent → child) links are restricted to genuine Linear nesting
primitives. Every rejection is a **hard-halt at config-load, before any
write** (FR-007, Principle VIII — fail-closed, exit 2). The matrix is
**offline** — it requires no Linear API call.

The validation gate enforces **two independent sub-checks**:

### (a) Relationship-type rules

| `relationship_to_parent` | Allowed as hierarchy link | Notes |
|--------------------------|---------------------------|-------|
| `parent` | **allow** | native sub-issue nesting |
| `none` | **allow** | top level — no parent link |
| `checklist` | **allow** | non-issue sentinel; level renders into the parent body |
| `blocks` | **reject** | cross-spec dependency link, not nesting |
| `relates` | **reject** | cross-spec dependency link, not nesting |

*Linear adaptation 1 (parity note)*: The Jira matrix includes `Epic-link`,
`Relates`, `Blocks`, and `Implements`. The Linear matrix drops `Epic-link` (no
analogue) and `Implements` (no Linear primitive); `blocks` and `relates`
remain rejected as hierarchy links, exactly as in the Jira sink. Linear's
native blocking/relating links remain available for inter-task-phase ordering
as today (FR-001) — they are separate from the hierarchy.

**Additional hard rejects from relationship-type rules** (FR-006):

- A level whose `artifact: "checklist"` paired with any
  `relationship_to_parent` other than `checklist` — rejected (the checklist
  sentinel is non-issue and MUST render into the parent body).
- A `checklist` relationship paired with any artifact other than `checklist` —
  rejected (the checklist relationship is only valid for the checklist sentinel).
- A `parent` relationship declared on the top-level position (i.e., the level
  that has no parent level in the resolved mapping, typically `repo` when L0 is
  off) — rejected (a `parent` link requires a parent level to attach to).
- A `none` relationship declared on any level that is not the topmost —
  rejected (levels below the top MUST be linked to their parent).

### (b) Containment matrix (Linear-native nesting hierarchy)

For every non-top level linked by `parent`, the **parent level's resolved
artifact** must be one that Linear can actually nest the child under. The
`config::_valid_parent_artifacts` helper encodes this allow-list; the
containment check is the second offline gate. Violations are rejected at
config-load (fail-closed, exit 2) before any write.

Linear container hierarchy: **Initiative > Project > Issue > sub-issue**
(checklist = in-body sentinel at task level, no standalone artifact).

| Child artifact | Valid parent artifact | Notes |
|----------------|-----------------------|-------|
| `Project` | `Initiative` | a Project belongs to an Initiative |
| `Issue` | `Project` | an Issue belongs to a Project |
| `sub-issue` | `Issue` | a sub-issue parents to an Issue |
| `checklist` | any (renders in body) | no containment check needed |
| `Initiative` | — (top-only) | Initiatives do not nest under another artifact |

Rejected examples (caught at config-load, exit 2):

- `Project` under `Project` — rejected (use an `Initiative` as the parent for
  the `#17` spec-as-Project shape).
- `Issue` under `Issue` — rejected.
- `sub-issue` under `Project` — rejected (must go through an Issue).
- Any artifact under `sub-issue` — rejected (sub-issue is the lowest
  standalone artifact).

## Required-id presence rules (FR-013)

Before any write, `config.sh` verifies that each configured artifact that
projects to a standalone Issue or a Project carries a valid, resolvable
identity-key binding so that `reconcile.sh` can match/update on re-run (FR-009):

- A level projecting to `Project` requires a `project_id`-style binding key
  present in the gitignored operator-local file for that level. Under the
  default mapping this is the top-level `project_id` binding. Under the `#17`
  alternative, a `spec`-level `project_id` binding is also required.
- A level projecting to `Issue` or `sub-issue` requires the equivalent
  team/project binding so the identity label can be resolved.
- The `checklist` sentinel is exempt — it renders into its parent's body and
  carries no independent identity binding.
- An enabled `l0` block (`Initiative`) does not require a pre-existing
  binding id — `config.sh` defers to `reconcile.sh` / `graphql.sh`, which
  creates/attaches the Initiative idempotently and degrades gracefully if
  Initiatives are unavailable on the workspace (see below).

Any missing required binding is a **workspace-level configuration error →
exit 2**, writing nothing for the run (FR-013, Principle VIII).

## Narrative super-level (`l0`) and graceful degradation (FR-011)

The optional `l0` block (off by default) introduces a narrative level above
`repo` that projects to a Linear **Initiative**. Initiative is Linear's
above-Project container and is the correct above-Project narrative primitive;
Linear Milestones live *inside* a Project and cannot serve this role.

- `source: "spec_input"` — narrative is populated ONLY from the spec's "Input:"
  description line; never inferred or fabricated (FR-012).
- `on_absent: "degrade"` — when Initiatives are unavailable on the workspace,
  the narrative folds onto the `repo`-level Project behind a **stable marker**
  and repo grouping becomes a label; the run MUST succeed — no hard failure
  (FR-011, SC-006). *Linear adaptation 2 (parity note)*: this mirrors the Jira
  `initiative.on_absent: "degrade"` policy exactly — both sinks use an
  Initiative for L0, improving Jira parity. `absent → degrade` is the only
  supported policy; hard-error on absent is not an option for the L0 level.
- Degradation is **idempotent**: re-runs in the degraded state are zero-churn;
  a later workspace upgrade to Initiative-capable re-homes the narrative
  without churn.
- The `l0` level, even when enabled, is **not** a new drift surface — the
  spec-level work unit remains the backward-drift anchor in every mode
  (FR-010).

## Config-load validation order (all BEFORE any write)

Validation is a single fail-closed gate; any failure is a **workspace-level
configuration error → exit 2**, writing nothing for the run (FR-007, FR-013,
Principle VIII). Order:

1. **Parse** the `mapping:` block (or synthesize the default via the alias
   layer); apply per-level inheritance for any unspecified levels.
2. **Relationship-type validation** (offline): reject every nonsensical
   hierarchy link per the matrix above — `blocks`, `relates`, `parent` on the
   top level, `none` below the top level, or `checklist` artifact with a
   non-`checklist` relationship (and vice versa).
3. **Containment matrix validation** (offline): for every non-top level linked
   by `parent`, verify the parent level's resolved artifact is a valid Linear
   container for the child artifact per the Initiative > Project > Issue >
   sub-issue hierarchy (via `config::_valid_parent_artifacts`). Rejects
   Project-under-Project and other invalid nesting arrangements.
4. **Required-id presence check**: verify each Issue/Project/Initiative-projected
   level has its required binding key present in the operator-local gitignored
   file (the `l0` block is exempt — its identity is managed at runtime by
   `graphql.sh`).

Only after all four pass does `config.sh` export the **resolved mapping** to
`reconcile.sh` (the consuming layer). *Linear adaptation 2 (parity note)*: The
Jira sink runs five validation steps (the extra step is the available-type
probe). The Linear sink omits that step because the required-level artifacts
are fixed Linear primitives; only the L0 Initiative capability is probed, but
that probe is deferred to runtime in `graphql.sh` as part of the
graceful-degradation path (not a hard config-load gate).

## Contract tests

- Absent `mapping:` ⇒ synthesized default equals the explicit default block
  (alias equivalence, US1 scenario 3).
- A pre-feature `linear-config.yml` loads unchanged and projects
  byte-identically (US1, SC-001).
- A partial block inherits the synthesized default on all unspecified levels
  and mirrors identically to the equivalent full block (US3, SC-005).
- `blocks` or `relates` declared as `relationship_to_parent` → hard-halt at
  config-load with exit 2, no write (SC-003).
- `parent` declared on the topmost level → hard-halt, exit 2, no write.
- `checklist` artifact with a non-`checklist` relationship → hard-halt,
  exit 2, no write (US2 scenario 3).
- Non-`checklist` artifact with a `checklist` relationship → hard-halt,
  exit 2, no write.
- `Project` under `Project` (containment violation) → hard-halt, exit 2,
  no write.
- `Issue` under `Issue` (containment violation) → hard-halt, exit 2, no write.
- A missing required-id binding for an Issue/Project-projected level →
  hard-halt, exit 2, no write.
- `l0` on + Initiatives available ⇒ Initiative created with narrative
  from `spec_input` only (US4 scenario 1).
- `l0` on + Initiatives unavailable ⇒ narrative folds onto the repo
  level behind stable marker + grouping label, run succeeds (US4 scenario 2,
  SC-006).
- `l0` off (default) ⇒ no narrative level, behaviour matches US1
  (US4 scenario 3).
