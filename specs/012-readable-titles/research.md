# Phase 0 Research: Human-Readable Issue Titles

**Feature**: `012-readable-titles`

**Date**: 2026-06-17

Phase 0 decisions for replacing the slug Issue title with a deterministic
human-readable `"<NNN> — <human title>"`. Two clarifications resolved in the
2026-06-17 `/speckit-clarify` session (title source = H1 → Input → slug; rollout
= default-on, no toggle) are encoded in D1 and D6.

**Unresolved NEEDS CLARIFICATION**: none.

---

## D1 — Title resolution order: H1 → Input-first-sentence → slug

- **Decision**: Resolve the human title in order: (1) `# Feature Specification:
  <NAME>` H1; (2) the first sentence of the `**Input**:` line (via
  `_extract_input`), truncated at a clean word boundary and length-capped;
  (3) the `<NNN>-<short_name>` slug. The
  composed Issue title is `"<NNN> — <human title>"`.
- **Rationale**: The H1 is the canonical human name spec-kit already emits for
  every spec, so the common case is free and retroactive. The Input fallback
  covers specs whose H1 is still the `[FEATURE NAME]` placeholder (the AML demo's
  `001-fixtures` is exactly this — its H1 is unfilled but its Input is a rich
  sentence). The slug last-resort guarantees a non-empty, stable title for any
  spec. All three sources are filesystem-evident and deterministic (Principle I).
- **Alternatives considered**: H1-only → slug (rejected by clarification —
  leaves placeholder-H1 specs like `001-fixtures` stuck on the slug, which is the
  exact case that motivated the feature); model summarization of the Input
  (rejected — see D2); a dedicated `**Title:**` line convention (rejected — the
  H1 already exists and needs no authoring change; revisit only if H1s prove
  inadequate in practice).

---

## D2 — Deterministic-only: no model at sync time

- **Decision**: The title is computed purely from filesystem text — never by a
  summarization model at reconcile time.
- **Rationale**: The reconciler runs in three contexts that MUST agree
  (interactive hook, manual push, headless CI/Layer-E) — only the first has a
  model available. A model call would also be non-deterministic, rewriting the
  title on every run and destroying the zero-churn idempotency guarantee
  (Principle II/III), and would add network/cost to the hot write path.
  "Summarization," where wanted, is an authoring-time act: the spec's H1 (and
  Input) are written when the spec is authored; the bridge only mirrors them.
- **Alternatives considered**: call a model in the interactive path only
  (rejected — diverges interactive vs CI output, violating "one code path / same
  outcome", and churns); cache a model summary in a sidecar (rejected — sidecar
  state is forbidden by Principle II; identity/derivation must be filesystem-
  evident).

---

## D3 — H1 parse: `# Feature Specification: <NAME>`, placeholder-aware

- **Decision**: `parser::spec_h1_name <spec_md>` matches the first line of the
  form `# Feature Specification: <NAME>` (tolerating surrounding whitespace),
  emits the trimmed `<NAME>`, and treats an empty name or the literal
  `[FEATURE NAME]` placeholder as **absent** (empty output). BSD-awk-safe (no
  gawk-isms); graceful when the file or heading is missing.
- **Rationale**: This is the exact heading the spec-kit template and every
  existing spec use (`# Feature Specification: Faithful projection`). Treating the
  unfilled placeholder as absent is what routes `001-fixtures` to the Input
  fallback rather than titling an Issue `001 — [FEATURE NAME]` (FR-007).
- **Alternatives considered**: take any first-level (`#`) heading (rejected — too
  loose; would catch a stray heading); require an exact-case `Feature Specification:`
  label (kept — it is the template's fixed label; a non-conforming H1 simply
  falls through to the Input/slug, still safe).

---

## D4 — First-sentence rule for the Input fallback

- **Decision**: `reconcile::_first_sentence <text>` takes `_extract_input`'s
  output, squeezes internal newlines/whitespace to single spaces, and cuts at the
  first sentence terminator (period-then-space, period-then-newline, or end), then
  the composer applies the length cap (D5). Deterministic and pure-string.
- **Rationale**: The Input is often a full paragraph; a title must be one
  scannable line, so the first sentence (capped) is the right slice — it carries
  the "what this spec does" lede. Reusing the existing `_extract_input` avoids a
  second Input parser.
