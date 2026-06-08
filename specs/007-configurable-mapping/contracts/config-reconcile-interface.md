# Contract — config ↔ reconcile interface (feature-007)

This contract governs the boundary between `src/config.sh` (the source-agnostic
configuration layer that resolves and validates the `mapping:` block) and
`src/reconcile.sh` (the Linear projection that consumes a resolved mapping).
It is the Linear-side counterpart to the spec-kit-jira feature-002
`engine-sink-interface-002.md`. The key structural difference is that **Linear
has no separate sink module**: the Jira engine↔sink contract is replaced here
by a config↔reconcile contract, with `reconcile.sh` holding the Linear
projection and reading a fully resolved mapping from `config.sh` — gaining
NO Linear-specific mapping knowledge of its own (FR-014).

**Parity statement**: The resolved-mapping shape, per-level accessor contract,
and the guarantee that the reconcile engine is free of mapping knowledge mirror
the equivalent guarantees in the Jira `engine-sink-interface-002.md`. The
notable difference is that `graphql.sh` owns the Milestone helper surface
(create / attach / degrade) rather than a separate sink module, because
Milestone mutations are unavailable in the Linear MCP and must go via the
existing direct-GraphQL edge path (plan Technical Context).

---

## I. Config layer obligations (`src/config.sh`)

`config.sh` owns every mapping, alias, and validation concern (FR-014). It
exposes the resolved mapping to `reconcile.sh` via a **set of exported
shell variables and accessor functions** after the config-load validation gate
passes. `reconcile.sh` MUST NOT inspect the raw `linear-config.yml` `mapping:`
block; it reads only what `config.sh` exports.

### 1.1 Resolved-mapping shape

After a successful config-load, `config.sh` exports one record per workstate
level, plus the super-level state. The record for each level contains:

| Field | Type | Description |
|-------|------|-------------|
| `artifact` | string | the resolved Linear artifact for this level — `Project`, `Issue`, `sub-issue`, or `checklist` (or `Milestone` for the super-level only) |
| `relationship_to_parent` | string | the validated hierarchy link — `parent`, `none`, or `checklist` |
| `identity_key` | string | the filesystem-derived label prefix used to match/update this level on re-run (always present; `reconcile.sh` MUST pass this to every create/update call) |
| `is_top_level` | bool | `true` when this level has no parent in the resolved mapping (relationship is `none`) |

The super-level record additionally exposes:

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | `true` when the `super_level` block is on |
| `on_absent` | enum `degrade` | degrade policy (only `degrade` is supported) |
| `source` | enum `spec_input` | narrative source |

### 1.2 Accessor contract

`config.sh` exposes the following functions for consumption by `reconcile.sh`.
All functions read from the validated, resolved mapping; they do NOT re-read
the raw YAML.

```
config::resolved_artifact <level>
  → stdout: the resolved artifact string for the given level
  → exit 0; exit 2 if <level> is unknown (internal error — should not occur
    after a successful config-load gate)
```

```
config::resolved_relationship <level>
  → stdout: the resolved relationship_to_parent string for the given level
  → exit 0; exit 2 if <level> is unknown
```

```
config::resolved_identity_key <level>
  → stdout: the filesystem-derived identity label prefix for the given level
  → exit 0; exit 2 if <level> is unknown
```

```
config::is_top_level <level>
  → exit 0 (true) when the level is the topmost resolved level (relationship "none")
  → exit 1 (false) otherwise
```

```
config::super_level_enabled
  → exit 0 (true) when the super_level is on
  → exit 1 (false) otherwise
```

```
config::super_level_milestone_source
  → stdout: "spec_input" (the only supported value; NEVER inferred)
  → exit 0
```

**Level identifiers**: `repo`, `spec`, `phase`, `task` (plus `super_level` for
the super-level accessors). These are the canonical workstate level names; no
vendor-specific names enter the interface.

### 1.3 Config-layer guarantee (FR-014)

`config.sh` MUST encapsulate ALL of the following; `reconcile.sh` MUST NOT
re-implement or duplicate any of them:

- Parsing the `mapping:` block from `linear-config.yml`.
- Synthesizing the alias-layer default when `mapping:` is absent.
- Per-level inheritance for partially specified `mapping:` blocks.
- Offline relationship-validation matrix checks.
- Required-id presence checks.
- Writing back the resolved mapping into the exported shape above.

Any future change to the mapping grammar or validation rules MUST be applied
exclusively in `config.sh`; `reconcile.sh` remains free of mapping knowledge.

---

## II. Reconcile layer obligations (`src/reconcile.sh`)

`reconcile.sh` owns the Linear projection: it reads the resolved mapping via
the accessor contract above and dispatches each workstate level to the correct
Linear create/update path. It gains NO knowledge of the `mapping:` grammar,
the alias layer, the validation matrix, or the raw `linear-config.yml` keys.

### 2.1 Mapping-driven projection (per-level artifact + relationship)

For each workstate level, `reconcile.sh` calls `config::resolved_artifact` and
`config::resolved_relationship` to determine what to create and how to link it.

