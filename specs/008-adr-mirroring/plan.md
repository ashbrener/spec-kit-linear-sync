# Implementation Plan: ADR / Decision-Record Mirroring

**Branch**: `008-adr-mirroring` | **Date**: 2026-06-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-adr-mirroring/spec.md`

## Summary

Mirror each spec's architecture/decision records — the
`Decision / Rationale / Alternatives` blocks in its `research.md` — as
at-most-once comments on that spec's Linear Issue (Option A). This is a near-clone
of the existing clarify-session comment path: a new `parser::adr_records` reads
the decision blocks; a new `reconcile::sync_adr_comments` renders one ADR comment
per decision keyed by a stable hidden marker and reconciles it idempotently. The
only behavioural difference from the clarify path is **update-in-place** when a
decision's content changes on disk (FR-005) — which the clarify path does not do
(it warns-don't-overwrite) — so a small `reconcile::mutate_comment_update`
(`commentUpdate`) is added. The Linear bridge has no workstate floor, so no
schema change is required; the user-visible shape is parity-locked with the
spec-kit-jira ADR feature (FR-009).

## Technical Context

**Language/Version**: Bash (CI matrix: bash 4.4 + 5.2; ubuntu authoritative over
macOS for GNU/BSD differences)

**Primary Dependencies**: `jq` (JSON), `curl` (Linear GraphQL API) — **no new
runtime dependencies**. Uses the existing `graphql::query`/`graphql::mutate`
transport and the existing comment query/create helpers.

**Storage**: none — reads `research.md` from the consumer repo's filesystem;
writes only Linear comments. No config or schema change.

**Testing**: `bats` (unit); `shellcheck --shell=bash --severity=style`;
`yamllint`; `markdownlint-cli2`. Offline (stubbed transport) for the new logic.

**Target Platform**: macOS + Linux (CI: ubuntu-latest + macos-latest)

**Project Type**: single-project CLI / reconcile sync engine

**Performance Goals**: not latency-bound — correctness-bound; zero-churn
idempotent re-runs (SC-002).

**Constraints**: idempotency, drift-awareness, and fail-closed writes hold
(constitutional); ADRs are non-task artifacts → spec-Issue comments (the
constitutional data-model); `extension.id` stays `linear` and the command surface
is unchanged (FR-011); no real Linear coordinates in tracked files (FR-012);
user-visible parity with the spec-kit-jira ADR feature (FR-009).

**Scale/Scope**: per spec, a handful of decision blocks; a comment per decision.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution **v2.1.0**. All eight principles hold; this feature is **additive**
and needs **no amendment** — the data-model already maps non-task artifacts to
spec-Issue comments.

| Principle | Verdict | Why |
|---|---|---|
| I Filesystem is the source of truth | PASS | `research.md` on disk is canonical; the ADR comment is a unidirectional mirror. Update-in-place (FR-005) IS Principle I — "operator-side mutations in Linear … the next reconcile overwrites them"; the comment is re-asserted from disk on divergence. |
| II Reconcile, never event-push | PASS | Each reconcile reads full `research.md` state and converges; identity is filesystem-derived (the decision key), never a sidecar. |
| III Layered idempotency (D + E) | PASS | A Layer-D concern only (comments); Layer E is untouched. At-most-once per ADR keyed by a hidden marker; unchanged corpus = zero churn (SC-002). |
| IV Write-authority follows the filesystem (drift-aware) | PASS | Runs inside the existing per-spec reconcile after the spec Issue is resolved; the spec-level drift anchor is unchanged. ADR comments are not a new drift surface. |
| V UUID-based binding, per-repo config | PASS | No new config or binding; reuses the resolved spec Issue. |
| VI OAuth-first, keys-at-the-edges | PASS | No new credential surface; reuses the existing comment transport. |
| VII Memory-just-works | PASS | Additive on the existing `after_*` reconcile path; no new command, no hook change (FR-011). |
| VIII Surface, don't enforce — observable failure | PASS | A spec with no `research.md`/no decisions is a graceful no-op (FR-007); failures are summarized; canonical vocabulary preserved. |
| Architectural Constraints (data-model: non-task artifacts → spec-Issue comments) | PASS | ADRs are non-task artifacts and map to spec-Issue comments — exactly the constitutional mapping. No data-model change. |

**Post-design re-check (after Phase 1)**: re-evaluated **PASS**. `data-model.md`
and `contracts/` keep all logic on the parser + reconcile layer (one reader, one
sync function, one `commentUpdate` wrapper) with no config/schema change and no
new Linear entity; ADR comments remain a non-task artifact on the spec Issue
(the constitutional mapping). The only new write is `commentUpdate` for
update-in-place, which is Principle I (filesystem wins). No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/008-adr-mirroring/
├── plan.md          # this file
├── research.md      # Phase 0 — decisions (parse grammar, keying, update-in-place)
├── data-model.md    # Phase 1 — ADR entity, identity key, comment shape
├── quickstart.md    # Phase 1 — operator-facing: what shows up + when
├── contracts/       # Phase 1 — research.md ADR grammar + ADR-comment contract
├── checklists/requirements.md
└── tasks.md         # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
├── parser.sh        # + parser::adr_records <spec_dir> — parse research.md
│                    #   `## D<N>/R<N> — Title` blocks (Decision/Rationale/
│                    #   Alternatives bullets) into one record per ADR; key =
│                    #   heading id else title slug (+ positional suffix for
│                    #   same-title un-headed collisions); graceful when absent
├── reconcile.sh     # + reconcile::sync_adr_comments <spec_issue_id> <spec_dir>
│                    #   — near-clone of sync_clarify_comments: render one ADR
│                    #   comment per decision with a `<!-- spec-kit-linear: adr
│                    #   <NNN>-<key> -->` marker; create when absent, skip when
│                    #   the body matches, UPDATE IN PLACE when it differs.
│                    # + reconcile::mutate_comment_update <comment_id> <body>
│                    #   — commentUpdate (the one new mutation; clarify path
│                    #   only creates). Wired into process_spec after
│                    #   sync_clarify_comments.
└── graphql.sh, summary.sh, …   # unchanged (reuse query_existing_comment_body,
                                 # which already returns {id, body})

tests/
├── unit/            # parser::adr_records grammar (headed/un-headed/missing
│                    #   subpart/collision); sync_adr_comments create / skip-
│                    #   unchanged / update-on-change / zero-churn (stubbed
│                    #   transport); mutate_comment_update dry-run + shape
└── integration/     # (optional) end-to-end ADR-comment reconcile over the mock
```

**Structure Decision**: A single-project **additive** extension of the 001
bridge — no new modules, no config/schema change. The new logic lives in
`parser.sh` (one reader) and `reconcile.sh` (one sync function + one mutation
wrapper), reusing the existing comment query/create machinery. The clarify-
session path is the template; the only delta is update-in-place via
`commentUpdate`.

## Complexity Tracking

> No constitution violations — this section is intentionally empty.
