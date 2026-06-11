# Input Contract: `research.md` ADR Grammar

**Spec**: `008-adr-mirroring` | **Phase**: 1 (Design) | **Date**: 2026-06-11

**Implements**: FR-001 (source = `research.md` only), FR-003 (key
derivation), FR-007 (graceful-empty), FR-012 (no real coordinates in
tracked files).

**Function**: `parser::adr_records <spec_dir>`

This document is the authoritative definition of how
`parser::adr_records` reads decision-record blocks out of a spec's
`research.md` and emits one structured record per ADR. The reconciler
(`reconcile::sync_adr_comments`) consumes this output directly; the
grammar here is the single source of truth for both parser
implementation and parser unit tests.

---

## 1. Source file

`parser::adr_records` reads exactly one file per invocation:

```
<spec_dir>/research.md
```

Where `<spec_dir>` is the filesystem path to one spec directory (e.g.
`specs/NNN-feature-name`). If `research.md` is absent, the function
emits nothing and returns 0 (graceful-empty — FR-007). A `research.md`
that exists but contains no ADR blocks also emits nothing and returns 0.

No other file is read; `docs/adr/` and any other corpus are explicitly
out of scope (FR-001, spec clarification 2026-06-11).

---

## 2. Heading grammar

`parser::adr_records` recognises two heading forms.

### 2.1 Explicit-id headings (preferred)

```
## D<N> — <Title>
## R<N> — <Title>
```

Where:

- `D` or `R` is a literal ASCII letter (uppercase).
- `<N>` is one or more decimal digits (`[0-9]+`).
- ` — ` is a space, an em-dash (U+2014, `—`), and a space.
  An ASCII double-hyphen (` -- `) is tolerated as a synonym (tolerant
  parsing).
- `<Title>` is any non-empty string to end-of-line; leading/trailing
  whitespace is stripped.

These headings produce an explicit heading id of `D<N>` or `R<N>` (e.g.
`D1`, `R3`). The id is used as-is as the record's key (§4).

### 2.2 Titled-only headings (tolerated)

```
## <Title>
```

A second-level heading that does not match the `D<N>`/`R<N>` pattern is
tolerated as an ADR heading **only when it is immediately followed by at
least one recognised sub-part bullet** (§3) before the next second-level
`##` heading. A bare `## <Title>` with no sub-part bullets below it is
treated as a non-ADR section and skipped.

These headings produce no explicit heading id; the key is derived from
the title slug (§4.2).

### 2.3 Un-headed prose (tolerated)

A block that begins with at least one recognised sub-part bullet (§3)
without any preceding `##` heading (or following a non-ADR `##` heading
with no sub-part bullets) is treated as an un-headed ADR. The first
available sub-part value (decision text > rationale > alternatives, in
that priority order) provides the slug for key derivation (§4.2).

### 2.4 Non-ADR `##` sections

Any `##` heading that matches neither §2.1 nor §2.2 (i.e. has no
sub-part bullets at all) is not a decision block and is silently skipped.
Examples: `## Jira-parity cross-reference`, `## Technical context`.

---

## 3. Sub-part bullets

Within an ADR block (from its heading or first sub-part bullet to the
next `##` heading or end-of-file), `parser::adr_records` recognises
three sub-part bullets:

| Sub-part | Bullet prefix | Notes |
|---|---|---|
| Decision | `- **Decision**:` | Case-sensitive; leading whitespace stripped |
| Rationale | `- **Rationale**:` | Case-sensitive; leading whitespace stripped |
| Alternatives considered | `- **Alternatives considered**:` | Case-sensitive; leading whitespace stripped |

**Multi-line handling**: A sub-part's value begins at the content
immediately after the bullet prefix (on the same line) and continues
on all subsequent lines that are indented by at least two spaces relative
to the bullet's column, or that are blank continuation lines between two
such indented lines. The value ends at the first line that is a new
sub-part bullet, a `##` heading, or a non-blank, non-indented line that
is not a recognised continuation. The multi-line value is joined with a
single newline; leading/trailing blank lines in the assembled value are
stripped.

**Missing sub-parts**: Any sub-part not found is recorded as an empty
string in the output record. A missing sub-part is never an error
(FR-007). The rendered comment omits the section rather than showing a
blank field (see `adr-comment.md` §2).

**Status field**: `research.md` does not have a dedicated
`- **Status**:` bullet in the canonical spec-kit grammar. The status
value is always provided by the reconciler default (`Accepted`) when
absent from the source. If a future grammar revision adds
`- **Status**:`, this contract is the amendment point.

---

## 4. Key derivation

Each record carries a stable key used for idempotency-marker generation.

### 4.1 Explicit heading id

When the heading matched §2.1, the key is the heading id as parsed
(e.g. `D1`, `R3`). No normalisation.

### 4.2 Title slug (un-headed or titled-only)

When no explicit heading id is available:

1. Take the title string from the `##` heading (§2.2), or — for
   un-headed blocks — the first non-empty word of the first recognised
   sub-part value (§2.3).
2. Lowercase the string.
3. Replace any run of non-alphanumeric ASCII characters with a single
   hyphen (`-`).
4. Trim leading and trailing hyphens.
5. Truncate to 48 characters.

Example: `"Alias-layer default synthesis (byte-for-byte back-compat)"`
→ `"alias-layer-default-synthesis-byte-for-byte-back"`.

### 4.3 Positional suffix (collision disambiguation)

Two or more records in the same `research.md` with the same derived key
(after §4.1 / §4.2) are disambiguated by appending a one-based decimal
suffix separated by a hyphen:

