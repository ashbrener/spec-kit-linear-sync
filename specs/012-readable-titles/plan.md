# Implementation Plan: Human-Readable Issue Titles

**Branch**: `012-readable-titles` | **Date**: 2026-06-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/012-readable-titles/spec.md`

## Summary

Replace the spec Issue's slug title (`${feature_number}-${short_name}`, e.g.
`001-fixtures`) with a human-readable `"<NNN> — <human title>"` (e.g.
`006 — Faithful projection`). The human title is resolved **deterministically
from filesystem content**, in order: (1) the `# Feature Specification: <NAME>`
H1; (2) the first sentence of the `## Input` block (clean-boundary truncated,
length-capped); (3) the `<NNN>-<short_name>` slug as last resort. No model at
sync time — the bridge mirrors what an author wrote, so the title is identical
across interactive, hook, and headless-CI reconciles and is zero-churn on re-run.
**Default-on, no toggle** (clarified): the title is already a bridge-owned field;
existing Issues re-title once on the next reconcile then stay stable.

Mechanically this is one new parser (`parser::spec_h1_name`), one new composer
(`reconcile::_compose_spec_title`) reusing the existing `_extract_input` +
clean-boundary truncation, and swapping the single `local title=…` line in
`reconcile::sync_spec_issue`. The existing title-diff in the update path
(`current_title != title → {title}`) makes it idempotent for free. Parity-locked
with the spec-kit-jira sibling at the user-visible level (specs 008/010
precedent).

## Technical Context

**Language/Version**: Bash (CI matrix: bash 4.4 + 5.2; ubuntu authoritative over
macOS for GNU/BSD differences)

**Primary Dependencies**: `jq`, `curl` — **no new runtime dependencies**. Reuses
`reconcile::_extract_input`, the existing clean-boundary truncation pattern
(`render_spec_content_block`), `parser::feature_number` / `parser::short_name`,
and the existing title-diff in `sync_spec_issue`.

**Storage**: none — reads `spec.md` from the consumer repo's filesystem; writes
only the Linear Issue title field. No config, no schema, no new state.

**Testing**: `bats` (unit, offline); `shellcheck --shell=bash --severity=style`
(lint all `src/**` in one invocation — the SC2120 cross-file lesson from 010);
`yamllint`; `markdownlint-cli2`. Integration gated by `RUN_INTEGRATION_TESTS=0`.

**Target Platform**: macOS + Linux (CI: ubuntu-latest + macos-latest)

**Project Type**: single-project CLI / reconcile sync engine

**Performance Goals**: correctness-bound; zero-churn idempotent re-runs (SC-002).
Title derivation is pure-local string work (no extra network round-trips).

**Constraints**: deterministic + idempotent (no model at sync time, identical in
CI — Principle II/III); filesystem is the source of truth (Principle I); title
stays one scannable line within a length cap (FR-004); never empty / never
`[FEATURE NAME]` (FR-007); `extension.id` stays `linear`, command surface
unchanged (FR-010); user-visible parity with the spec-kit-jira sibling.

**Scale/Scope**: one title per spec; a handful to a few dozen specs per repo.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution **v2.1.0**. All eight principles hold; this feature is **additive,
deterministic, and needs no amendment** — it changes only the *computed value* of
a field the bridge already owns and already reconciles (the Issue title). No new
mapping, no new config, no new command, no Layer-E change.