| Function | Returns | Notes |
|----------|---------|-------|
| `reconcile::sync_level <level> <identity_label> <parent_id> <input_json>` | `{id}` (for Project/Issue/sub-issue) or empty (for `checklist`) | create/update the resolved artifact under `parent_id` with the resolved relationship; idempotent match by `identity_label` |
| `reconcile::link_to_parent <child_id> <parent_id> <relationship>` | ok | applies `parent` link **only** when the child's current parent differs (read-before-write, zero-churn); no-op for `none` and `checklist` |

`input_json` is the level payload (sink-neutral):

```json
{
  "summary": "<issue or project title>",
  "body": "<markdown body>",
  "labels": ["<phase-label>", "...operator labels"]
}
```

- `labels` is the **desired** label set EXCLUDING the identity label. The
  reconcile layer composes the on-the-wire desired set as
  `([identity_label] + (input.labels // [])) | unique` for both the create
  path and the PRESENT-path label diff — so configured phase/operator labels
  survive an idempotent update (zero-churn, FR-008 / FR-009). An absent or
  empty `labels` array projects just the identity label.
- A level projecting to `Project` under the `#17` alternative (FR-004) carries
  a stable filesystem-derived identity label so re-runs match/update rather
  than re-create (FR-009).
- `checklist`-sentinel levels create **no** child artifact; they render into
  the parent Issue body via `reconcile::sync_body_checklist` (see §2.2).

### 2.2 In-body checklist render — keyed sub-tree byte-diff (FR-008)

| Function | Returns | Notes |
|----------|---------|-------|
| `reconcile::render_checklist_subtree <tasks_json>` | markdown checklist fragment | each item **keyed by its workstate task id**; stable byte ordering |
| `reconcile::diff_checklist_subtree <issue_id> <rendered_subtree>` | `changed` \| `unchanged` | byte-compares **only** the checklist sub-tree against the current body, not the full body |
| `reconcile::sync_body_checklist <issue_id> <rendered_subtree>` | ok; **skip write when `unchanged`** | writes the body only when the sub-tree changed (FR-008) |

- A re-run against unchanged tasks re-renders **byte-identical** markdown ⇒
  `unchanged` ⇒ zero writes (FR-008, US1 scenario 2, SC-004).
- Each checklist item is keyed by its workstate task id so reorder /
  completion-toggle / rename is handled by re-rendering keyed items; no item
  is duplicated and unrelated body edits do **not** trigger a rewrite.
- A single stable **provenance marker** line renders above the checklist
  sub-tree without perturbing the byte-stable compare (the marker is fixed and
  included in both sides of the diff).

### 2.3 L0 super-level projection (Milestone + graceful degradation)

`reconcile.sh` calls `config::super_level_enabled` before entering the
super-level projection path. When enabled, it delegates Milestone
create/attach/degrade to `graphql.sh` (see §III).

The reconcile layer's obligations in the super-level path:

- Pass the narrative only from the `spec_input` source (the spec's "Input:"
  line); NEVER pass an inferred or fabricated narrative (FR-012).
- Call `graphql::ensure_milestone` and, if the return code signals degradation
  (`rc=2`), call `graphql::degrade_milestone_onto_repo` — never hard-fail when
  the Milestone path degrades (FR-011, SC-006).
- On a degraded re-run: call the same degrade path; a later Milestone-capable
  run calls `ensure_milestone` again and re-homes the narrative without churn.
- Never expose the super-level Milestone id to the per-level resolved mapping
  accessors; the Milestone is above the mapping levels, not a peer.

---

## III. Milestone GraphQL helper surface (`src/graphql.sh`)

Milestone create/attach mutations are absent from the Linear MCP and MUST go
via the direct-GraphQL edge path already used by the 001 seed fallback (plan
Technical Context, Principle VI). `graphql.sh` owns these helpers; `reconcile.sh`
calls them and `config.sh` does NOT.

### 3.1 Capability probe

```
graphql::probe_milestone_support <team_id>
  → exit 0 ("present") when Project Milestones are available for <team_id>
  → exit 1 ("absent")  when Project Milestones are unavailable
  Performs a lightweight GraphQL query; result is cached for the run.
  <team_id> is a PLACEHOLDER — the real value lives in the gitignored binding
  file (FR-018).
```

### 3.2 Create / attach

```
graphql::ensure_milestone <project_id> <narrative> <repo_slug>
  → stdout: milestone_id (PLACEHOLDER shape only)
  → exit 0 on create or idempotent match (already present, zero churn)
  → exit 2 on Milestone-unavailable (caller MUST call degrade path)
  Idempotent: matches an existing Milestone by the stable <repo_slug>-derived
  identity marker before creating; creates only when absent.
  <project_id> is a PLACEHOLDER — real value lives in the gitignored file.
  Narrative is populated ONLY from the explicit spec_input source (passed in
  by reconcile.sh); graphql.sh MUST NOT infer or fabricate narrative content.
```

### 3.3 Degrade

