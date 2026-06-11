# Data Model: ADR / Decision-Record Mirroring

**Feature**: `008-adr-mirroring`
**Phase**: 1 (design)
**Companions**: [spec.md](./spec.md) · [plan.md](./plan.md)
**Builds on**: `specs/001-spec-kit-linear-bridge/data-model.md` §3.8 (Comment on spec Issue)

---

## 1. Overview

This document defines the data shapes and rules for mirroring each spec's
architecture/decision records — the `Decision / Rationale / Alternatives`
blocks in `research.md` — as idempotent comments on that spec's Linear Issue.
The design is a near-clone of the clarify-session comment path (§3.8 of the
001 data-model). The only behavioural delta is **update-in-place** when a
decision's content changes on disk (FR-005); the clarify path warns-don't-
overwrite, ADRs update.

This document covers:

1. The **ADR record** — the parsed entity extracted from `research.md`
2. The **identity key** — how the marker is composed; idempotency anchor
3. The **comment body layout** — the user-visible shape (parity-locked with spec-kit-jira FR-009/SC-005)
4. The **reconcile state machine** — create / skip / update-in-place
5. **Relationships** — how ADR comments coexist with other artifacts

No new Linear entities are introduced. No config or schema change is required.

---

## 2. ADR record (source shape)

One ADR record is extracted per `Decision / Rationale / Alternatives` block in
a spec's `research.md`. The source grammar matches the `## D<N>/R<N> — Title`
heading convention established in spec 007 (see `specs/007-configurable-
mapping/research.md` for concrete examples).

### 2.1 Fields

| Field | Type | Required | Source | Notes |
|---|---|---|---|---|
| `id` | string | optional | `## D<N>` / `## R<N>` heading prefix | e.g. `D1`, `R2`; absent for un-headed blocks |
| `title` | string | required | heading text after the `—` separator, or first line of the decision body when no heading | e.g. `Alias-layer default synthesis (byte-for-byte back-compat)` |
| `status` | string | optional | explicit status marker in the block (e.g. `[Accepted]`, `[Superseded]`); defaults to `"Accepted"` when unstated | FR-009 default ensures the comment never shows a blank status field |
| `decision` | string | required | body of the `- **Decision**:` bullet | the core resolution text |
| `rationale` | string | optional | body of the `- **Rationale**:` bullet | absent → section omitted from rendered comment (not an error; FR-007) |
| `alternatives` | string | optional | body of the `- **Alternatives considered**:` bullet | absent → section omitted from rendered comment (not an error; FR-007) |
| `source` | string | required | derived | `research.md#<heading-anchor>` — the canonical back-reference to the source location; e.g. `research.md#d1--alias-layer-default-synthesis-byte-for-byte-back-compat` |

### 2.2 Parser invariants

- A block that has a `- **Decision**:` bullet but no heading is a valid
  un-headed ADR: it is parsed and mirrored (keyed by title slug — see § 3).
- Absent `rationale` or `alternatives` bullets are silently omitted from the
  rendered comment; the ADR is not skipped or errored (FR-007).
- A `research.md` with no `Decision / Rationale / Alternatives` blocks yields
  zero ADR records; a missing `research.md` yields zero records — both are
  graceful no-ops (FR-007).
- A block deferred as "out of scope" (e.g. the `D9`/`D10` deferred entries in
  spec 007) is still a valid ADR block and is mirrored unless explicitly
  excluded by a parser convention agreed in Phase 2.

---

## 3. Identity key

### 3.1 Decision key derivation

The **decision key** is the stable identifier used in the idempotency marker.
It is derived deterministically from the source block:

```
if the block has an explicit heading id (D<N> or R<N>):
    key = lower-cased heading id
    e.g. "D1" → "d1",  "R2" → "r2"

else (un-headed block — no D<N>/R<N> prefix):
    key = slug(title)
    where slug(t) = lowercase(t), spaces and punctuation → hyphens,
                    leading/trailing hyphens stripped,
                    truncated to 40 characters

    collision handling: if two un-headed blocks produce the same slug,
    a deterministic positional suffix is appended:
        first occurrence  → "<slug>"
        second occurrence → "<slug>-2"
        third occurrence  → "<slug>-3"
        …
    (position = 1-based ordinal of the block in document order)
    Headed blocks NEVER collide: the heading id (D1, D2, …) is unique by
    construction; duplicate heading ids are a parse warning.
```

### 3.2 Marker composition

Each ADR comment carries a leading HTML-comment identity marker. The marker
encodes the spec's feature number (`<NNN>`) and the decision key (`<key>`):

```
<!-- spec-kit-linear: adr <NNN>-<key> -->
```

Examples (spec 008, feature number `008`):

