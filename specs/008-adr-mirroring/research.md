# Phase 0 Research: ADR / Decision-Record Mirroring

**Feature**: `008-adr-mirroring`

**Date**: 2026-06-11

This document records the Phase 0 research decisions for feature 008 — mirroring
each spec's architecture/decision records (the `Decision / Rationale /
Alternatives` blocks in its `research.md`) as at-most-once comments on that
spec's Linear Issue. The feature is a near-clone of the existing
clarify-session comment path (`reconcile::sync_clarify_comments`), with one
behavioural delta: **update-in-place** when a decision's content changes on
disk, where the clarify path warns-and-does-not-overwrite.

Two clarification questions were resolved in the 2026-06-11 `/speckit-clarify`
session (ADR source and ADR keying); those answers are encoded in D1 and D3
below. All remaining decisions are settled here; nothing blocks Phase 1 design.

**Unresolved NEEDS CLARIFICATION**: none.

---

## D1 — ADR source = `research.md` only

- **Decision**: Each spec's `research.md` is the sole source of ADRs for this
  feature. Specifically, its structured `Decision / Rationale / Alternatives`
  blocks are parsed — one ADR per block. A `docs/adr/` corpus in the consumer
  repo is **not** a source; it is explicitly out of scope for this feature.
- **Rationale**: `research.md` is the native, structured ADR surface that
  spec-kit already produces — it is the exact source the Jira sibling targets,
  and treating it as the single source keeps a single grammar across both sinks
  (cross-sink parity, FR-009). The `docs/adr/` convention is a separate format
  (freeform Markdown files with no enforced schema) that would require a second
  parser with different grammar assumptions, doubling the parsing surface without
  a documented consumer need. The clarify session (2026-06-11) resolved this
  question explicitly: revisit `docs/adr/` only if a real consumer need appears.
- **Alternatives considered**: Parse both `research.md` and a `docs/adr/`
  corpus (rejected — two sources, two grammars, unclear merge semantics when a
  decision exists in both; no documented consumer need; out of scope per the
  clarification); use `docs/adr/` as the canonical source and treat
  `research.md` as an alternative (rejected — `research.md` is the structured
  native source already; this would invert the authority without benefit and
  break Jira-parity).

---

## D2 — ADR grammar: `## D<N>/R<N> — Title` headings + sub-part bullets

- **Decision**: The ADR grammar in `research.md` is:
  - A `## D<N> — Title` or `## R<N> — Title` heading opens one ADR block.
    Everything between that heading and the next `##` heading (or EOF) belongs
    to that ADR.
  - Within the block, three sub-parts are recognized by their leading bullet
    label: `- **Decision**:`, `- **Rationale**:`, and
    `- **Alternatives considered**:`. Multi-line bullets (continuation lines
    indented under the bullet) are captured as part of that sub-part.
  - Missing sub-parts are tolerated: the rendered comment includes only the
    sub-parts that exist; a block with only a `- **Decision**:` bullet renders
    just that sub-part without error.
  - Un-headed prose blocks — a `Decision:` / `Rationale:` / `Alternatives:`
    paragraph sequence not preceded by a `## D<N>`/`## R<N>` heading — are also
    parsed and mirrored (keyed by title slug per D3).
- **Rationale**: This grammar is the exact shape produced by the spec-kit plan
  template (see the existing `research.md` files throughout this repository,
  including the spec 007 `research.md` used as the format reference). Targeting
  this grammar means no config, no schema negotiation, and no consumer migration.
  Tolerating missing sub-parts (render what exists) satisfies FR-007's
  "graceful absence" principle and the spec edge case — a decision block is
  still mirroring-worthy even if the author omitted the Alternatives bullet.
  Un-headed prose blocks (the less-structured sibling format) are included for
  completeness so no ADR is silently dropped; their key is deterministically
  derived from their title (D3).
- **Alternatives considered**: Require all three sub-parts and error on a
  partial block (rejected — violates Principle VIII "surface, don't enforce";
  a partial decision is still a decision; the spec edge case explicitly requires
  toleration); parse only headed blocks and drop un-headed prose (rejected —
  silently drops valid ADRs; the spec clarification is explicit that un-headed
  blocks are still mirrored, keyed by title slug); require a YAML front-matter
  block per ADR (rejected — no existing `research.md` uses this format; forces
  consumer migration; out of scope).

---

## D3 — Identity keying: heading id when present, else stable title slug + positional suffix

