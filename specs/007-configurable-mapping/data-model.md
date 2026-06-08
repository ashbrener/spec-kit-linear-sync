# Phase 1 Data Model — Configurable Artifact Mapping (Linear)

Entities for the additive `mapping:` config block, the neutral workstate
levels it consumes, the Linear artifact vocabulary, the relationship-validation
matrix, the identity-label prefixes, and the narrative source. This is a DATA
model — shapes + rules, not implementation. No real coordinates; all ids are
placeholders (`<UUID>`, `<slug>`, `<NNN>`) resolved only in gitignored
credential/binding files (FR-018). Every validation rule below runs
**fail-closed at config-load, before any write** unless noted otherwise
(FR-007, Principle VIII).

**Scope note**: this model is a faithful port of the spec-kit-jira
`specs/002-configurable-mapping` data model to Linear primitives. Where the
two models diverge the delta is called out explicitly. Two items present in the
Jira data model are **deferred** here: the `--workstate` direct-input seam
(§2.3 in the Jira model) and the `status_rollup` lever (§1 field in the Jira
model) are out of scope for this port — see spec Assumptions.

---

## 1. `mapping:` config block (additive over existing `linear-config.yml` keys)

An OPTIONAL block layered over the existing `linear.*` keys in
`.specify/extensions/linear/linear-config.yml` (which keep their 001 meaning
unchanged — `linear.team.id`, `linear.project.id`,
`linear.workflow_state_uuids.*`, etc.). Absent ⇒ the alias layer synthesizes
the DEFAULT block below, reproducing today's behaviour byte-for-byte (FR-001,
FR-002). Present ⇒ each specified level overrides; unspecified levels inherit
the synthesized default per level (per-level inheritance, FR-005).

### 1.1 Synthesized DEFAULT block (what the alias layer emits when `mapping:` absent)

The alias layer reads the existing committed binding keys (`linear.team.id`,
`linear.project.id`, `linear.workflow_state_uuids.*`,
`linear.default_state_uuids.*`) and from them synthesizes the mapping below —
with no file rewrite and no version bump — so a pre-feature
`linear-config.yml` loads unchanged.

```yaml
# .specify/extensions/linear/linear-config.yml
schema_version: 1

linear:
  team:
    id: "<UUID>"
  project:
    id: "<UUID>"
  workflow_state_uuids:
    specifying:      "<UUID>"
    clarifying:      "<UUID>"
    planning:        "<UUID>"
    tasking:         "<UUID>"
    red_team:        "<UUID>"
    implementing:    "<UUID>"
    analyzing:       "<UUID>"
    ready_to_merge:  "<UUID>"
    merged:          "<UUID>"
  default_state_uuids:
    todo:        "<UUID>"
    in_progress: "<UUID>"
    done:        "<UUID>"
  labels:
    spec_prefix:      "speckit-spec:"
    repo_prefix:      "speckit-repo:"
    phase_prefix:     "task-phase:"
    lifecycle_prefix: "phase:"
    task_prefix:      "speckit-task:"   # identity key for task-level when projected
                                        # to a standalone sub-issue under the #17
                                        # alternative; synthesized by alias layer

  # NEW — optional. Absent => alias layer synthesizes exactly this default.
  mapping:
    l0:
      enabled: false                    # OFF by default (FR-011)
      artifact: "Milestone"             # Linear Milestone (narrative-shaped primitive)
      on_absent: "degrade"              # ONLY supported policy — fold onto repo level
      source: "spec_input"              # spec.md "Input:" line; NEVER inferred (FR-012)
    levels:
      repo:
        artifact: "Project"
        relationship_to_parent: "none"  # or "parent" when l0 is on
      spec:
        artifact: "Issue"
        relationship_to_parent: "parent"  # Issue under repo Project
      phase:
        artifact: "sub-issue"
        relationship_to_parent: "parent"  # sub-issue of spec Issue
      task:
        artifact: "checklist"
        relationship_to_parent: "checklist"  # in-body checklist render
```

