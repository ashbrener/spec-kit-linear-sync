# Feature Specification: Config / identity split

**Feature Branch**: `004-config-identity-split`

**Created**: 2026-06-07

**Status**: Draft

**Input**: User description: "Split the per-repo Linear binding from the per-operator identity so the shared binding can be committed safely while each operator's identity stays local (issues #38, #20)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A collaborator inherits the binding without inheriting an identity (Priority: P1)

A teammate clones a repo that already has the extension set up. The committed
config gives them the team/project binding so sync works immediately, but issues
they create are attributed to **them**, not to whoever first installed the
extension — and the original installer's personal Linear details are nowhere in
the repo.

**Why this priority**: This is the core defect (#38). Today the committed config
either leaks the installer's identity or mis-attributes everyone's issues to that
one person. Fixing it is the whole point of the feature.

**Independent Test**: Clone a repo containing a committed `linear-config.yml`,
supply a *different* operator identity locally, run a reconcile, and confirm the
created issues are assigned to the local operator (not the original installer),
with no operator-identifying data present in any committed file.

**Acceptance Scenarios**:

1. **Given** a committed `linear-config.yml` with the team/project binding and no
   identity, **When** a second operator supplies their own identity locally and
   reconciles, **Then** issues are assigned to that second operator.
2. **Given** a repo set up with this feature, **When** the committed files are
   inspected, **Then** they contain no operator `user_id`, name, or email.

---

### User Story 2 - Installing never commits my identity or key (Priority: P1)

An operator installs the extension. Their personal identity and API key are
written only to local, gitignored locations; the install guarantees those
locations are ignored so a later `git add -A` cannot accidentally publish them.

**Why this priority**: Prevents the leak at the source and removes the
docs-vs-`.gitignore` contradiction.

**Independent Test**: Run the install in a fresh repo; confirm the shared config
is created and tracked, the operator-local identity file is created and matched
by `.gitignore`, and `git status` never shows the identity file as
untracked-but-stageable.

**Acceptance Scenarios**:

1. **Given** a fresh repo, **When** install runs, **Then** `linear-config.yml`
   exists and is committable, and an operator-local identity file exists and is
   covered by `.gitignore`.
2. **Given** an install that finds no `.gitignore` entry for the local file,
   **When** install runs, **Then** it adds the entry (does not silently skip).

---

### User Story 3 - Existing single-file configs keep working (Priority: P2)

An operator upgrades a repo whose `linear-config.yml` still has `operator.*`
keys baked in. Nothing breaks: the tool notices the old shape, moves the identity
into the operator-local file with a one-time notice, and continues.

**Why this priority**: There are existing installs (real users). A migration that
breaks them is unacceptable.

**Independent Test**: Take a pre-split config with `operator.*` populated, run
reconcile/install once, and confirm it still works, emits a single migration
notice, and afterwards the committed config no longer carries the identity.

**Acceptance Scenarios**:

1. **Given** a legacy `linear-config.yml` with `operator.*` keys, **When** the
   tool runs, **Then** it works, surfaces exactly one migration notice, and moves
   the identity into the operator-local file.
2. **Given** an already-migrated repo, **When** the tool runs again, **Then** no
   further migration notice appears (idempotent).

---

### User Story 4 - Identity and key resolve across worktrees without copying files (Priority: P2)

An operator running multiple worktrees reconciles from any of them. Identity and
API key resolve through a documented cascade (environment → operator-local file →
interactive prompt), so a per-worktree `.env` copy is no longer required.

**Why this priority**: Removes the worktree `.env` pain (#20) and makes the
local-only model practical day to day.

**Independent Test**: From a linked worktree with the key/identity available via
the environment (or a discoverable local file), reconcile succeeds without a
per-worktree `.env`.

**Acceptance Scenarios**:

1. **Given** `LINEAR_API_KEY` set in the environment, **When** reconcile runs in a
   worktree with no local `.env`, **Then** it authenticates and syncs.
2. **Given** an operator-local identity file but no identity env vars, **When**
   reconcile runs, **Then** the assignee resolves from that file.

---

### Edge Cases

- **No identity resolves at all** (no env, no local file, non-interactive): the
  bridge proceeds and **warns**, creating issues with no assignee, rather than
  failing the sync (assignment is best-effort; sync correctness is not gated on it).
- **Identity present in both env and local file**: the cascade order wins
  (environment takes precedence over the local file).
- **Legacy config committed with identity AND a local file already present**: the
  local file is authoritative; the committed `operator.*` keys are treated as
  legacy and removed on migration, with the notice.
- **Operator-local file exists but is malformed**: surface the same kind of clear
  diagnostic the config loader now emits (no silent failure).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `linear-config.yml` MUST contain only the shareable binding (team
  id, project id, `workflow_state_uuids`, `default_state_uuids`,
  `agent_label_uuids`, behaviour toggles) and MUST be safe to commit.
- **FR-002**: Operator identity (`user_id`, name, email) MUST be stored in a
  separate operator-local file that is never committed.
- **FR-003**: The install ceremony MUST scaffold the operator-local identity file
  and MUST ensure it is gitignored, adding the `.gitignore` entry if absent.
- **FR-004**: `linear-config.yml` MUST be committed (the docs, the template, and
  `.gitignore` MUST agree that it is tracked) — resolving the current contradiction.
- **FR-005**: The reconcile path MUST resolve the operator assignee via the
  cascade environment → operator-local file → interactive prompt, and MUST NEVER
  read operator identity from the committed config.
- **FR-006**: API-key resolution MUST follow the same documented cascade
  (environment → operator-local file/`.env` → interactive prompt), so a
  per-worktree `.env` copy is not required when the key is available higher in the
  cascade.
- **FR-007**: The tool MUST keep working when it encounters a legacy
  `linear-config.yml` containing `operator.*` keys: it MUST emit exactly one
  migration notice and move the identity into the operator-local file, and the
  migration MUST be idempotent (no repeat notice on subsequent runs).
- **FR-008**: Documentation (README, config template) MUST describe the two-file
  model and state explicitly which file is committed and which is local.
- **FR-009**: All existing safety guarantees — idempotency, drift-awareness, and
  fail-closed writes — MUST continue to hold unchanged.
- **FR-010**: `extension.id` MUST remain `linear`; the command surface
  (`/speckit.linear.*`) MUST be unchanged.
- **FR-011**: When no operator identity resolves in a non-interactive run, the
  bridge MUST proceed and warn (creating issues without an assignee), not fail.

### Key Entities *(include if feature involves data)*

- **Shared binding** (`linear-config.yml`, committed): the team/project UUIDs,
  workflow-state and label UUID maps, and behaviour toggles — everything a
  collaborator needs to inherit, none of it personal.
- **Operator-local identity** (gitignored local file): the per-person `user_id`,
  name, and email used for issue assignment and provenance.
- **Resolution cascade**: the documented precedence (environment → operator-local
  file → interactive prompt) used for both identity and API key.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A repo cloned by a second operator (with their own local identity)
  produces issues assigned to that operator — 0 issues mis-attributed to the
  original installer.
- **SC-002**: 0 occurrences of operator-identifying data (`user_id`, email) in any
  committed file, verifiable by a content scan of the tracked tree.
- **SC-003**: 100% of existing pre-split configs continue to work after upgrade,
  with exactly one migration notice and identity relocated to the local file.
- **SC-004**: Reconcile succeeds from a second worktree with no per-worktree
  `.env`, when the key/identity are available via the environment or a
  discoverable local file.
- **SC-005**: The documented commit policy (`linear-config.yml` committed; identity
  local) is internally consistent across README, config template, and `.gitignore`
  — no remaining contradiction.

## Assumptions

- The operator-local identity file lives alongside the shared config under
  `.specify/extensions/linear/` (a `*.local.*` name matched by a single
  `.gitignore` entry); exact filename is an implementation detail for the plan.
- The environment variable remains the highest-precedence source for both key and
  identity (CI / ephemeral overrides), matching the existing `LINEAR_API_KEY`
  behaviour.
- Migration is one-way: once identity is moved to the local file, the committed
  config's `operator.*` keys are removed.
- Issue assignment is best-effort; sync correctness does not depend on an assignee
  resolving (FR-011), so the feature never blocks a sync purely on missing identity.
- This is a configuration / security-model change only; it adds no new tracker
  capability and does not alter the spec→Issue→sub-issue mapping.