| Block | key | Full marker |
|---|---|---|
| `## D1 — Alias-layer default synthesis` | `d1` | `<!-- spec-kit-linear: adr 008-d1 -->` |
| `## R2 — Relationship-validation matrix` | `r2` | `<!-- spec-kit-linear: adr 008-r2 -->` |
| Un-headed block titled `Cache invalidation strategy` | `cache-invalidation-strategy` | `<!-- spec-kit-linear: adr 008-cache-invalidation-strategy -->` |
| Two un-headed blocks both titled `Tradeoff` | `tradeoff` / `tradeoff-2` | `<!-- spec-kit-linear: adr 008-tradeoff -->` / `<!-- spec-kit-linear: adr 008-tradeoff-2 -->` |

### 3.3 Marker as idempotency anchor

- The marker is the **only** lookup key. Matching is `body.startswith(marker)`,
  consistent with `reconcile::query_existing_comment_body` (which already
  filters comments by a leading marker prefix per contracts §4.5).
- The key survives content edits (decision/rationale text changes) and block
  reordering — the heading id or title slug is stable across edits.
- Change detection is by rendered body comparison (§ 4.3), not by key.
- The marker is byte-stable for an unchanged decision block (§ 4.4).

---

## 4. ADR comment body layout

### 4.1 Full example

For a decision block `## D1 — Alias-layer default synthesis` with all three
sub-parts present, the rendered comment body is:

```markdown
<!-- spec-kit-linear: adr 008-d1 -->
### ADR d1 — Alias-layer default synthesis  [Accepted]

**Decision**

<decision text verbatim from the research.md block>

**Rationale**

<rationale text verbatim from the research.md block>

**Alternatives considered**

<alternatives text verbatim from the research.md block>

---
*Source: [`research.md#d1--alias-layer-default-synthesis`](research.md#d1--alias-layer-default-synthesis)*
```

### 4.2 Partial example (rationale absent)

When `rationale` is absent, that section is omitted entirely:

```markdown
<!-- spec-kit-linear: adr 008-d9 -->
### ADR d9 — workstate-direct-input-seam  [Accepted]

**Decision**

<decision text verbatim from the research.md block>

**Alternatives considered**

<alternatives text verbatim from the research.md block>

