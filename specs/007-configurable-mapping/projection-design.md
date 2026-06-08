# Projection design — spec 007 US2–US4 (the `reconcile.sh` build)

This note records the design decisions for the **projection** half of spec 007
(actually creating the non-default Linear artifacts), locked before
implementation. The **config layer** (grammar + alias + fail-closed validation)
already shipped in PR #56. This note governs branch `008-mapping-projection`.

## API derisk (done — read-only, live workspace)

Confirmed against the live Linear API (read-only):

- **Initiatives are available** on the workspace and are reachable via the API
  (`initiatives` query returned live data).
- **Initiatives natively contain Projects** (`initiative.projects[]`), confirming
  the containment `Initiative > Project` the #17 shape relies on.
- `parentInitiatives[]` exists (Linear supports sub-initiatives) — not needed for
  this feature, but it confirms Initiatives are first-class.
- The MCP tool params corroborate the model: `list_projects(initiative:)` and
  `list_initiatives(includeProjects:)`.

⇒ The full containment `Initiative > Project > Issue > sub-issue` is buildable.
No blocker; the L0/#17 paths do not need the degrade path on this workspace, but
the degrade path is still required for plans without Initiatives.

## Decision 1 — Architecture: parallel projection path (not in-place refactor)

When the resolved mapping is the **default**, reconcile uses the existing,
battle-tested `process_spec` / `sync_spec_issue` / `sync_task_phase_subissues`
path **unchanged** (zero regression risk to the ~99% default case; protects the
constitutional idempotency/drift guarantees that path already satisfies).

When the resolved mapping is **non-default** (any level overridden, or L0 on),
reconcile routes to a new `reconcile::process_spec_mapped` that walks the
resolved levels (`config::resolved_artifact/relationship/identity_key`,
`config::l0_enabled`) and projects each. Shared concerns (memory block, drift,
labels, summary) are factored into helpers reused by both paths where clean.

Rationale: a full in-place generalisation of the 285-line `sync_spec_issue`
would put the default path at regression risk for a feature most repos won't
enable. A guarded parallel path keeps the default sacrosanct and lets the new
projection evolve independently. `config::resolved_*` is still the single source
of mapping truth (FR-014) — both paths read it; the engine holds no hardcoded
mapping.

## Decision 2 — Identity for non-issue levels: description marker

The existing identity model (data-model §5) keys artifacts by **issue labels**
(`speckit-spec:NNN`, `task-phase:N`). That works for Issue and sub-issue levels
but **Initiatives and Projects do not carry issue labels**. This closes that gap:

| Level / artifact | Identity mechanism |
|---|---|
| repo → **Project** (default) | the bound `linear.project.id` (config UUID) — unchanged |
| repo → **Initiative** (#17 / L0) | stable **description marker** `<!-- speckit-id: speckit-repo:<slug> -->`, matched by listing initiatives and filtering |
| spec → **Project** (#17) | stable **description marker** `<!-- speckit-id: speckit-spec:<NNN> -->`, matched by `list_projects` within the parent Initiative |
| spec → **Issue** (default) | `speckit-spec:NNN` label — unchanged |
| phase → **Issue** (#17) | `task-phase:N` label scoped to the parent Project |
| phase → **sub-issue** (default) | `task-phase:N` label + parent issue — unchanged |
| task → **sub-issue** (#17) | `speckit-task:<task-id>` label + parent issue |
| task → **checklist** (default) | in-body render keyed by task identity — unchanged |
| L0 → **Initiative** | description marker `<!-- speckit-id: speckit-repo:<slug> -->` (same as repo→Initiative; the narrative super-level and a repo-as-Initiative are the same Linear entity in the #17+L0 combination, which is rejected by the matrix — they are alternative tops, never both) |

The description marker is consistent with the bridge's existing memory-block
marker convention (a stable comment line matched on read). It is filesystem-
derived (slug / NNN), never minted from Linear state — preserving Principle II.

Idempotency: query by marker → 0 matches ⇒ create; 1 ⇒ update; >1 ⇒ resolve
duplicates (reuse the existing `resolve_or_archive_duplicates` shape, adapted to
mark losers by editing their description marker out).

## Sub-increment sequence (each green + committed before the next)

1. **Identity + GraphQL leaf helpers** (isolated, mock-tested): description-marker
   compose/extract helpers; `reconcile::query_initiative_by_marker` /
   `ensure_initiative`; `query_project_by_marker` / `ensure_project` (create +
   idempotent update), reusing `graphql::mutate` and the dry-run + summary
   conventions of `mutate_issue_create`. Unit tests via the curl-shim mock.
2. **US2 projection** — `reconcile::process_spec_mapped` for the #17 shape
   (repo→Initiative, spec→Project, phase→Issue, task→sub-issue): walk levels,
   create/link each via the resolved mapping; integration test (mock) for the #17
   shape + a zero-churn re-run.
3. **US3** — partial-inheritance end-to-end (mostly falls out of US2 + the
   resolver); one integration test.
4. **US4** — L0 Initiative super-level: `probe_initiative_support` /
   `ensure_initiative` / `degrade_initiative_onto_repo` (+ re-home); off by
   default; degrade when Initiatives absent; narrative from the spec `**Input**:`
   line only (FR-012). Integration tests (present / degrade / off).
5. **Polish** — README (now safe to document the working feature), setup
   fixtures, `no-real-identifiers` over new fixtures, all gates green, PR.

## Invariants (unchanged in every sub-increment)

Idempotency, drift-awareness (spec level stays the sole anchor; L0 is not a new
drift surface), fail-closed writes, `extension.id = linear`, no real coordinates
in tracked files, `--severity=style` shellcheck, ubuntu-CI authoritative.
