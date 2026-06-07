# Feature Specification: Team-scoped / non-admin seeding

**Feature Branch**: `005-team-scoped-seeding`

**Created**: 2026-06-07

**Status**: Draft

**Input**: User description: "Make seeding usable by sub-team owners who lack
workspace-admin rights. Today seeding creates per-team workflow states AND
workspace-scoped labels, both of which require workspace-admin permissions, so in
larger orgs a sub-team owner cannot seed and the extension is unusable for them
(issue #41). Add a team-scoped seed mode (team-scoped labels), an adopt-existing
path that captures already-present states/labels into config instead of creating
them, and graceful permission-error handling that points operators at the adopt
path — while preserving idempotency and the existing UUID-capture-into-config
behaviour."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A sub-team owner seeds without workspace-admin (Priority: P1)

A sub-team owner installs the extension. They have team-level permissions but not
workspace-admin. Seeding completes by creating the workflow states and labels
**scoped to their team** — never touching workspace-wide resources — and captures
every UUID into config, so the bridge is fully usable for that team.

**Why this priority**: This is the core defect (#41). Today every seed run
requires workspace-admin (workflow-state creation and workspace-scoped label
creation both need it), so sub-teams in larger orgs cannot use the extension at
all. Making a non-admin team owner able to seed is the whole point of the feature.

**Independent Test**: Run a seed as an operator holding only team-level
permissions (no workspace-admin) with team scope selected, and confirm the
workflow states and labels are created scoped to that team, every UUID is
captured into config, and no workspace-level mutation is attempted.

**Acceptance Scenarios**:

1. **Given** an operator with team-level permissions only and team scope selected,
   **When** seeding runs, **Then** the workflow states and labels are created
   scoped to that team and all UUIDs are captured into config, with no
   workspace-scoped create attempted.
2. **Given** a successful team-scoped seed, **When** the resulting config is
   inspected, **Then** it contains the full set of workflow-state and label UUIDs
   the bridge needs, identical in shape to a workspace-scoped seed.

---

### User Story 2 - A non-admin operator adopts resources an admin already created (Priority: P1)

An admin (or a previous run) has already created the required workflow states and
labels. A non-admin operator runs seeding; instead of trying to create anything,
the tool finds the existing states and labels by name, **captures their UUIDs into
config**, and finishes. No create permission is needed.

**Why this priority**: This is the second half of #41. Even team-scoped creation
needs *some* create permission; the adopt path lets an operator who cannot create
resources become productive by reusing what already exists. It is also the safe
landing zone the permission-error path (US3) points to.

**Independent Test**: Pre-create the required states and labels, then run seeding
as an operator who cannot create resources; confirm the run captures the existing
UUIDs into config, reports them as adopted (not created), and exits successfully
without any create mutation.

**Acceptance Scenarios**:

1. **Given** all required workflow states and labels already exist and adopt mode
   is active, **When** seeding runs, **Then** every UUID is captured into config,
   each is reported as adopted, and no create mutation is issued.
2. **Given** some required resources exist and others are missing while adopt-only
   is in effect, **When** seeding runs, **Then** the existing ones are adopted and
   the missing ones are reported clearly as not-found (with the names), without a
   cryptic failure.

---

### User Story 3 - A permission/limit error becomes an actionable next step (Priority: P1)

An operator runs seeding and a create call fails with a permission or limit error
(the situation rcollette hit). Instead of a cryptic hard-fail, the tool surfaces a
clear message naming the resource that failed and pointing to the adopt-existing
path (and the team-scoped option) as the way forward.

**Why this priority**: The reported symptom in #41 is exactly an opaque API
permission/limit error that leaves the operator stuck. Turning that dead-end into
a signposted recovery path is what makes the feature usable in practice, not just
in theory.

**Independent Test**: Force a create call to return a permission/limit error and
confirm the tool emits a message that (a) names the resource and the failure kind
and (b) explicitly directs the operator to the adopt-existing / team-scoped path,
rather than a raw API error or stack dump.

**Acceptance Scenarios**:

1. **Given** a create call returns a permission or limit error, **When** seeding
   handles it, **Then** the operator sees a message naming the failed resource and
   the failure kind and pointing at the adopt-existing path.
2. **Given** the same permission error during a workspace-scoped attempt, **When**
   the operator re-runs with team scope or adopt mode as directed, **Then**
   seeding proceeds along that path without re-hitting the same hard-fail.

---

### User Story 4 - Scope is selectable and auto-detects sensibly (Priority: P2)

An operator chooses the seed scope (workspace or team) via config, or lets the
tool auto-detect: it attempts the configured/default scope and, on a
permission/limit failure, falls back to adopting existing resources rather than
aborting. The chosen scope is honoured and recorded so re-seeds are consistent.

**Why this priority**: A single hardcoded scope is what broke sub-teams. Making
scope a first-class, explicitly selectable option (with a safe auto-fallback)
generalises the fix beyond the one reported org shape, but it builds on the P1
mechanics (team scope, adopt path) and so is P2.

**Independent Test**: Set the scope option to `team`, run seeding, and confirm
team-scoped behaviour; set it to `workspace` and confirm workspace-scoped
behaviour; then with auto-detect, force a permission failure on the primary scope
and confirm the run falls back to adopt-existing instead of aborting.

**Acceptance Scenarios**:

1. **Given** the scope option set to `team`, **When** seeding runs, **Then** it
   uses team-scoped behaviour; **given** it set to `workspace`, **Then** it uses
   workspace-scoped behaviour.
2. **Given** auto-detect and a permission/limit failure on the primary scope,
   **When** seeding runs, **Then** it falls back to adopting existing resources and
   reports the fallback, rather than aborting.

---

### Edge Cases

- **Duplicate resources by name** (two workflow states or two labels with the same
  name in the team/workspace the adopt path searches): the tool MUST NOT guess —
  it surfaces a clear ambiguity warning naming the duplicates and skips that
  resource rather than capturing an arbitrary UUID.
- **Partial pre-existing set in adopt mode**: some required resources exist and
  some do not — existing ones are adopted, missing ones are reported by name; the
  run does not silently capture a partial config as if complete.
- **Mixed creatability**: the operator can create labels but not workflow states
  (or vice versa) — each resource family is handled on its own merits (create what
  it can, adopt/report what it cannot), not gated all-or-nothing on a single
  permission check.
- **Re-seed after a team-scoped or adopt seed**: a second run observes the
  resources already exist (by UUID/name) and captures/keeps the same UUIDs,
  emitting zero `created` events — idempotency holds across all scopes and paths.
- **Team-scoped resources later promoted to workspace scope (or vice versa)**: the
  captured UUIDs remain valid bindings regardless of a resource's scope; seeding
  re-binds by the resource's current identity rather than failing on a scope
  mismatch.
- **Adopt mode with nothing pre-existing and no create permission**: the tool
  exits with a clear, actionable message listing every required resource that
  could be neither created nor adopted (so an admin knows exactly what to create
  once), not a cryptic failure.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Seeding MUST support a **team-scoped** mode in which both workflow
  states and labels are created scoped to the configured team (the team identifier
  is supplied to label creation, not only to workflow-state creation), so an
  operator with team-level permissions can seed without workspace-admin.
- **FR-002**: Seeding MUST support an **adopt-existing** path that, when a required
  workflow state or label already exists, captures its UUID into config instead of
  attempting to create it — requiring no create permission for adopted resources.
- **FR-003**: The adopt-existing path MUST match required resources by their
  canonical name (the same names a create run would use) within the relevant scope,
  and MUST capture the resulting UUIDs into config in the same shape as a
  create-based seed.
- **FR-004**: When a create call fails with a permission or limit error, the tool
  MUST surface a clear, actionable message that names the affected resource and the
  failure kind and explicitly points the operator to the adopt-existing path (and
  the team-scoped option) — it MUST NOT emit only a raw API error or hard-fail
  cryptically.
- **FR-005**: Seed scope MUST be selectable via a configuration option with values
  `workspace` and `team`; the tool MUST honour the selected scope.
- **FR-006**: The tool MUST support auto-detection that attempts the
  configured/default scope and, on a permission/limit failure, falls back to
  adopting existing resources rather than aborting, reporting which path it took.
- **FR-007**: Seeding MUST remain idempotent across all scopes and paths: a re-run
  against an already-seeded team/workspace MUST capture/keep the same UUIDs and
  emit zero `created` events.
- **FR-008**: The existing UUID-capture-into-config behaviour MUST be preserved
  unchanged — every workflow-state and label UUID the bridge depends on MUST be
  written to config in the same shape regardless of whether it was created or
  adopted, and regardless of scope.
- **FR-009**: Neither the team-scoped path nor the adopt-existing path may require
  workspace-admin permissions; the only permission either requires is what that
  specific path actually uses (team-level create for team scope, none for adopt).
- **FR-010**: When the adopt-existing path finds two or more resources matching a
  required name, the tool MUST NOT capture an arbitrary UUID; it MUST surface an
  ambiguity warning naming the duplicates and skip that resource.
- **FR-011**: When required resources can be neither created (no permission) nor
  adopted (not present), the tool MUST exit with a clear message listing every
  such resource by name, so an admin knows exactly what to provision once.
- **FR-012**: Each resource family (workflow states, labels) MUST be handled
  independently — the tool creates what it can and adopts/reports the rest per
  family, rather than gating the whole run on a single permission outcome.
- **FR-013**: The workspace-scoped behaviour that exists today MUST remain
  available and unchanged when `workspace` scope is selected, so current installs
  are not disrupted.
- **FR-014**: All existing safety guarantees — idempotency, drift-awareness,
  fail-closed writes, and the dry-run preview — MUST continue to hold across the
  new scopes and paths.
- **FR-015**: Documentation MUST describe the scope option, the adopt-existing
  path, and the non-admin seeding story, including which permissions each path
  requires.

### Key Entities *(include if feature involves data)*

- **Seed scope**: the selected breadth of seeding — `workspace` (workspace-wide
  resources, requires workspace-admin) or `team` (resources scoped to the
  configured team, requires only team-level permissions). Recorded in config.
- **Required resource set**: the workflow states and labels the bridge depends on,
  each identified by a canonical name; the unit that is either created or adopted
  and whose UUID is captured into config.
- **Adopt-existing match**: the association of a required resource name to an
  already-present Linear resource's UUID, captured into config in place of a
  create — the basis of the no-create-permission path.
- **Permission/limit outcome**: the classification of a failed create call as a
  permission or limit error, which drives the actionable message and the
  auto-detect fallback to the adopt path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator with team-level permissions only (no workspace-admin)
  completes a seed in team scope and ends with a complete, bridge-usable config —
  0 workspace-admin permissions required.
- **SC-002**: With all required resources pre-existing, an operator who cannot
  create resources completes seeding via the adopt path with 100% of required
  UUIDs captured and 0 create mutations issued.
- **SC-003**: Every create call that fails with a permission/limit error produces
  an actionable message that names the resource and points to the adopt/team-scoped
  path — 0 cryptic hard-fails for that error class.
- **SC-004**: Re-seeding in any scope or path against an already-seeded
  team/workspace emits 0 `created` events (idempotency preserved).
- **SC-005**: A captured config from a team-scoped or adopt run is identical in
  shape to one from a workspace-scoped create run — the same set of workflow-state
  and label UUID bindings, verifiable by comparing the captured key set.
- **SC-006**: The documented permission requirements for each path (workspace,
  team, adopt) are internally consistent across README and the config template —
  no claim that a path needs admin when it does not.

## Assumptions

- Linear's label-creation contract accepts a team identifier to produce a
  team-scoped label; supplying it yields a label visible to that team and
  creatable with team-level (not workspace-admin) permissions. Exact field names
  are an implementation detail for the plan.
- The canonical names used to create resources are stable and unique enough to
  serve as the adopt-existing match key within a scope; genuine duplicates are the
  documented ambiguity edge case (FR-010), not the norm.
- Default scope, when the operator sets nothing, is `team` with auto-fallback to
  adopt-existing — the configuration that makes the broadest set of operators
  (including non-admins) succeed; an operator can still pin `workspace` explicitly.
- "Permission or limit error" is detectable from the tracker's error response well
  enough to classify it and trigger the actionable message / fallback; ambiguous
  failures fall through to the existing fail-closed behaviour rather than being
  misclassified as adoptable.
- Adopt mode searches the scope implied by the selected seed scope (team scope
  searches the team's resources; workspace scope searches workspace-visible
  resources); cross-scope discovery beyond that is out of scope for this feature.
- This feature changes only seeding scope/permissions and resource
  discovery/capture; it adds no new tracker capability and does not alter the
  spec→Issue→sub-issue mapping or the runtime reconcile/drift behaviour.
- The config/identity split (spec 004) and drift-aware authority (spec 003) are
  unchanged by this feature; captured UUIDs continue to live in the shared,
  committable binding exactly as those specs define.