```
<key>-1   # first occurrence (suffix added only when a collision exists)
<key>-2   # second occurrence
```

The suffix is assigned in document order (top-to-bottom). When there is
exactly one record for a given base key, no suffix is appended. This
guarantees every record has a globally unique key within its
`research.md` (FR-003 edge case: "Two un-headed decisions share the same
title").

---

## 5. Output record format

`parser::adr_records` emits one line per ADR record, tab-separated, in
document order. Fields:

```
<key>\t<title>\t<decision>\t<rationale>\t<alternatives>\t<source>
```

| Field | Content |
|---|---|
| `key` | Stable key per §4 (e.g. `D1`, `alias-layer-default`, `D1-1`) |
| `title` | The heading title string (§2.1/§2.2) or first-line of the first sub-part (§2.3); empty string if none available |
| `decision` | Multi-line decision text (§3), newlines preserved; empty string if absent |
| `rationale` | Multi-line rationale text (§3), newlines preserved; empty string if absent |
| `alternatives` | Multi-line alternatives text (§3), newlines preserved; empty string if absent |
| `source` | The literal relative path `research.md` (the consumer applies `<spec_dir>/research.md` for display) |

Tab characters within field values are escaped as `\t` (two-character
literal backslash-t) so the tab-separated wire format is unambiguous.
Newlines within field values are escaped as `\n` (two-character literal
backslash-n).

The caller (`reconcile::sync_adr_comments`) reconstructs multi-line
values by unescaping `\n` → newline and `\t` → tab before rendering the
comment body.

---

## 6. Graceful-empty behaviour

| Condition | Behaviour |
|---|---|
| `research.md` absent | Emit nothing; return 0 |
| `research.md` present, no ADR blocks | Emit nothing; return 0 |
| `research.md` present, some blocks missing a sub-part | Emit the record with the missing field as empty string; return 0 |
| `research.md` malformed (encoding error, binary content) | Emit nothing for the malformed block; emit a one-line `# WARN: parser::adr_records skipped malformed block at line N` to stderr; return 0 |

No condition causes a non-zero return from `parser::adr_records` itself.
The reconciler (`reconcile::sync_adr_comments`) treats an empty emission
as a no-op (FR-007).

---

## 7. Worked examples

### Example A — Explicit-id heading (normal case)

**Input fragment** (from a `research.md`):

```markdown
## D1 — <Feature name>: default synthesis

- **Decision**: Use the alias layer in `src/PLACEHOLDER-module.sh` to
  synthesize the default when no `mapping:` block is present.
  This produces zero file rewrites and zero config-version bumps.
- **Rationale**: The frozen zero-config default is constitutional;
  the safety promise that "a no-config upgrade changes nothing" is the
  regression anchor for the whole feature.
- **Alternatives considered**: Write a default `mapping:` block to
  `PLACEHOLDER-config.yml` on first post-feature load (rejected —
  the "no file rewrite" promise is explicit); require an explicit block
  to enable the feature (rejected — defeats the opt-in model).
```

**Output record** (one tab-separated line):

```
D1\t<Feature name>: default synthesis\tUse the alias layer in `src/PLACEHOLDER-module.sh` to\nsynthesize the default when no `mapping:` block is present.\nThis produces zero file rewrites and zero config-version bumps.\tThe frozen zero-config default is constitutional;\nthe safety promise that "a no-config upgrade changes nothing" is the\nregression anchor for the whole feature.\tWrite a default `mapping:` block to\n`PLACEHOLDER-config.yml` on first post-feature load (rejected —\nthe "no file rewrite" promise is explicit); require an explicit block\nto enable the feature (rejected — defeats the opt-in model).\tresearch.md
```

Key: `D1` (explicit heading id, §4.1).

---

### Example B — Titled-only heading (no explicit id)

**Input fragment**:

```markdown
## <Feature>: per-level inheritance for partial blocks

- **Decision**: A `mapping:` block that specifies only some levels is valid.
  Each unspecified level independently inherits the synthesized default.
- **Rationale**: Per-level inheritance satisfies the optional/additive
  philosophy and the spec edge case.
- **Alternatives considered**: All-or-nothing validation (rejected).
```

**Output record**:

```
PLACEHOLDER-feature-per-level-inheritance-for-partial\t<Feature>: per-level inheritance for partial blocks\tA `mapping:` block that specifies only some levels is valid.\nEach unspecified level independently inherits the synthesized default.\tPer-level inheritance satisfies the optional/additive\nphilosophy and the spec edge case.\tAll-or-nothing validation (rejected).\tresearch.md
```

Key: slug of `"<Feature>: per-level inheritance for partial blocks"` →
`placeholder-feature-per-level-inheritance-for-partial` (truncated to 48
chars, §4.2).

---

### Example C — Missing sub-part

**Input fragment**:

```markdown
## D5 — <Feature>: optional narrative super-level

- **Decision**: The narrative super-level is off by default.
  When enabled, it projects to a PLACEHOLDER-artifact.
- **Rationale**: Keeping it off preserves the no-config upgrade promise.
```

*(No `- **Alternatives considered**:` bullet.)*

**Output record**:

```
D5\t<Feature>: optional narrative super-level\tThe narrative super-level is off by default.\nWhen enabled, it projects to a PLACEHOLDER-artifact.\tKeeping it off preserves the no-config upgrade promise.\t\tresearch.md
```

Key: `D5` (explicit heading id). `alternatives` field is empty string.
The reconciler renders the comment without an Alternatives section rather
than failing (FR-007).