- **Decision**: Each ADR's identity key is constructed as follows:
  1. **Headed block**: key = the explicit heading id, e.g. `D1`, `D2`, `R3`.
     The heading pattern `## D<N> — Title` yields key `D<N>`; `## R<N> — Title`
     yields key `R<N>`. This key is compact, stable across content edits, and
     survives reordering.
  2. **Un-headed block**: key = a stable slug derived from the decision's title
     or first non-empty line (lower-cased, non-alphanumeric characters collapsed
     to `-`, truncated to a reasonable length). If two un-headed blocks produce
     the same slug (same title), a deterministic positional suffix
     (e.g. `-2`, `-3`, …) is appended, disambiguating them by their order of
     appearance in the file.
  The idempotency marker embedded in the comment is
  `<!-- spec-kit-linear: adr <NNN>-<key> -->` where `<NNN>` is the three-digit
  spec directory prefix (e.g. `008`). The existing comment-lookup function
  (`reconcile::query_existing_comment_body`) matches by this marker prefix —
  the match is by KEY, not by comment content — so the marker survives content
  edits and block reordering without producing a duplicate.
- **Rationale**: Heading-id keying (`D<N>`, `R<N>`) is deterministic,
  human-readable, and immune to content edits or reordering — a decision author
  who rewrites the rationale does not change the key, so the next reconcile
  correctly finds and updates the existing comment rather than creating a new
  one. Slugging the title for un-headed blocks extends the same guarantee to the
  less-structured format without requiring authors to add heading ids. The
  positional suffix for same-title un-headed blocks (the edge case from the
  spec) ensures no two un-headed decisions with identical titles collide and
  overwrite each other. The marker convention
  (`<!-- spec-kit-linear: adr <NNN>-<key> -->`) is consistent with the existing
  clarify marker (`<!-- spec-kit-linear: clarify-session <date> -->`), so the
  same `reconcile::query_existing_comment_body` infrastructure locates both
  families of comments. The clarification session (2026-06-11) confirmed this
  keying approach.
- **Alternatives considered**: Key by comment content (rejected — any edit to
  the decision text would break the match and create a duplicate; exactly the
  failure mode FR-003 and FR-005 exist to prevent); key by ordinal position in
  the file (rejected — inserting a new ADR above an existing one would shift
  all positions and mis-match every subsequent comment; violates idempotency
  across reorders); require every block to have an explicit `## D<N>` heading
  and error if absent (rejected — Principle VIII; un-headed blocks are valid and
  must still be mirrored per the spec clarification); use a UUID-per-ADR sidecar
  file (rejected — Principle II prohibits filesystem sidecars as identity
  sources; the key must be filesystem-derived from the document itself).

---

## D4 — Update-in-place on content change (vs. warn-don't-overwrite for clarify sessions)