---
*Source: [`research.md#d9--workstate-direct-input-seam`](research.md#d9--workstate-direct-input-seam)*
```

### 4.3 Rendering rules

1. **Marker line** (line 1): the full `<!-- spec-kit-linear: adr <NNN>-<key> -->` string.
2. **ADR heading** (line 2, blank line separator): `### ADR <key> — <title>  [<status>]`
   — two spaces before `[<status>]` to distinguish the bracketed tag from the
   heading text.
3. **Decision section**: always present — `**Decision**` + blank line + decision
   text.
4. **Rationale section**: present only if `rationale` is non-empty.
5. **Alternatives section**: present only if `alternatives` is non-empty.
6. **Divider + Source line**: always present — `---` + `*Source: …*` with a
   Markdown link whose href is `research.md#<heading-anchor>`.
7. Section order is fixed: Decision → Rationale → Alternatives → Source.
   This order matches the spec-kit-jira ADR shape (SC-005 parity check).

### 4.4 Byte-stability requirement

The rendered body MUST be byte-identical across re-runs when the source block
is unchanged. Concretely:

- No run-time timestamps or UUIDs embedded in the body.
- No trailing-whitespace variation (strip trailing spaces from each line before
  rendering).
- Newline normalization: LF only (`\n`), no `\r\n`.
- Section separator is exactly `\n---\n` (blank line above, blank line below via
  the Source line's leading blank).

Byte-stability is what makes `existing_body == rendered_body` the zero-churn
test (§ 5.2).

### 4.5 Jira parity note (FR-009 / SC-005)

The user-visible fields, their ordering (Decision → Rationale → Alternatives →
Source), and the one-comment-per-decision placement are **parity-locked** with
the spec-kit-jira ADR feature. The only rendering differences are:

- Jira uses ADF (Atlassian Document Format); Linear uses Markdown.
- Jira comment IDs use a deterministic UUIDv4 scheme; this Linear path uses
  an HTML-comment marker (consistent with the existing clarify-session and
  memory-block patterns on the Linear side).

A cross-sink parity check (SC-005) compares user-visible shape only; serialisation
format differences are expected and acceptable.

---

## 5. Reconcile state machine

`reconcile::sync_adr_comments` processes each ADR record in document order.
For each record the state machine is:

```
query_existing_comment_body(spec_issue_id, marker)
    │
    ├── 0 matches  → CREATE
    │       reconcile::mutate_comment_create(spec_issue_id, rendered_body)
    │       summary: "commentCreate (adr <key>)"
    │
    ├── 1 match, existing_body == rendered_body  → SKIP (zero churn)
    │       reconcile::log "adr <key> comment in sync"
    │       no write, no summary entry
    │
    └── 1 match, existing_body != rendered_body  → UPDATE IN PLACE
            reconcile::mutate_comment_update(existing_comment_id, rendered_body)
            summary: "commentUpdate (adr <key>)"
```

### 5.1 CREATE path

Reached when no comment on the spec Issue has a body starting with the marker.
Posts a new comment with the fully rendered body. Consistent with
`reconcile::mutate_comment_create` — the same mutation used by the clarify path.

### 5.2 SKIP path (zero-churn idempotency)

Reached when a comment exists and its body is byte-identical to the rendered
body. No write is issued. The reconcile produces no new comment timestamps.
This satisfies SC-002 (zero ADR-comment writes on an unchanged corpus).

### 5.3 UPDATE IN PLACE path

Reached when a comment exists but its body differs from the rendered body (the
ADR's content changed on disk, or the rendering rule was updated). Issues a
`commentUpdate` mutation via `reconcile::mutate_comment_update(comment_id, body)`.
This is the **only behavioural delta** from the clarify path:

| Path | Body diverges → |
|---|---|
| Clarify session | WARN (warns-don't-overwrite: "existing comment body diverges from spec.md; not overwriting") |
| ADR comment | UPDATE IN PLACE (`commentUpdate`) |

The asymmetry is intentional: clarify sessions are Q/A annotations that an
operator may have enriched in Linear (warn to avoid losing nuance); ADR records
are formal decisions where the filesystem is the source of truth and Linear is
a read-only mirror (Principle I).

### 5.4 Error path

If `query_existing_comment_body` fails (transport error), `summary::add error`
is called and the loop continues to the next ADR record (graceful partial
failure per Principle VIII).

### 5.5 Multi-match guard

If `query_existing_comment_body` returns more than one match for a given marker
(should not occur in a well-formed workspace), the bridge logs a warning, skips
the ADR, and surfaces a `summary::add warned` entry rather than silently
picking one to update. The filesystem is never the cause of duplicates; a
duplicate can arise only from a Linear-side manual action.

---

## 6. Relationships

### 6.1 ADR comments attach to the spec Issue (001 data-model §3.8)

ADR comments are `Comment` records on the same spec Issue defined in the 001
data-model. They are a new **category** within §3.8, not a new Linear entity:

| Category (updated §3.8 table) | Source | Trigger | Body shape |
|---|---|---|---|
| ADR decision | each `Decision / Rationale / Alternatives` block in `research.md` | `after_*` reconcile (same pass as clarify) | marker + ADR heading + Decision/Rationale/Alternatives + Source |

### 6.2 Coexistence with clarify-session comments and memory block

The ADR comments **coexist** with the clarify-session comments and the spec
Issue's description (which carries the memory block). The three comment streams
are independent:

- They share the same `issueId` (the spec Issue).
- They are distinguished by their leading marker prefix:
  - Clarify: `<!-- spec-kit-linear: clarify-session <date> -->`
  - ADR: `<!-- spec-kit-linear: adr <NNN>-<key> -->`
- `sync_clarify_comments` and `sync_adr_comments` iterate different source
  sets; neither function touches the other's markers.
- There is no ordering guarantee between the two comment streams (Linear
  displays in `createdAt` order); both streams are correctly idempotent
  independently.

### 6.3 ADR comments are not a drift surface

ADR comments do not participate in drift detection. The spec Issue's drift
anchor is the `description` body (memory block + overview); ADR comments are
a one-way append-or-update mirror. A manual edit or deletion of an ADR comment
in Linear is re-asserted on the next reconcile (Principle I: filesystem is
source of truth).

### 6.4 No new Linear entities

This feature introduces zero new Linear entity types. The additions are:

- One new `Comment` category (ADR) within the existing §3.8 Comment entity.
- One new mutation wrapper (`reconcile::mutate_comment_update`) for the
  `commentUpdate` GraphQL mutation — the clarify path has no equivalent.
- One new parser function (`parser::adr_records`) reading `research.md`.
- One new reconcile function (`reconcile::sync_adr_comments`) wired in after
  `sync_clarify_comments` on the existing `process_spec` path.

No config keys, binding files, or schema version bumps are required.

---

## Cross-references

- `spec.md` FR-001…FR-012 — requirements that motivate every rule above.
- `spec.md` §Key Entities — canonical vocabulary for ADR record, Spec Issue, ADR comment.
- `plan.md` §Project Structure — where `parser::adr_records` and `reconcile::sync_adr_comments` physically live.
- `specs/001-spec-kit-linear-bridge/data-model.md` §3.8 — Comment entity this feature extends.
- `src/reconcile.sh` `reconcile::sync_clarify_comments` — the clarify path this is modelled on (marker convention, `query_existing_comment_body` usage).
- `specs/007-configurable-mapping/research.md` §D1…§D11 — source examples of the `## D<N> — Title` / Decision/Rationale/Alternatives block grammar.
