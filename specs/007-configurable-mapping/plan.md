# Implementation Plan: Configurable Artifact Mapping

**Branch**: `007-configurable-mapping` | **Date**: 2026-06-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-configurable-mapping/spec.md`

## Summary

Extend the shipped 001 core bridge with an operator-configurable artifact-mapping
layer that lives entirely in the source-agnostic configuration layer (`config.sh`)
— the Linear projection in `reconcile.sh` consumes a *resolved* mapping rather than
hardcoding it. A back-compat **alias layer** keeps today's
repo→Project / spec→Issue / phase→sub-issue / task→checklist behaviour as the
**frozen zero-config default**; an opt-in, additive `mapping:` block adds per-level
artifact + relationship configuration (validated against an **offline
relationship-validation matrix**, fail-closed at config-load), the **#17
spec-as-Project** alternative (spec→Project, phase→Issue, task→sub-issue), per-level
inheritance for partial blocks, and an off-by-default **narrative super-level (L0)**
that projects to a Linear **Milestone** and degrades gracefully where Milestones are
unavailable. Idempotency, drift-awareness, and fail-closed writes hold in every
mode. This resolves design issue #17 as a configurable choice and is a **faithful
port of the spec-kit-jira `specs/002-configurable-mapping` model** so the two sinks
share one workstate→sink grammar.

This port is deliberately **narrower** than the Jira original: the `--workstate`
direct-input seam and the status-rollup lever (both in the Jira spec) are
**deferred** to a later Linear feature (spec Assumptions → Out of scope) and are not
part of this plan.

## Technical Context

**Language/Version**: Bash (CI matrix: bash 4.4 + 5.2; ubuntu authoritative over
macOS for GNU/BSD differences)

**Primary Dependencies**: `jq` (JSON), `curl` (Linear GraphQL API) — **no new
runtime dependencies**. Milestone create/attach uses the existing direct-GraphQL
path (the Linear MCP lacks the required mutations), consistent with the 001 seed
fallback (Principle VI).

**Storage**: the committed per-repo binding `linear-config.yml` (gains the new,
optional `mapping:` block) and the gitignored operator-local file + `.env`
(credentials/identity, per spec 004); no database.

**Testing**: `bats` (unit + integration); `shellcheck --shell=bash
--severity=style`; `yamllint`; `markdownlint-cli2`. Run all gates locally before
push (`--severity=style` and ubuntu-CI catch what macOS does not).

**Target Platform**: macOS + Linux (CI: ubuntu-latest + macos-latest)

**Project Type**: single-project CLI / reconcile sync engine

**Performance Goals**: not latency-bound — correctness-bound; zero-churn idempotent
re-runs in every mapping mode; all config validation completes before any write.

**Constraints**: idempotent + drift-aware + fail-closed in ALL modes
(constitutional); all mapping/alias/validation logic confined to the
source-agnostic config layer (`config.sh`), leaving the reconcile engine free of
mapping knowledge (FR-014); no real Linear coordinates in tracked files (FR-018,
real values only in gitignored files); back-compat (pre-feature configs unchanged,
byte-for-byte — no file rewrite, no config-version bump); `extension.id` stays
`linear` and the `/speckit.linear.*` command surface is unchanged (FR-016).

**Scale/Scope**: per-repo, a single Linear team/project binding per run; tens of
specs/phases; up to 5 mapping levels (L0 narrative / repo / spec / phase / task).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution **v2.1.0** (amended this feature — see below). All eight principles
hold; feature-007 is **additive** and backward-compatible. No violations.

**Governance note (amendment landed with this plan)**: The v2.0.0 *Architectural
Constraints* clause locked the spec-001 data-model mapping as constitutional
("amending it is a MAJOR bump"). Because 007 makes that mapping configurable, the
constitution was amended **v2.0.0 → v2.1.0 (MINOR)**: the spec-001 mapping is now
named the **frozen zero-config default** (redefining/removing it stays MAJOR), and a
**bounded** opt-in configurability surface (alias-synthesized default when absent;
offline relationship-validation matrix, fail-closed; all logic in the config layer)
is added as a new constitutional constraint. MINOR is the honest classification:
the default is preserved byte-for-byte and no installed repo changes behaviour, so
the change is backward-compatible (not the MAJOR "redefining the data-model
mapping"). The same MINOR amendment is flagged for backport to the spec-kit-jira
constitution to restore cross-sink governance parity.

| Principle | Verdict | Why |
|---|---|---|
| I Filesystem source of truth · II Reconcile | PASS | Directionality unchanged — Linear stays a unidirectional read-only mirror in every mode; identity stays filesystem-derived (FR-009). |
| III Layered idempotency (D + E) | PASS | FR-008 requires zero-churn re-runs in EVERY mode; the in-body checklist re-renders byte-identically keyed by each item's workstate task identity. Layer E still mutates only the spec-Issue workflow state; mapping is a Layer-D concern. The headline gate. |
| IV Write-authority follows the filesystem (drift-aware) | PASS | The spec-level work unit remains the backward-drift anchor in every mode; the optional L0 super-level is NOT a new drift surface (FR-010). |
| V UUID-based binding, per-repo config | PASS | The `mapping:` block is additive in the committed `linear-config.yml`; bindings stay UUID-based; required-id presence for any Issue/Project-projected level is validated before write (FR-013). |
| VI OAuth-first, keys-at-the-edges | PASS | No new credential surface; the Milestone GraphQL path reuses the existing seed-style edge fallback. |
| VII Memory-just-works | PASS | Hooks and command surface unchanged (FR-016); identity stays filesystem-derived via labels, including a defined key for Issue/Project-projected levels under the #17 alternative (FR-009). |
| VIII Surface, don't enforce — observable failure | PASS | Relationship-matrix + required-id validation is offline, runs at config-load, and **fails closed** writing nothing on any nonsensical mapping (FR-006/FR-007/FR-013); the Milestone-absent case degrades and warns rather than hard-failing (FR-011). Canonical vocabulary preserved. |
| Architectural Constraints (data-model mapping; vendor-neutral engine) | PASS (under v2.1.0) | The spec-001 mapping is preserved as the frozen default (FR-001/FR-002); all mapping/alias/validation logic lives in the config layer, the reconcile engine consumes a resolved mapping and gains no Linear-specific mapping knowledge (FR-014). Grammar matches the Jira sink (FR-015). |

**Post-design re-check (after Phase 1)**: re-evaluated **PASS**. `data-model.md`
keeps the `mapping:` schema, alias synthesis, per-level inheritance, and the
relationship-validation matrix entirely in the config layer; `contracts/`
(`mapping-config.md` + `config-reconcile-interface.md`) defines a resolved-mapping
accessor surface on `config.sh` that `reconcile.sh` consumes, so the engine gains
no Linear-specific mapping knowledge (FR-014). Milestone GraphQL helpers are
isolated in `graphql.sh`. No new violations introduced.

## Project Structure

### Documentation (this feature)

```text
specs/007-configurable-mapping/
├── plan.md          # this file
├── research.md      # Phase 0 — resolved clarifications + tech decisions + Jira parity
├── data-model.md    # Phase 1 — mapping config schema, entities, validation matrix
├── quickstart.md    # Phase 1 — operator guide (default, #17 shape, partial, L0)
├── contracts/       # Phase 1 — mapping-config grammar + config↔reconcile interface
├── checklists/requirements.md
└── tasks.md         # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/
├── config.sh        # + parse the optional `mapping:` block; alias-layer default
│                    #   synthesis from existing binding keys; per-level inheritance;
│                    #   offline relationship-validation matrix; required-id presence
│                    #   checks — ALL fail-closed at config-load (the config layer
│                    #   owns every mapping/validation concern, FR-014)
├── reconcile.sh     # + consume the RESOLVED mapping (artifact + relationship per
│                    #   level) instead of the hardcoded default; project each level
│                    #   to its configured Linear artifact; in-body checklist render
│                    #   keyed by workstate task identity; L0 Milestone super-level
│                    #   create/attach + graceful degradation (fold-onto-repo marker
│                    #   + grouping label) — no new mapping knowledge, reads config
├── graphql.sh       # + Milestone query/create/attach helpers (edge GraphQL path)
└── parser.sh, seed.sh, pull.sh, status.sh, summary.sh, install.sh   # unchanged

tests/
├── unit/            # mapping parse + alias-default equivalence; per-level
│                    #   inheritance; relationship-matrix accept/reject; checklist
│                    #   identity keying; required-id presence fail-closed
└── integration/     # US1 default-equivalence + zero-churn; US2 #17 spec→Project
                     #   shape + nonsensical-relationship fail-closed; US3 partial
                     #   mapping equivalence + zero-churn; US4 L0 Milestone present
                     #   + degrade-when-absent + off-by-default
```

**Structure Decision**: A single-project **extension** of 001 — no new modules. The
mapping layer threads through `config.sh` (parse + alias + per-level inheritance +
validation, all fail-closed at config-load) and is consumed by `reconcile.sh`
(projection + checklist render + L0 Milestone), with Milestone GraphQL helpers in
`graphql.sh`. The reconcile engine gains no Linear-specific mapping knowledge — it
reads a resolved mapping from the config layer (FR-014), mirroring how the Jira sink
keeps the equivalent logic in its `config.sh`.

## Complexity Tracking

> No constitution violations under v2.1.0 — this section is intentionally empty.