### 1.2 Field reference

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `mapping` | block | (synthesized) | absent ⇒ alias layer emits the default |
| `mapping.l0.enabled` | bool | `false` | narrative super-level on/off (FR-011) |
| `mapping.l0.artifact` | string | `"Milestone"` | Linear Milestone; only valid L0 artifact |
| `mapping.l0.on_absent` | enum | `"degrade"` | `degrade` is the only supported policy |
| `mapping.l0.source` | enum | `"spec_input"` | explicit origin only; never inferred (FR-012) |
| `mapping.levels.<level>.artifact` | string | per default | Linear artifact or `checklist` sentinel |
| `mapping.levels.<level>.relationship_to_parent` | enum | per default | hierarchy link kind |

`<level>` ∈ `{repo, spec, phase, task}`.

`relationship_to_parent` vocabulary (Linear): `parent`, `none`, `checklist`.
Rejected values (hard-halt at config-load): `blocks`, `relates`.

**Linear vs Jira relationship vocabulary delta**: Linear has a single native
nesting primitive (the sub-issue `parent` link). There is no `Epic-link`
analogue. Jira's `Epic-link`/`Blocks`/`Relates`/`Implements` map to Linear as
follows: `Epic-link` → `parent` (the only nesting link); `Blocks`/`Relates`/
`Implements` → rejected (`blocks`/`relates` in Linear, still rejected).

### 1.3 Validation rules (all fail-closed at config-load, before any write)

- A `mapping:` block with only some levels is VALID; unspecified levels inherit
  the synthesized default per level (FR-005). Not an all-or-nothing error.
- `mapping.l0.on_absent` MUST be `degrade` (the only supported policy); any
  other value is a config error.
- `mapping.l0.source` MUST be `spec_input` (never inferred; FR-012).
- Each `levels.<level>.artifact` MUST be a member of the Linear artifact
  vocabulary (§3) — except the `checklist` sentinel, which projects no
  standalone artifact. **No availability probe is required for the four
  required levels** — `Project`, `Issue`, `sub-issue`, and `checklist` are
  fixed Linear primitives available in every Linear workspace. Only the L0
  `Milestone` has a degrade path (`on_absent: degrade`), not a hard error.
- Each `relationship_to_parent` is checked against the relationship-validation
  matrix (§4). Any rejected value is a config error (hard-halt, no write).
- An artifact that resolves to a standalone Issue or sub-issue REQUIRES the
  corresponding `labels.*_prefix` identity key to be present in
  `linear-config.yml`; a missing required prefix is a config error (FR-009,
  FR-013). (The alias layer synthesizes all five default prefixes so this is
  only relevant for manually-trimmed configs.)
- `l0.enabled: true` does NOT require a Milestone UUID — Milestone
  availability is runtime-detected; absence is handled by `on_absent: degrade`,
  not a config error (FR-011).
- `mapping.l0.enabled: true` REQUIRES `mapping.l0.source: "spec_input"` (the
  only supported source); any other value is a config error.

### 1.4 State / lifecycle notes

- The synthesized default and an explicit full default block MUST be equivalent
  (alias-layer round-trip; FR-002, US1 scenario 3).
- L0 degrade→upgrade re-home MUST be idempotent: folding the narrative onto the
  repo Project (degraded) and later re-homing it onto a real Milestone produces
  zero churn on unchanged content, keyed by the stable marker (§6) and the
  reused `repo_prefix` grouping label (FR-008, FR-011).
- **DEFERRED (out of scope)**: `status_rollup` — present in the Jira data
  model as a top-level lever; deferred to a later Linear feature per spec
  Assumptions. No `status_rollup` field is defined in this model.

---

## 2. workstate level vocabulary (neutral units the mapping consumes)

The mapping consumes four neutral, ordinal structural units — NOT spec-kit
on-disk concepts — keeping the parser↔sink seam clean. The optional L0
super-level sits above `repo` when enabled.

| Level | workstate origin | Ordinal | Default artifact | Default link to parent |
|-------|-----------------|---------|-----------------|------------------------|
| `l0` (narrative, optional) | narrative source | 0 | Milestone | `none` (above repo) |
| `repo` | source repo | 1 | Project | `none` (or `parent` when l0 on) |
| `spec` | spec directory | 2 | Issue | `parent` (under repo Project) |
| `phase` | task-phase | 3 | sub-issue | `parent` (under spec Issue) |
| `task` | task item | 4 | checklist | `checklist` (in-body render) |

