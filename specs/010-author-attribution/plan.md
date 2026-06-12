# Implementation Plan: Author-Based Attribution

**Branch**: `010-author-attribution` | **Date**: 2026-06-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-author-attribution/spec.md`

## Summary

Make each spec's Linear Issue reflect **who authored the spec** instead of who
ran the sync. Two tracks, both opt-in (`linear.attribution.*`, default OFF):

1. **Authorship label** — always stamp `author:<handle>` on the spec Issue
   (account-independent; works for non-members). Applied by the existing
   strip-and-set label hygiene (the `phase:*` / `speckit-spec:NNN` pattern).
2. **Author assignee** — re-point the existing FR-034 create-time `assigneeId`
   from the operator to the resolved author, **only when** the author maps to a
   Linear user, and **only on create** (the never-clobber-on-update invariant is
   already in place). Unresolved author → **unassigned** (clarified 2026-06-11),
   never an operator fallback.

Author resolution is filesystem-derived (Principle I): an explicit
`**Owner:**`/`**Author:**` line in `spec.md` wins, else the first git author to
add the spec directory, else *unknown* (graceful no-op). Author→Linear-user
mapping resolves **dynamically** by matching the author email against the
workspace `users` connection at runtime (cached per run); an **optional**
gitignored `linear-authors.local.yml` provides aliasing (git-email ≠ Linear-
email) and handles for non-members. This is the key divergence from the
spec-kit-jira sibling (whose static map is *mandatory* because Jira's email
search is GDPR-restricted) — the **user-visible shape is parity-locked** (same
`author:<handle>` label, same author-as-assignee-on-create, same Owner-then-git
resolution), the internal mechanism differs, exactly as spec 008 did for ADRs.

## Technical Context

**Language/Version**: Bash (CI matrix: bash 4.4 + 5.2; ubuntu authoritative over
macOS for GNU/BSD differences)

**Primary Dependencies**: `jq` (JSON), `curl` (Linear GraphQL) — **no new runtime
dependencies**. Reuses `graphql::query`/`graphql::mutate`, the existing label
resolve/apply machinery (`reconcile::_resolve_label_id`,
`reconcile::_resolve_label_ids_array`), the create-time assignee call sites
(`reconcile::_resolve_operator_assignee_id`), the config parser
(`config::_parse_file`), and the spec-004 operator-local-file model.

**Storage**: none new — reads `spec.md` + git history from the consumer repo's
filesystem; an OPTIONAL gitignored `linear-authors.local.yml` (mirrors the spec-
004 `linear-operator.local.yml` model). Writes only Linear labels + (on create)
assignee. Additive `linear.attribution.*` config block, default OFF.

**Testing**: `bats` (unit, stubbed transport); `shellcheck --shell=bash
--severity=style`; `yamllint`; `markdownlint-cli2`. Integration gated by the
existing `RUN_INTEGRATION_TESTS=0` default.

**Target Platform**: macOS + Linux (CI: ubuntu-latest + macos-latest)

**Project Type**: single-project CLI / reconcile sync engine

**Performance Goals**: not latency-bound — correctness-bound; zero-churn
idempotent re-runs (SC-003). The `users` roster is fetched at most once per
reconcile (cached), independent of spec count.

**Constraints**: idempotency, drift-awareness, fail-closed writes hold
(constitutional); attribution is opt-in and default-OFF behaviour is byte-for-
byte today's (FR-015 / SC-005); author derives only from filesystem (Principle
I); no real email/UUID in any tracked file and no raw email in a label (FR-005 /
FR-011 / SC-006); `extension.id` stays `linear`, command surface unchanged
(FR-017); user-visible parity with the spec-kit-jira author-attribution feature.

**Scale/Scope**: per repo, a handful to a few dozen specs; one author per spec;
one workspace `users` fetch per run (paginated).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution **v2.1.0**. All eight principles hold; this feature is **additive
and opt-in** and needs **no amendment**. It introduces no new mapping (the
`author:*` label is additive metadata in the existing label namespace alongside
`phase:*` / `speckit-spec:NNN` / `agent:*`), and it changes only *which user* is
the create-time assignee — a spec-001 FR-034 behaviour, not a constitutional
rule — and only when explicitly enabled.

| Principle | Verdict | Why |
|---|---|---|
| I Filesystem is the source of truth | PASS | Author is resolved from `spec.md` (`Owner:` line) or git history — filesystem-evident, never from Linear. The `author:*` label is strip-and-set (operator label edits are overwritten — squarely Principle I). The **create-only assignee** is the *existing* FR-034 carve-out (assignee set on create, never re-asserted on update so manual reassignment persists); this feature does not widen that carve-out, it only changes the create-time value, opt-in. No Linear→filesystem flow. |
| II Reconcile, never event-push | PASS | Each run reads full `spec.md` + git state and converges; author identity derives from filesystem-evident keys (Owner line / first-add commit), never a sidecar cache. Unchanged corpus = zero churn (SC-003). |
| III Layered idempotency (D + E) | PASS | A Layer-D concern only (labels + create-time assignee). Layer E (workflow-state flips) is untouched and gains no author logic. Strip-and-set label + create-only assignee keep re-runs churn-free. |
| IV Write-authority follows the filesystem (drift-aware) | PASS | Runs inside the existing per-spec reconcile after the spec Issue is resolved; introduces no new drift surface and no new write gate. |
| V UUID-based binding, per-repo config | PASS | No new committed *binding*. Author→user is a **runtime lookup** matched by **email** (a stable identifier, not a cosmetic name) resolving to a UUID; the optional override pins a UUID when email is ambiguous. Identity data (emails/UUIDs) lives in the gitignored operator-local-style file per the spec-004 precedent, never in committed config. |
| VI OAuth-first, keys-at-the-edges | PASS | The `users` query rides the existing transport (interactive → MCP OAuth; seed/CI → the existing key). No new credential surface. Layer E (the Action) is untouched, so CI gains no attribution credential need. |
| VII Memory-just-works | PASS | Additive on the existing `after_*` reconcile path; no new command, no hook change (FR-017). Opt-in config; absent block = today's behaviour. |
| VIII Surface, don't enforce — observable failure | PASS | Unknown author / non-member → graceful no-op (no halt; FR-002/FR-012) with an INFO summary row naming the author + source (FR-003). Identity-leak guard fails closed. Canonical vocabulary (`author:<handle>` label). |
| Architectural Constraints (data-model; layers; no backend) | PASS | The frozen zero-config mapping is unchanged — `author:*` is additive label metadata, not a redefinition. Assignee source change is opt-in and does not touch the mapping. No hosted backend/daemon/db; state stays in filesystem + Linear + (gitignored) operator-local file. |

**Post-design re-check (after Phase 1)**: re-evaluated **PASS**. `data-model.md`
and `contracts/` keep all logic on the parser + config + reconcile layers (author
resolver, users-roster resolver, label strip-and-set clone, create-time assignee
re-point) with an additive, default-OFF config block and a gitignored override
file modelled on spec 004. No new Linear entity, no mapping change, no new
command, no Layer-E change. The only assignee semantics touched are the existing
FR-034 create-only carve-out. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/010-author-attribution/
├── plan.md          # this file
├── research.md      # Phase 0 — author resolution, users query, override model, fallback
├── data-model.md    # Phase 1 — entities: resolved author, handle, override map, config block
├── quickstart.md    # Phase 1 — operator-facing: enabling attribution + what shows up
├── contracts/       # Phase 1 — config schema delta, author-resolution + users-query + label contract
│   ├── attribution-config.md
│   └── author-resolution-and-projection.md
├── checklists/requirements.md
└── tasks.md         # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
├── parser.sh        # + parser::spec_owner_line <spec_md>     — extract **Owner:**/**Author:** value
│                    # + parser::spec_git_first_author <spec_dir> — first git author email to add the dir
│                    # + parser::resolve_author <spec_dir> <spec_md> — composite: owner→git→unknown,
│                    #   emits `<identity>\t<source>` (source ∈ owner_line|git_first_add|unknown);
│                    #   readonly awk program, graceful when absent (no error)
├── config.sh        # + linear.attribution.* accessors (default-OFF):
│                    #   config::attribution_enabled / _assignee / _label /
│                    #   config::attribution_source_order / config::authors_file_path /
│                    #   config::attribution_subissue_label
│                    # + config::load_authors_override <path> → CONFIG_AUTHORS_* (gitignored map;
│                    #   email→handle, email→linear_user_id|null); graceful absent
├── reconcile.sh     # + reconcile::_resolve_workspace_users  — one paginated `users` fetch, cached
│                    #   in a module global; email→{id,active} index (case-insensitive)
│                    # + reconcile::_resolve_author_user <email> — override-map first, else roster;
│                    #   returns UUID | "" (non-member/unknown)
│                    # + reconcile::_author_handle <identity> — override handle else email local-part,
│                    #   sanitized to a label-safe non-PII token; never a raw email
│                    # ~ spec-Issue label computation — strip `author:*`, add resolved `author:<handle>`
│                    #   (clone of the phase:* strip-and-set at the spec-update site)
│                    # ~ create-time assignee — when attribution ON: author UUID if resolvable else
│                    #   OMIT (unassigned); when OFF: operator per FR-034 (unchanged). Update path
│                    #   still never sends assigneeId.
│                    # ~ sub-issue labels — inherit author:<handle> only when subissue_label ON
│                    #   (default OFF); sub-issues never get the author assignee
├── install.sh       # + scaffold linear-authors.local.yml.sample + ensure *.local.yml gitignored
│                    #   (glob already present); extend install::assert_no_identity_leak to also
│                    #   reject a committed (non-.sample) authors file / emails / UUIDs
└── summary.sh       # (reuse) INFO rows: per-spec "author=<id> (source) → <uuid|unassigned|unknown>"

tests/
├── unit/            # parser::spec_owner_line / git_first_author / resolve_author (owner>git>unknown);
│                    # config attribution accessors + default-OFF; load_authors_override (alias/null/absent);
│                    # _resolve_author_user (override>roster>non-member); _author_handle (non-PII, no email);
│                    # label strip-and-set for author:*; assignee OMITTED on update; unassigned-on-unresolved;
│                    # attribution-OFF == baseline (operator assignee, no author label); identity-leak guard
└── integration/     # (gated) end-to-end: two-author repo → correct label + assignee/unassigned per spec
```

**Structure Decision**: A single-project **additive** extension of the 001
bridge. New logic spans three existing layers — `parser.sh` (author resolution
from filesystem), `config.sh` (the opt-in `attribution.*` block + the gitignored
override loader, modelled on the spec-004 operator-local split), and
`reconcile.sh` (one workspace-`users` resolver + author→user mapping, plus a
clone of the existing label strip-and-set and a re-point of the existing
create-time assignee). `install.sh` scaffolds the `.sample` and extends the
identity-leak guard. No new modules, no new command, no schema/mapping change,
no Layer-E change. The `phase:*` label hygiene and the FR-034 assignee path are
the templates; the only genuinely new transport call is the workspace `users`
query (read-only, reusing `graphql::query`).

## Complexity Tracking

> No constitution violations — this section is intentionally empty.