```
graphql::degrade_milestone_onto_repo <project_id> <narrative> <repo_slug>
  → exit 0 always (never hard-fails — FR-011)
  Folds the narrative onto the repo-level Project behind a STABLE MARKER
  (a fixed, recognisable prefix line in the Project description that is
  included in both sides of any subsequent byte-diff). Adds repo grouping
  as a label using the existing label surface. Idempotent: a re-run in the
  degraded state is zero-churn (the stable marker prevents double-folding).
```

### 3.4 Re-home on upgrade

```
graphql::rehome_milestone_from_repo <project_id> <repo_slug>
  → exit 0 on successful re-home or when no degraded narrative is present
  Called by reconcile.sh when probe_milestone_support returns "present" but
  a prior degraded-state stable marker is detected in the Project description.
  Moves the narrative to a proper Milestone and removes the stable marker +
  grouping label. Idempotent.
```

### 3.5 GraphQL mutation shapes (placeholders only — FR-018)

All `team_id`, `project_id`, `milestone_id`, and label id values in the
mutations below are **PLACEHOLDERS**. Real values live exclusively in the
gitignored operator-local binding file and `.env` (FR-018).

```graphql
# probe_milestone_support — lightweight capability check
query ProbeMilestoneSupport($teamId: String!) {
  team(id: $teamId) {
    id
    milestones {
      nodes { id }
    }
  }
}

# ensure_milestone — idempotent create/attach
mutation EnsureMilestone(
  $projectId: String!,
  $name: String!,
  $description: String!
) {
  projectMilestoneCreate(input: {
    projectId: $projectId,
    name: $name,
    description: $description
  }) {
    projectMilestone { id name }
    success
  }
}

# degrade / re-home — project description update
mutation UpdateProjectDescription(
  $projectId: String!,
  $description: String!
) {
  projectUpdate(id: $projectId, input: {
    description: $description
  }) {
    project { id description }
    success
  }
}
```

---

## IV. End-to-end flow (summary)

```
config.sh                               reconcile.sh                 graphql.sh
─────────────────────────────────────── ──────────────────────────── ──────────────────────
1. parse mapping: block (or alias)
2. per-level inheritance
3. relationship-matrix validation (offline)
4. required-id presence check
   all fail-closed → exit 2 on any fail
5. export resolved mapping (accessors) ─→
                                        6. for each workstate level:
                                           resolved_artifact(level)
                                           resolved_relationship(level)
                                           resolved_identity_key(level)
                                           → sync_level(...)
                                        7. checklist level:
                                           render_checklist_subtree(...)
                                           diff_checklist_subtree(...)
                                           sync_body_checklist(...)
                                        8. if super_level_enabled:
                                           narrative ← spec_input only
                                           → ensure_milestone(...)  ──→  probe_milestone_support
                                                                         ensure_milestone
                                           if rc=2 (absent):        ──→  degrade_milestone_onto_repo
                                           if re-home needed:       ──→  rehome_milestone_from_repo
```

**Invariant**: at no point in steps 6–8 does `reconcile.sh` read the raw
`mapping:` YAML block or make a decision based on Linear-specific mapping
knowledge. All such knowledge was resolved and validated by `config.sh` in
steps 1–5 (FR-014).

---

## V. Contract tests

- `config::resolved_artifact`, `config::resolved_relationship`,
  `config::resolved_identity_key` each return the correct value for every
  workstate level under the default mapping and under the `#17` alternative.
- `config::is_top_level` returns true for the topmost level only; false for
  all others.
- `config::super_level_enabled` returns false for a default/no-block config
  and true when `super_level.enabled: true` is set.
- `config::super_level_milestone_source` always returns `"spec_input"`;
  never any other value.
- `reconcile::sync_level` creates the configured artifact (Project / Issue /
  sub-issue) with the correct relationship and identity label; a re-run is
  zero-churn (idempotent match by identity label).
- `reconcile::sync_body_checklist` re-renders byte-identically on a second
  run against unchanged tasks (zero writes).
- Checklist items are keyed by workstate task id; an unrelated body edit
  does not trigger a rewrite.
- `graphql::ensure_milestone` is idempotent (second call with the same
  `repo_slug` does not create a duplicate Milestone).
- `graphql::degrade_milestone_onto_repo` is idempotent (second call in the
  degraded state does not double-fold the narrative or add a duplicate label).
- `graphql::rehome_milestone_from_repo` re-homes the narrative cleanly and
  removes the stable marker; a subsequent ensure_milestone call is zero-churn.
- Full pipeline: default mapping → same Project/Issue/sub-issue/checklist
  result as the pre-feature behaviour (US1, SC-001).
- Full pipeline: `#17` mapping → spec becomes a Project, phase becomes an
  Issue, task becomes a sub-issue (US2 scenario 1, SC-002).
- Full pipeline: super-level on + Milestones present → Milestone above the
  repo Project with narrative from spec_input only (US4 scenario 1).
- Full pipeline: super-level on + Milestones absent → narrative folds onto
  repo Project, run succeeds, zero hard-failure (US4 scenario 2, SC-006).