- Levels are ordinal: `l0 > repo > spec > phase > task` (parent → child).
  `l0` is narrative-only and off by default.
- `spec→Issue` is the backward-drift anchor in EVERY mode; an enabled L0
  super-level is narrative-only and is NOT a new drift surface (FR-010).
- **DEFERRED**: a workstate-direct input seam (present in the Jira model as a
  separate input mode, §2.3) is out of scope for this port.

---

## 3. Linear artifact vocabulary

The set of artifacts a level may project to. These are fixed Linear primitives
(no availability probe needed for the four required levels).

| Artifact | Linear primitive | Notes |
|----------|-----------------|-------|
| `Project` | Linear Project | top-level container; carries its own issue list |
| `Issue` | Linear Issue | first-class issue under a Project |
| `sub-issue` | Linear Issue with `parent` set | native nesting via the `parent` field |
| `checklist` | in-body checklist sentinel | NOT a standalone artifact; rendered into the parent body as a markdown task list; keyed by workstate task identity for idempotent re-render (FR-008) |
| `Milestone` | Linear Milestone | L0 only; optional; degrades when unavailable |

**Checklist sentinel note**: `checklist` is not a Linear API type — it is a
bridge sentinel that instructs reconcile to render the level's items into the
parent artifact's body as a markdown task list. A level configured with
`artifact: "checklist"` MUST also carry `relationship_to_parent: "checklist"`;
any other relationship paired with the checklist artifact is a validation
error (FR-006 §3).

**No `Epic-link` equivalent**: Linear does not have an Epic-link primitive. The
only nesting primitive is the sub-issue `parent` field. All parent→child
hierarchy links use `parent` (or `checklist` for in-body render).

---

## 4. Relationship-validation matrix (allow/reject table)

The offline allow/reject table of (level-boundary × relationship type) that
guards against a corrupt Linear hierarchy (FR-006, FR-007). All rejections
HARD-HALT at config-load, before any write — no warn-and-continue.

### 4.1 Relationship type allow/reject

| Relationship | As a hierarchy (parent→child) link | Notes |
|--------------|-----------------------------------|-------|
| `parent` | ALLOW | native sub-issue nesting (the only nesting primitive) |
| `none` | ALLOW | top level (e.g. repo Project, or any level with no parent) |
| `checklist` | ALLOW | non-issue sentinel; in-body markdown render |
| `blocks` | REJECT | dependency semantics, not nesting |
| `relates` | REJECT | dependency semantics, not nesting |

### 4.2 Boundary-specific rejections (keyed by level × relationship)

| Level boundary | Relationship | Decision | Reason |
|---------------|-------------|----------|--------|
| `l0` (L0 → ∅) | `parent` | REJECT | L0 has no parent; `none` is the only valid link |
| `l0` | `checklist` | REJECT | Milestone is not an in-body artifact |
| `repo` (when l0 off) | `parent` | REJECT | repo is the top level; no parent when l0 is off |
| `repo` (when l0 on) | `parent` | ALLOW | repo Project nests under L0 Milestone |
| `repo` | `checklist` | REJECT | Project is not an in-body artifact |
| `spec` | `none` | REJECT | spec always has a repo parent |
| `spec` | `checklist` | REJECT | checklist sentinel is only valid at the task level (see §3) |
| `phase` | `none` | REJECT | phase always has a spec parent |
| `phase` | `checklist` | REJECT | checklist sentinel is only valid at the task level |
| `task` | `parent` | REJECT | task items render into the parent body (checklist only) |
| `task` | `none` | REJECT | task items always have a phase parent |
| any level | `blocks` | REJECT | dependency link, not nesting (FR-006) |
| any level | `relates` | REJECT | dependency link, not nesting (FR-006) |
| `checklist` artifact + any rel ≠ `checklist` | — | REJECT | checklist artifact must pair with checklist relationship |

### 4.3 Notes on offline resolution

