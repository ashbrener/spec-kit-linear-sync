# Data Model: Human-Readable Issue Titles

**Feature**: `012-readable-titles` | **Date**: 2026-06-17

No new Linear entity, no schema/config/mapping change. This feature changes the
*computed value* of one existing, bridge-owned field — the spec Issue title. The
entities below are the in-process values the parser + reconcile layers build.

---

## Entity: Human title

The readable name (without the number prefix), derived deterministically from
filesystem content.

| Field | Type | Source | Notes |
|---|---|---|---|
| `value` | string | resolver | Non-empty, single line, length-capped. Never `[FEATURE NAME]`. |
| `source` | enum | resolver | `h1` \| `input` \| `slug` (diagnostic / test assertion). |

**Resolution rule (FR-002/FR-003, D1)**:

1. `h1` — `parser::spec_h1_name` of `# Feature Specification: <NAME>`, when
   present and not the `[FEATURE NAME]` placeholder.
2. `input` — first sentence of the `**Input**:` line (`reconcile::_first_sentence` over
   `_extract_input`), when the H1 did not resolve.
3. `slug` — `<short_name>` (the dir slug after `<NNN>-`), last resort.

**Validation**: never empty; never contains `[FEATURE NAME]`; sanitised to a
single line; length ≤ cap after clean-boundary truncation (FR-004/FR-007).

---

## Entity: Composed Issue title

The string written to the Linear Issue title field.

| Field | Type | Value |
|---|---|---|
| `title` | string | `"<NNN> — <human title>"`, capped at `RECONCILE_SPEC_TITLE_MAX_CHARS` (≈80) with word-boundary truncation + `…` when truncated. |

- `<NNN>` = `parser::feature_number` (the spec dir number).
- Separator = `" — "` (em-dash, matching the `Phase N — <Name>` sub-issue
  convention).
- **Bridge-owned + reconciled**: set on create; on update the existing
  `current_title != title` diff rewrites it. A manual Linear rename is overwritten
  on the next reconcile (Principle I) — unchanged ownership semantics.

---

## Resolution table (per spec)

| spec.md H1 | `**Input**:` line present | Composed title | source |
|---|---|---|---|
| `# Feature Specification: Faithful projection` | — | `006 — Faithful projection` | h1 |
| `# Feature Specification: [FEATURE NAME]` | yes | `001 — Establish the validated, internally-consistent seed-data contract…` (capped) | input |
| missing / unparseable | no | `001-fixtures` (today's slug) | slug |

## State transitions (per spec, across reconciles)

```text
H1 present            → create/update: title = "<NNN> — <H1 name>"
unchanged spec        → update: current_title == title ⇒ NO write (zero churn, SC-002)
H1 edited on disk     → update: title rewritten once to the new H1
upgrade (was slug)    → update: current_title "<NNN>-<slug>" != "<NNN> — <name>" ⇒ one re-title, then stable (SC-006)
H1 unfilled + Input   → title = "<NNN> — <first sentence…>" (capped)
no H1 + no Input      → title = "<NNN>-<slug>" (stable, never empty)
```

## Constants

| Name | Value | Purpose |
|---|---|---|
| `RECONCILE_SPEC_TITLE_MAX_CHARS` | ≈80 | Title length cap (one scannable line). |
