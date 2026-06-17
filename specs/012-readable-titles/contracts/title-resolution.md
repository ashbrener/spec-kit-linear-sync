# Contract: Title Resolution & Projection

**Feature**: `012-readable-titles` | **Date**: 2026-06-17

Defines the parser surface, the title composer, and how the composed title
projects onto the spec Issue. All deterministic; reuses existing helpers.

---

## 1. Parser surface (parser.sh)

### `parser::spec_h1_name <spec_md_path> → name | ""`

- Match the first line of the form `^#[[:space:]]+Feature Specification:[[:space:]]*(.+)$`.
- Echo the trimmed capture; strip a trailing run of whitespace.
- Emit **empty** when: the file/heading is absent, the captured name is empty, or
  it is exactly the `[FEATURE NAME]` placeholder.
- Pure md parse, BSD-awk-safe (no `IGNORECASE`/gawk-isms), graceful (no `set -e`
  abort): `name="$(...)" || name=""`.

---

## 2. Reconcile helpers (reconcile.sh)

### `reconcile::_first_sentence <text> → one-line sentence`

- Squeeze all internal whitespace/newlines in `<text>` to single spaces, trim.
- Cut at the first sentence terminator (a period followed by a space, or
  end-of-text); return the lead sentence as a single line. Empty input → empty
  output.

### `reconcile::_compose_spec_title <feature_number> <spec_dir> <short_name> → title`

Resolution (D1), all deterministic:
1. `h="$(parser::spec_h1_name "<spec_dir>/spec.md")"` → if non-empty, `name=$h`.
2. else `name="$(reconcile::_first_sentence "$(reconcile::_extract_input "<spec_dir>/spec.md")")"`.
3. else `name="<short_name>"` and return `"<feature_number>-<short_name>"`
   verbatim (today's slug — last resort, no em-dash reshaping).
- For cases 1–2: compose `"<feature_number> — <name>"`, then **clean-boundary
  length-cap** to `RECONCILE_SPEC_TITLE_MAX_CHARS`: if over cap, cut to the cap,
  back up to the last space, append `…`.
- MUST never return empty and MUST never contain `[FEATURE NAME]` (FR-007).
- Deterministic: identical `(spec.md, dir)` ⇒ identical output every call
  (FR-005, SC-003).

---

## 3. Projection onto the spec Issue (sync_spec_issue)

- **Create path**: `local title="$(reconcile::_compose_spec_title
  "$feature_number" "$spec_dir" "$short_name")"` replaces the prior
  `local title="${feature_number}-${short_name}"`. The create input's
  `title: $title` is otherwise unchanged.
- **Update path**: unchanged — the existing diff
  `if [[ "$current_title" != "$title" ]]; then … {title: $title} … fi`
  now compares against the composed title, so:
  - unchanged spec ⇒ `current_title == title` ⇒ **no title write** (zero churn);
  - upgraded-from-slug or edited-H1 ⇒ one title write.
- **Out of scope (untouched)**: sub-issue `Phase N — <Name>` titles, the Issue
  description, the `speckit-spec:NNN` label, all match/identity keys, config,
  install, Layer E.

---

## 4. Invariants (acceptance-bearing)

- **I1 (readable, SC-001)**: a filled-H1 spec ⇒ title `"<NNN> — <H1 name>"`, no
  slug.
- **I2 (idempotent, SC-002)**: second reconcile over an unchanged spec ⇒ 0 title
  writes.
- **I3 (deterministic/CI, SC-003)**: no model input; interactive and headless
  reconcile produce byte-identical titles.
- **I4 (graceful, SC-004/FR-007)**: unfilled/missing H1 ⇒ Input- or slug-derived
  title; never empty, never `[FEATURE NAME]`.
- **I5 (concise, SC-005)**: every title is one line within the length cap.
- **I6 (migration, SC-006)**: first post-upgrade reconcile re-titles each existing
  Issue exactly once, then zero-churn.
- **I7 (scope)**: sub-issue titles and the identity label are byte-unchanged.