| Principle | Verdict | Why |
|---|---|---|
| I Filesystem is the source of truth | PASS | The title is derived only from `spec.md` (H1 / Input) + the spec dir number — filesystem-evident. The title was already a bridge-owned, reconciled field (a manual Linear rename is overwritten today); this changes the value, not the ownership. No Linear→filesystem flow. |
| II Reconcile, never event-push | PASS | The title is recomputed from full filesystem state each run; identity (feature number, slug) stays filesystem-derived. **Deterministic-only — no model** — so hook-fired, manual, and CI reconciles produce the identical title (the explicit reason model-summarization is rejected). |
| III Layered idempotency (D + E) | PASS | A Layer-D concern (the title diff already lives there). Layer E (workflow-state flips) is untouched. Unchanged spec ⇒ identical computed title ⇒ the existing `current_title != title` guard fires no write (zero churn, SC-002). |
| IV Write-authority follows the filesystem (drift-aware) | PASS | Runs inside the existing per-spec reconcile; no new drift surface, no new write gate. |
| V UUID-based binding, per-repo config | PASS | No new binding or config. The `<NNN>` prefix is filesystem-derived, not a Linear name lookup. |
| VI OAuth-first, keys-at-the-edges | PASS | No new credential surface; reuses the existing title mutation. |
| VII Memory-just-works | PASS | Additive on the existing `after_*` reconcile; no new command, no hook change, no config toggle (default-on). |
| VIII Surface, don't enforce — observable failure | PASS | An unfilled/missing H1 degrades gracefully (Input → slug; never empty / never `[FEATURE NAME]`, FR-007). Canonical vocabulary (`<NNN> — <name>` mirrors the existing `Phase N — <Name>` em-dash convention). |
| Architectural Constraints (data-model; layers; no backend) | PASS | The frozen mapping (spec → Issue) is unchanged — this only improves the Issue's title string. No mapping redefinition, no new entity, no backend/daemon/db. |

**Post-design re-check (after Phase 1)**: re-evaluated **PASS**. `data-model.md`
and `contracts/` keep all logic on the parser + reconcile layers (one H1 reader +
one title composer reusing `_extract_input` and the existing truncation), no
config/schema/mapping change, no Layer-E change, no new command. The only field
touched is the spec Issue title, already bridge-owned and reconciled. No new
violations.

## Project Structure

### Documentation (this feature)

```text
specs/012-readable-titles/
├── plan.md          # this file
├── research.md      # Phase 0 — title resolution, first-sentence rule, cap, em-dash, migration
├── data-model.md    # Phase 1 — human-title + composed-title entities, resolution table
├── quickstart.md    # Phase 1 — what operators see + the one-time re-title
├── contracts/       # Phase 1 — title-resolution + projection contract
│   └── title-resolution.md
├── checklists/requirements.md
└── tasks.md         # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
├── parser.sh        # + parser::spec_h1_name <spec_md> — extract `# Feature
│                    #   Specification: <NAME>`; trim; treat `[FEATURE NAME]`
│                    #   placeholder / missing as empty. Pure md parse,
│                    #   BSD-awk-safe, graceful when absent.
├── reconcile.sh     # + RECONCILE_SPEC_TITLE_MAX_CHARS (≈80) cap constant.
│                    # + reconcile::_first_sentence <text> — first sentence of a
│                    #   block (cut at first `. ` or newline), squeezed to one line.
│                    # + reconcile::_compose_spec_title <feature_number> <spec_dir>
│                    #   <short_name> — resolve H1 → first-sentence(_extract_input)
│                    #   → slug; prefix `<NNN> — `; clean-boundary length-cap;
│                    #   never empty / never `[FEATURE NAME]`.
│                    # ~ sync_spec_issue: swap the single `local title=
│                    #   "${feature_number}-${short_name}"` (≈L2863) for the
│                    #   composer call. Create + update paths and the existing
│                    #   `current_title != title` diff are otherwise unchanged.
└── (summary.sh, graphql.sh, install.sh, config.sh)  # UNCHANGED — no config,
                                                      # no new mutation, no install change

tests/
├── unit/            # parser::spec_h1_name (name / placeholder / missing /
│                    #   trailing markup); _first_sentence (period, newline,
│                    #   single-line squeeze); _compose_spec_title (H1 wins;
│                    #   Input fallback; slug last resort; <NNN> — prefix; length
│                    #   cap clean-boundary; never empty / never [FEATURE NAME]);
│                    #   idempotency (same spec → same title); sub-issue titles
│                    #   untouched.
└── integration/     # (gated) end-to-end: a spec with H1 → `<NNN> — <name>`;
                     #   a placeholder-H1 spec → Input-derived; re-run zero-churn.
```

**Structure Decision**: A single-project **additive** change. New logic is one
pure parser (`parser::spec_h1_name`) plus two small reconcile helpers
(`_first_sentence`, `_compose_spec_title`) that reuse the already-tested
`_extract_input` and clean-boundary truncation; the only edit to existing flow is
swapping one `title=` assignment in `sync_spec_issue`. The existing title-diff in
the update path delivers idempotency with no further change. Sub-issue titles,
the description, config, install, and Layer E are all untouched.

## Complexity Tracking

> No constitution violations — this section is intentionally empty.