- **Decision**: When an ADR's content on disk has changed and an existing ADR
  comment is found (matched by key via the idempotency marker), the system
  **updates the existing comment in place** (`commentUpdate`). It does NOT warn
  and skip (the clarify-session path's behaviour). A new
  `reconcile::mutate_comment_update <comment_id> <body>` wrapper (Linear
  `commentUpdate` mutation) is added to support this. The comment id for the
  update is already available from `reconcile::query_existing_comment_body`,
  which returns `{id, body}` — no additional query is needed.
- **Rationale**: Update-in-place directly implements FR-005 and Principle I
  ("filesystem is the source of truth; operator-side mutations in Linear on the
  next reconcile are overwritten"). ADRs are formal decision records — when an
  author revises a decision's rationale or alternatives in `research.md`, the
  Linear comment should reflect the current state of the decision, not a stale
  snapshot. The clarify-session path warns-and-does-not-overwrite because
  clarification sessions are historical records (a session on 2026-06-11 is
  immutable; its comment is a transcript). ADRs are living documents that evolve
  as a design matures — update-in-place is the correct policy for them. The
  `commentUpdate` mutation is a small, bounded addition; it mirrors the existing
  `reconcile::mutate_comment_create` in shape and reuses the same
  `ARG_DRY_RUN` gate, dry-run placeholder, and `summary::add` accounting. The
  comment id is already returned by the existing query function, so no extra
  network call is introduced.
- **Alternatives considered**: Warn-and-skip (the clarify path's policy)
  (rejected — violates FR-005 and Principle I; an updated decision on disk that
  is not reflected in Linear silently diverges; this is exactly the gap the
  feature exists to close); delete-then-recreate (rejected — produces a comment
  timestamp churn on every content change; a reader watching the issue would see
  the comment removed and re-added; `commentUpdate` is the correct in-place
  mutation); require a new explicit key heading on every edit to force a fresh
  create instead of an update (rejected — hostile to authors; keys should be
  stable across edits, not tied to edit history).

---

## D5 — Reuse of existing machinery; no workstate change; marker convention

- **Decision**: The ADR mirroring path is built by near-cloning the existing
  `reconcile::sync_clarify_comments` function into a new
  `reconcile::sync_adr_comments`. The following existing primitives are reused
  without modification:
  - `reconcile::query_existing_comment_body` — comment lookup by marker prefix.
  - `reconcile::mutate_comment_create` — new comment creation.
  - `graphql::query` / `graphql::mutate` — transport layer.
  - The per-spec reconcile hook point (`process_spec`) where
    `sync_clarify_comments` is already wired in — `sync_adr_comments` is wired
    in immediately after.
  The Linear bridge has **no workstate floor** — it reads `spec.md` and
  `research.md` directly from the filesystem (parser-direct) without a
  workstate schema layer. This differs from the Jira sibling, which requires
  a workstate schema change. No schema or config change is needed for this
  feature. The user-visible shape of the ADR comment (fields, ordering, source
  back-reference, one-per-decision placement) must match the Jira sibling
  (FR-009/SC-005) — only the shape must match, not the internal plumbing.
  The idempotency marker convention is:
  `<!-- spec-kit-linear: adr <NNN>-<key> -->`
  (e.g. `<!-- spec-kit-linear: adr 008-D1 -->` for spec 008, decision D1).
  This is consistent with the existing clarify marker format
  (`<!-- spec-kit-linear: clarify-session <date> -->`).
- **Rationale**: Reusing the existing query/create/transport primitives keeps
  the delta small and auditable — the only net-new code is `parser::adr_records`
  (the reader), `reconcile::sync_adr_comments` (the reconcile loop), and
  `reconcile::mutate_comment_update` (the update mutation). Everything else is
  already tested and proven. The absence of a workstate floor is an advantage:
  it means no schema migration and no dependency on a workstate-capable caller —
  the ADR path simply reads `research.md` directly, exactly as
  `sync_clarify_comments` reads `spec.md` directly. The marker convention
  follows the existing established pattern so a reader of the codebase or of the
  Linear issue can identify the comment family at a glance without learning a
  new convention.
- **Alternatives considered**: Introduce a new comment query API call specific
  to ADRs (rejected — `query_existing_comment_body` already handles the generic
  case; no new query needed); use a different marker format or namespace
  (rejected — consistency with the existing clarify marker is a readability and
  maintainability property; a divergent format would require separate
  documentation and documentation drift over time); require a workstate schema
  change to route ADRs through the existing workstate pipeline (rejected — the
  Linear bridge is parser-direct; injecting a workstate layer for a single
  comment stream would be speculative scope expansion, not a faithful port).

---

## D6 — Graceful absence: no `research.md` or no decision blocks → no-op

- **Decision**: If a spec has no `research.md`, or if its `research.md` exists
  but contains no parseable decision blocks, `reconcile::sync_adr_comments`
  posts zero ADR comments and returns without error. The reconcile run completes
  normally. No warning is emitted for the absence (a spec that has not yet
  authored decisions is not an anomaly — it is a normal state during early
  development).
- **Rationale**: FR-007 and Principle VIII ("surface, don't enforce — observable
  failure") are explicit: the absence of a decision corpus is not an error
  condition. The clarify-session path uses the identical policy: if `spec.md`
  has no `## Clarifications` section, `sync_clarify_comments` silently returns.
  ADR mirroring inherits this no-op contract. The graceful-absence path is the
  common cold-start case (a spec that has not yet reached Phase 0 has no
  `research.md`), so failing here would block every early-phase spec from
  reconciling normally — an unacceptable regression (SC-004).
- **Alternatives considered**: Emit a warning when `research.md` is absent
  (rejected — absence is normal and not actionable; a warning would
  systematically pollute reconcile output for all early-phase specs without
  adding signal); hard-fail when `research.md` is absent (rejected — violates
  FR-007 and Principle VIII; the clarify path does not fail on missing
  clarifications and the ADR path must not either); emit a placeholder ADR
  comment when no decisions exist (rejected — fabricating content violates
  Principle I; a "no decisions yet" comment is not a mirror of the filesystem
  state; it creates a spurious artifact that must be removed later).

---

## Technical context

- **Language / runtime**: Bash, targeting the CI matrix (bash 4.4 and bash
  5.2, ubuntu authoritative over macOS for GNU/BSD differences).
- **External tooling**: `jq` (JSON), `curl` (Linear GraphQL API) — both already
  in use; no new runtime dependencies introduced.
- **Source delta**: `src/parser.sh` gains `parser::adr_records`; `src/reconcile.sh`
  gains `reconcile::sync_adr_comments` and `reconcile::mutate_comment_update`.
  No other source files are modified.
- **Testing**: `bats` (unit + optional integration); `shellcheck --shell=bash
  --severity=style`; `yamllint`; `markdownlint-cli2`. All new logic tested with
  stubbed transport (offline).
- **Unresolved NEEDS CLARIFICATION**: none. All decisions are resolved; nothing
  blocks Phase 1 design.