- **Alternatives considered**: whole Input as the title (rejected — paragraph
  titles are bad in list/board views, FR-004/SC-005); the H1-less `## Overview`
  first line (rejected — Input is the more reliable lede and is what the operator
  pasted; Overview may be absent).

---

## D5 — Length cap + clean-boundary truncation; em-dash separator

- **Decision**: Cap the composed title at `RECONCILE_SPEC_TITLE_MAX_CHARS`
  (≈80 chars) using word-boundary truncation (back up to the last space within
  the cap; append a single `…` when truncated) — mirroring the clean-boundary
  truncation already used for inlined descriptions. The number/name separator is
  an em-dash with surrounding spaces: `"<NNN> — <name>"`.
- **Rationale**: ~80 chars keeps the title to one line in Linear's list/board.
  Word-boundary (not mid-word) truncation reads cleanly and is deterministic. The
  em-dash matches the existing `Phase N — <Name>` sub-issue convention
  (vocabulary consistency, Principle VIII). The em-dash is emitted as a UTF-8
  literal in a bash string / `jq --arg` (no awk matching), so the GNU/BSD em-dash
  parsing gotcha does not apply here.
- **Alternatives considered**: no cap (rejected — long H1/Input would overflow);
  hyphen/colon separator (rejected — em-dash matches the existing sub-issue
  convention and reads as a title, not a slug).

---

## D6 — Default-on, no toggle; one-time re-title migration

- **Decision**: Readable titles apply to every install with no config toggle and
  no opt-out (clarified). On the first reconcile after upgrade, each existing
  Issue re-titles once (slug → readable) via the existing `current_title != title`
  diff; every reconcile thereafter is zero-churn.
- **Rationale**: The title is already a bridge-owned, reconciled field (a manual
  Linear rename is already overwritten today), so this is a strictly better
  computed value, not a behaviour/ownership change — a config knob would add
  surface for no real benefit. The one-time re-title is an intended improvement,
  bounded to a single write per existing Issue.
- **Alternatives considered**: opt-in config toggle like spec 010 (rejected —
  010 changed *who owns the assignee* and could surprise existing boards; this
  only improves an already-owned title string, so default-on is proportionate);
  create-only (don't re-title existing Issues) (rejected — would leave already-
  synced boards on slugs forever, defeating the retroactive win in US1/SC-001).

---

## D7 — Scope guard: spec Issue title only

- **Decision**: Touch only the spec Issue title in `sync_spec_issue` (the single
  `local title=` line). Do NOT change sub-issue (`Phase N — <Name>`) titles, the
  Issue description, the `speckit-spec:NNN` identity label, or any match key.
- **Rationale**: Sub-issue titles are already human-readable; the description
  already inlines the Input/Overview; the identity label is the idempotent match
  key and must stay byte-stable. Narrow scope keeps the change low-risk and the
  diff reviewable.
- **Alternatives considered**: also prettify sub-issue titles (rejected — already
  readable; out of scope); fold the human name into the description header
  (rejected — out of scope; description is unchanged).

---

## D8 — Testing strategy

- **Decision**: Unit-first, offline, mirroring `tests/unit` conventions:
  `parser::spec_h1_name` (real name / `[FEATURE NAME]` placeholder / missing
  heading / trailing markup); `_first_sentence` (period-terminated, newline-
  terminated, multi-line squeeze); `_compose_spec_title` (H1 wins; Input fallback
  when H1 is placeholder; slug last resort; the `<NNN> —` prefix; length-cap clean
  boundary; never empty / never `[FEATURE NAME]`); idempotency (same spec → byte-
  identical title across two calls); a guard that sub-issue title lines are
  unchanged. Gated integration: a fixture repo with one filled-H1 spec and one
  placeholder-H1 spec → correct titles + zero-churn re-run.
- **Rationale**: All behaviour is deterministic pure-string work, fully unit-
  checkable offline — the proven pattern in this repo; keeps CI hermetic.
- **Alternatives considered**: integration-only (rejected — slow, needs a live
  workspace, can't run under `RUN_INTEGRATION_TESTS=0`).