All rejections are computed at config-load from the `mapping:` block alone —
no Linear API call is required (FR-007). The relationship matrix is fully
self-contained: Linear's single nesting primitive (`parent`) removes the
classic-vs-team-managed style ambiguity that existed in the Jira model (where
`Epic-link` vs `parent` depended on project style). As a result the matrix
resolves fully offline in every mode with zero network round-trips.

**Blocking/relating links between task phases** (inter-phase ordering, as used
by today's 001 bridge) are separate from the hierarchy-link validation and
remain available as today — they are not governed by this matrix (FR-001).

---

## 5. Identity-label prefixes

The existing 001 prefixes PLUS the synthesized `task_prefix` for task-level
artifacts when projected to a standalone sub-issue under the #17 alternative.
Each prefix yields a stable, filesystem-derived identity label so re-runs
match-and-update rather than re-create (FR-009).

| Config key | Default value | Identity for |
|-----------|--------------|--------------|
| `linear.labels.spec_prefix` | `"speckit-spec:"` | spec-level Issue (`<NNN>`) |
| `linear.labels.repo_prefix` | `"speckit-repo:"` | repo-level Project / degraded grouping (`<slug>`) |
| `linear.labels.phase_prefix` | `"task-phase:"` | phase-level sub-issue (`<N>`) |
| `linear.labels.lifecycle_prefix` | `"phase:"` | lifecycle-status grouping |
| `linear.labels.task_prefix` | `"speckit-task:"` | task-level sub-issue under #17 alternative (`<task-id>`) |

### 5.1 Identity key derivation per level

The `identity_key` is the label value that uniquely identifies a created
artifact across runs. It is **always filesystem-derived**, never minted from
Linear state.

| Level | Default artifact | Identity key derivation |
|-------|-----------------|------------------------|
| `repo` | Project | `repo_prefix` + repo slug (e.g. `speckit-repo:my-repo`) |
| `spec` | Issue | `spec_prefix` + spec number (e.g. `speckit-spec:007`) |
| `phase` | sub-issue | `phase_prefix` + phase ordinal (e.g. `task-phase:1`) |
| `task` | checklist (no standalone artifact) | keyed by task id within parent body; no label needed |

**Under the #17 spec-as-Project alternative** (spec→Project, phase→Issue,
task→sub-issue), the identity keys shift:

| Level | #17 artifact | Identity key derivation |
|-------|-------------|------------------------|
| `repo` | Project | `repo_prefix` + repo slug (unchanged) |
| `spec` | Project | `spec_prefix` + spec number — **same prefix, now on a Project** |
| `phase` | Issue | `phase_prefix` + phase ordinal — **same prefix, now on an Issue** |
| `task` | sub-issue | `task_prefix` + task id (e.g. `speckit-task:T-001`) — **new prefix** |

The `task_prefix` identity key is synthesized by the alias layer for all
configs (both default and #17 alternative) so it is always available when
needed; absence is a config error (FR-009).

### 5.2 Label validation / lifecycle notes

- `task_prefix` is REQUIRED to be present (synthesized by the alias layer) and
  is the identity key whenever a level projects to a standalone sub-issue; without
  it such sub-issues cannot be re-matched (FR-009).
- `task_prefix` MUST NOT collide with `spec_prefix` / `phase_prefix` — a
  distinct prefix keeps re-match unambiguous.
- In the degraded L0 path, repo grouping reuses `repo_prefix` (never a new
  prefix), keeping identity continuity for the idempotent re-home (§1.4).
- A Project-projected spec level (`spec→Project` under #17) uses `spec_prefix`
  on the Project entity — the same prefix, a different Linear artifact type;
  the reconcile engine selects the query path (Project vs Issue) based on the
  resolved mapping's `artifact` field, not the prefix value.

---

## 6. Narrative source (explicit spec-input origin)

The explicit origin of the L0 super-level narrative — NEVER inferred or
fabricated (FR-012).

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `source` | enum | `"spec_input"` | the only supported value |
| origin | string | spec.md `**Input**:` line | per-repo 1:1 |

### 6.1 Narrative validation / lifecycle notes

- `source` MUST be `spec_input`; any other value is a config error (FR-012).
- The narrative is populated ONLY from the spec's `**Input**:` line; it is
  never inferred, fabricated, or taken from any other field.
- If the L0 super-level is on but no `**Input**:` line is present in the spec
  (e.g. a newly created spec stub), the narrative field is left empty — it is
  not a config error, and the Milestone (or degraded grouping label) is still
  created with an empty narrative body.
- Per-org 1:many grouping is out of scope for this feature; the source ships
  per-repo 1:1.

---

## 7. Alias-layer default-synthesis rules

When no `mapping:` block is present in `linear-config.yml`, the alias layer
synthesizes the DEFAULT mapping (§1.1) from the existing binding keys. Rules:

1. **repo level**: artifact = `Project`, relationship = `none`. Derived from
   `linear.project.id` being present (any non-empty project binding ⇒ repo
   projects to Project).
2. **spec level**: artifact = `Issue`, relationship = `parent`. Default; no
   binding key signals a spec→Project override — that requires an explicit
   `mapping.levels.spec` block.
3. **phase level**: artifact = `sub-issue`, relationship = `parent`. Default;
   derived from the presence of `linear.default_state_uuids.*` (the sub-issue
   state keys the 001 bridge always populates).
4. **task level**: artifact = `checklist`, relationship = `checklist`. Default;
   no issue-type UUID needed for the checklist sentinel.
5. **L0 level**: `enabled: false`, `on_absent: degrade`, `source: spec_input`.
   Always off in the synthesized default (FR-011).
6. **`task_prefix`**: synthesized as `"speckit-task:"` regardless of whether
   the operator has set it explicitly; ensures the identity key is always
   available when a future `mapping:` block promotes task to sub-issue.
7. **Equivalence**: an explicit `mapping:` block that spells out these exact
   values MUST produce an identical resolved mapping to the synthesized default
   (alias-layer round-trip, FR-002, SC-001, SC-005).

### 7.1 Per-level inheritance rules for partial blocks

When a `mapping:` block is present but specifies only some levels:

- Each specified level is taken as-is and validated against the matrix (§4).
- Each unspecified level inherits the **synthesized default for that level**
  (not the synthesized default for any other level — inheritance is per-level,
  not cascading).
- An unspecified level is treated identically to the synthesized-default case;
  no warning is emitted.
- A partial block containing ONLY `l0:` (and no `levels:` keys) is valid;
  all four levels inherit the synthesized default.
- A partial block containing ONLY `levels:` (and no `l0:` key) is valid;
  L0 inherits `enabled: false`.

---

## 8. YAML examples

### Example A — no `mapping:` block (default behaviour)

```yaml
schema_version: 1

linear:
  team:
    id: "<UUID>"
  project:
    id: "<UUID>"
  workflow_state_uuids:
    specifying:      "<UUID>"
    clarifying:      "<UUID>"
    planning:        "<UUID>"
    tasking:         "<UUID>"
    red_team:        "<UUID>"
    implementing:    "<UUID>"
    analyzing:       "<UUID>"
    ready_to_merge:  "<UUID>"
    merged:          "<UUID>"
  default_state_uuids:
    todo:        "<UUID>"
    in_progress: "<UUID>"
    done:        "<UUID>"
  labels:
    spec_prefix:      "speckit-spec:"
    repo_prefix:      "speckit-repo:"
    phase_prefix:     "task-phase:"
    lifecycle_prefix: "phase:"
    task_prefix:      "speckit-task:"
```

The alias layer synthesizes: repo→Project/none, spec→Issue/parent,
phase→sub-issue/parent, task→checklist/checklist, L0 off.
Behaviour is byte-identical to the pre-feature bridge.

---

### Example B — #17 spec-as-Project shape

```yaml
schema_version: 1

linear:
  team:
    id: "<UUID>"
  project:
    id: "<UUID>"
  workflow_state_uuids:
    specifying:      "<UUID>"
    # ... (all nine required)
    merged:          "<UUID>"
  default_state_uuids:
    todo:        "<UUID>"
    in_progress: "<UUID>"
    done:        "<UUID>"
  labels:
    spec_prefix:      "speckit-spec:"
    repo_prefix:      "speckit-repo:"
    phase_prefix:     "task-phase:"
    lifecycle_prefix: "phase:"
    task_prefix:      "speckit-task:"
  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "parent"
      phase:
        artifact: "Issue"
        relationship_to_parent: "parent"
      task:
        artifact: "sub-issue"
        relationship_to_parent: "parent"
```

`repo` is unspecified — inherits synthesized default (Project/none).
`l0` is unspecified — inherits synthesized default (enabled: false).
Result: repo→Project/none, spec→Project/parent, phase→Issue/parent,
task→sub-issue/parent, L0 off.

---

### Example C — partial block (one-level override)

```yaml
  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "parent"
```

`repo`, `phase`, and `task` inherit the synthesized default.
`l0` inherits the synthesized default (off).
Result: repo→Project/none, spec→Project/parent, phase→sub-issue/parent,
task→checklist/checklist, L0 off.

---

### Example D — L0 narrative super-level on

```yaml
  mapping:
    l0:
      enabled: true
      artifact: "Milestone"
      on_absent: "degrade"
      source: "spec_input"
    levels:
      repo:
        artifact: "Project"
        relationship_to_parent: "parent"
      spec:
        artifact: "Issue"
        relationship_to_parent: "parent"
      phase:
        artifact: "sub-issue"
        relationship_to_parent: "parent"
      task:
        artifact: "checklist"
        relationship_to_parent: "checklist"
```

When the team supports Project Milestones: a Milestone is created above the
repo level; narrative is populated from `spec.md` `**Input**:` line only.
When Milestones are unavailable: narrative folds onto the repo Project behind
a stable marker; repo grouping carried as a label; run succeeds (no hard
failure). (FR-011, FR-012.)

---

## 9. Jira → Linear artifact parity table

Faithful port of the cross-reference parity table from spec.md §Assumptions.
The grammar (level names, field shape, alias semantics, matrix shape) is
structurally equivalent between the two sinks (FR-015, SC-007).

| workstate level | Jira artifact (default) | Linear artifact (default) | Linear #17 alternative |
|-----------------|------------------------|--------------------------|------------------------|
| L0 (narrative, off by default) | Initiative | Milestone | Milestone |
| `repo` | Epic | Project | Project |
| `spec` | Story | Issue | **Project** |
| `phase` | Subtask | sub-issue | **Issue** |
| `task` | checklist (ADF taskList) | checklist (markdown task list) | **sub-issue** |

### Relationship vocabulary parity

| Jira relationship | Linear equivalent | Status |
|------------------|------------------|--------|
| `parent` (native) | `parent` | Carried over — same semantics |
| `Epic-link` | _(none)_ | Dropped — no Epic-link analogue in Linear; `parent` covers all nesting |
| `none` | `none` | Carried over — top level |
| `checklist` | `checklist` | Carried over — in-body sentinel |
| `Blocks` | `blocks` | REJECT in both sinks |
| `Relates` | `relates` | REJECT in both sinks |
| `Implements` | _(not in Linear vocabulary)_ | REJECT (no equivalent; treated as an unknown rejected value) |

### Feature-level scoping delta (Jira spec vs this port)

| Capability | Jira `002-configurable-mapping` | This port (Linear `007-configurable-mapping`) |
|-----------|--------------------------------|----------------------------------------------|
| `--workstate` direct-input seam | In scope (§2.3) | **DEFERRED** — out of scope |
| `status_rollup` lever | In scope | **DEFERRED** — out of scope |
| Available-type detection probe | In scope (§3 of Jira model) | **NOT NEEDED** — required-level artifacts are fixed Linear primitives; no probe |
| L0 super-level | Initiative (Premium-only) | Milestone (free, narrative primitive) |
| `on_absent` policy | `degrade` (L0 only) | `degrade` (L0 only) — same |
| Relationship matrix | `parent`, `Epic-link`, `none`, `checklist`; reject `Blocks`/`Relates`/`Implements` | `parent`, `none`, `checklist`; reject `blocks`/`relates` |
