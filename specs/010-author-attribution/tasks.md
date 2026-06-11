---
description: "Task list for feature 010 — author-based attribution"
---

# Tasks: Author-Based Attribution

**Input**: Design documents from `/specs/010-author-attribution/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — the project's `bats` convention plus the spec's
test-bearing success criteria (SC-003 idempotency, SC-004 never-clobber,
SC-005 default-OFF parity, SC-006 no-PII, SC-007 graceful) make behavioural
tests required for acceptance.

**Branch**: `010-author-attribution` (off `origin/main`)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files / disjoint regions, no dep on
  incomplete tasks)
- **[Story]**: US1 / US2 / US3 (maps to spec.md user stories)
- Exact file paths included per task

## Path Conventions

Single-project Bash bridge: `src/` (engine), `tests/unit` + `tests/integration`
(bats), config under `.specify/extensions/linear/`.

> **Line-number anchors are hints, not coordinates** (analyze F1): the `~Lxxxx`
> references were derived from a diverged local tree. Anchor on the **named
> functions** (all verified present on this branch); grep for them rather than
> trusting the offsets. E.g. `_resolve_label_ids_array` is at `src/reconcile.sh`
> L1183, `assert_no_identity_leak` at `src/install.sh` L1507 on this branch.

---

## Phase 1: Setup (enabling changes)

- [X] T001 [P] Add `author:*` to the label auto-create allowlist in `reconcile::_resolve_label_id` (`src/reconcile.sh` ~L1340–1366), alongside `speckit-spec:*` / `task-phase:*`, so an `author:<handle>` label is created on first use (contracts/author-resolution-and-projection.md §3).
- [X] T002 [P] Add the documented `linear.attribution.*` block (default-OFF, all keys) as a commented example to the config template the install writes (`config-template.yml` or the inline template in `src/install.sh`), matching contracts/attribution-config.md §1.
- [X] T003 [P] Add a committed `linear-authors.local.yml.sample` (placeholder emails `@example.com`, all-zero UUID, one `linear_user_id: null` non-member row) at the reference location used by install, per contracts/attribution-config.md §3; confirm the existing `.specify/extensions/linear/*.local.yml` gitignore glob already covers the real file (no `.gitignore` change expected).

---

## Phase 2: Foundational (blocking prerequisites for US1)

**Shared resolution layer — author resolution, config, user mapping. MUST
complete before US1 projection.**

### Parser (filesystem author resolution — D1/D2)

- [X] T004 [P] Implement `parser::spec_owner_line <spec_md>` in `src/parser.sh` — first line matching `^\s*[-*]?\s*\*\*(Owner|Author)\*\*\s*:\s*(.+?)\s*$`, echo trimmed value, empty if absent; graceful (no `set -e` abort). Use the readonly-awk-program style of `parser::clarify_sessions`.
- [X] T005 [P] Implement `parser::spec_git_first_author <spec_dir>` in `src/parser.sh` — `git -C <repo> log --diff-filter=A --reverse --format='%ae' -- <spec_dir> | head -1`; empty on no history / untracked / non-repo; capture as `x="$(…)" || x=""` to survive `set -e`.
- [X] T006 Implement `parser::resolve_author <spec_dir> <spec_md>` in `src/parser.sh` — apply `config::attribution_source_order` (default `owner_line git_first_add`); emit `<identity>\t<source>` (source ∈ owner_line|git_first_add) or `\tunknown`. **Normalize a `Name <email>` owner-line value down to the bare `<email>`** before emitting (so roster match + handle derivation get a clean email — analyze U1); a value with `@` but no angle brackets passes through verbatim. Depends on T004, T005 (same file).

### Config (attribution block + override loader — D5/D6)

- [X] T007 [P] Implement the `linear.attribution.*` accessors in `src/config.sh` — `config::attribution_enabled` (default false), `_assignee` (true), `_label` (true), `config::attribution_source_order` (`owner_line git_first_add`), `config::authors_file_path` (default `.specify/extensions/linear/linear-authors.local.yml`), `config::attribution_subissue_label` (false). Each MUST be absent-safe (return default, never error). Follow the spec-004 operator-accessor / spec-007 `mapping.*` pattern.
- [X] T008 [P] Implement `config::load_authors_override <path>` in `src/config.sh` — parse the gitignored YAML into module globals (`CONFIG_AUTHORS_HANDLE[k]`, `CONFIG_AUTHORS_USER_ID[k]`) keyed by lowercased email/handle; `linear_user_id: null`/absent → non-member sentinel; absent file → graceful no-op success. Reuse the shallow-YAML `config::_parse_file` patterns.

### Reconcile (Linear user roster + author→user + handle — D3/D4)

- [X] T009 Implement `reconcile::_resolve_workspace_users` in `src/reconcile.sh` — paginated read-only `users(first:250, after:$after, includeArchived:false){ nodes{ id email active } pageInfo{ hasNextPage endCursor } }` via `graphql::query`; index `lower(email) → {id,active}` into a module global cache (`_RECONCILE_WORKSPACE_USERS_*`), fetched lazily and at most once; on query failure warn once and treat as empty roster (no halt). Field is `users`, NOT `workspaceMembers` (research D4).
- [X] T010 Implement `reconcile::_resolve_author_user <identity>` in `src/reconcile.sh` — override map first (T008 globals): explicit `linear_user_id` or non-member sentinel; else if identity contains `@`, look up the cached roster (T009) case-insensitively and return `id` iff `active`; else empty. Depends on T009 (same file).
- [X] T011 [P] Implement `reconcile::_author_handle <identity>` in `src/reconcile.sh` — override handle → email local-part → bare identity; sanitise (lowercase, collapse non-`[a-z0-9._-]`→`-`, trim, length-cap); MUST NOT emit `@`/full email (FR-005 / SC-006).

### Foundational tests

- [X] T012 [P] Unit tests `tests/unit/author_parser.bats` — `spec_owner_line` (bold variants, list-marker, `Name <email>`, absent); `spec_git_first_author` (temp git repo: first-add wins over later commits; no-history → empty); `resolve_author` (owner beats git; git fallback; both absent → unknown).
- [X] T013 [P] Unit tests `tests/unit/attribution_config.bats` — every accessor returns its default when the block/key is absent; explicit values parsed; `load_authors_override` (alias entry, `null` user, bare-handle key, absent file → no-op).
- [X] T014 [P] Unit tests `tests/unit/author_resolve_user.bats` — `_resolve_author_user` (override-first; roster case-insensitive match; inactive skipped; non-member → empty; override `null` → empty); `_author_handle` (local-part, override handle, sanitiser drops `@domain`, never raw email). Stub `graphql::query` to return a canned `users` page (and a 2-page case for pagination).

**Checkpoint**: resolution layer complete and unit-green — US1 can build.

---

## Phase 3: User Story 1 — Spec Issues show their real author (Priority: P1) 🎯 MVP

**Goal**: each spec Issue carries `author:<handle>` and (for member authors) the
author assignee, instead of the operator.

**Independent test**: enable attribution, reconcile a repo with two distinct
first-add authors → each spec Issue has the correct label + assignee/unassigned.

- [X] T015 [US1] Wire author resolution into the per-spec reconcile in `src/reconcile.sh` — after the spec Issue is resolved, call `parser::resolve_author` and (when enabled) `_resolve_author_user` / `_author_handle`; gate the whole block on `config::attribution_enabled`.
- [X] T016 [US1] Author label strip-and-set at the spec-Issue desired-label computation in `src/reconcile.sh` (the `phase:*` site ~L2883–2920) — when `config::attribution_label` && author≠unknown: strip existing `author:*`, add `author:<handle>`; resolve via `_resolve_label_ids_array`. Idempotent (unchanged author → identical set → no update).
- [X] T017 [US1] Re-point the create-time assignee in `src/reconcile.sh` (`sync_spec_issue` create site ~L2778) — when attribution ON: author UUID if resolvable, else OMIT (unassigned, D7); when OFF: keep `_resolve_operator_assignee_id` (FR-034). Do NOT alter the update path. Depends on T015 (same file).
- [X] T018 [US1] Emit the per-spec INFO summary row (FR-003 / research D9) via `summary::add info` in `src/reconcile.sh` — `author=<id> (<source>) → assigned <tail> | unassigned (non-member) | unassigned`; only when attribution enabled.
- [X] T019 [US1] Sub-issue author-label inheritance in `src/reconcile.sh` (sub-issue label computation ~L3183–3199) — inherit `author:<handle>` only when `config::attribution_subissue_label` (default OFF); never set the author assignee on sub-issues (FR-013). Depends on T016 (same file).
- [X] T020 [P] [US1] Unit tests `tests/unit/author_label_projection.bats` — strip-and-set for `author:*` (compute desired set: stale `author:x` removed, `author:y` added, `phase:*` preserved); label-only mode (`assignee:false`) still stamps; sub-issue inheritance toggle on/off.
- [X] T021 [P] [US1] Unit tests `tests/unit/author_assignee_projection.bats` — create-time assignee = author UUID when member; OMITTED (unassigned) when non-member/unknown and attribution ON; operator when OFF. Stub the issueCreate input builder and assert the `assigneeId` field presence/value.

**Checkpoint**: US1 independently functional — the board shows real authors.

---

## Phase 4: User Story 2 — Manual reassignment & re-runs respected (Priority: P1)

**Goal**: idempotent re-runs (zero churn) and create-only assignee (manual
reassignment survives).

**Independent test**: reconcile, manually reassign one Issue, reconcile again →
assignee unchanged, exactly one `author:*` label.

- [X] T022 [US2] Verify/guard that `assigneeId` is never present in the `issueUpdate` input in `src/reconcile.sh` (the update-diff block ~L2922–2966) — author re-point touches create only; add an inline assertion/comment locking FR-008. (Code review + the T023 test; fix if the re-point leaked into update.)
- [X] T023 [P] [US2] Unit test `tests/unit/author_never_clobber.bats` — drive an update scenario (author unchanged, another field changed) and assert the update input JSON has NO `assigneeId` key (SC-004).
- [X] T024 [P] [US2] Unit test `tests/unit/author_idempotency.bats` — second reconcile over unchanged disk produces no author label write and no assignee write (zero churn, SC-003); author change A→B yields exactly one strip + one add (no duplicate `author:*`).
- [X] T025 [P] [US2] Unit test `tests/unit/attribution_off_baseline.bats` — with `enabled:false`/absent: NO `author:*` label, operator assignee retained, NO `users` query issued (lazy/gated); output identical to baseline (SC-005 regression guard).

**Checkpoint**: idempotency + never-clobber + default-OFF parity proven.

---

## Phase 5: User Story 3 — Authorship without leaking identity (Priority: P2)

**Goal**: the override map enables aliasing/non-members while guaranteeing no
real identifiers land in tracked files.

**Independent test**: add an override file → it's gitignored; only the `.sample`
is tracked; no email/UUID in any tracked file; no email in any label.

- [X] T026 [US3] Scaffold `linear-authors.local.yml` at install in `src/install.sh` — **follow whichever approach `install::_write_operator_local_file` (install.sh:1298) uses for the operator file** (inline-write vs copy-from-committed-sample) so the two stay consistent (analyze A1); ensure the `*.local.yml` gitignore glob is present (idempotent, reuse `install::_ensure_operator_local_gitignored`, install.sh:1482).
- [X] T027 [US3] Extend `install::assert_no_identity_leak` in `src/install.sh` (~L1532–1610) to also reject (a) a tracked (non-`.sample`) `linear-authors.local.yml` via `git ls-files`, and (b) email-shaped / Linear-UUID-shaped strings in committed `linear-config.yml` / `*.sample` (placeholders `example.com` + all-zero UUID excepted). Warn by default; hard-fail under `SPECKIT_LINEAR_STRICT_IDENTITY=1`.
- [X] T028 [P] [US3] Extend `tests/unit/install_identity_leak.bats` — a planted tracked authors file, a real-looking email, and a real-looking UUID in committed config are each caught (warn + strict-fail); the `.sample` with placeholders passes (SC-006).
- [X] T029 [P] [US3] Unit test `tests/unit/author_no_pii_label.bats` — for an email identity with no override, the emitted label is `author:<local-part>` and contains no `@` and no domain (SC-006), across several email shapes.

**Checkpoint**: privacy contract enforced; override ergonomics available.

---

## Phase 6: Polish & Cross-Cutting

- [X] T030 [P] Lint gates: `shellcheck --shell=bash --severity=style` on `src/parser.sh`, `src/config.sh`, `src/reconcile.sh`, `src/install.sh`; `yamllint` the `.sample`; fix findings.
- [X] T031 [P] Docs: add an "Author attribution" section to `README.md` (opt-in block, resolution order, dynamic member match, optional override, default-OFF) and a `CHANGELOG.md` `[Unreleased]` entry.
- [X] T032 [P] Docs: ensure `specs/010-author-attribution/quickstart.md` matches the final accessor names/keys (sync if any renamed during implementation).
- [X] T033 [P] Integration test (gated `RUN_INTEGRATION_TESTS`) `tests/integration/author-attribution.bats` — a two-author fixture repo (distinct first-add emails, one mapped member + one non-member via stubbed roster) → each spec Issue gets the correct label and assignee/unassigned end-to-end.
- [X] T034 Full suite: run `bats tests/unit` (+ shellcheck/yamllint/markdownlint) green on this branch; confirm the pre-existing macOS integration flakes are unaffected; verify SC-001..SC-007 are each covered by a passing test; **assert FR-017 invariants — `extension.yml` `id` is still `linear` and no command/hook surface was added/changed by this feature** (analyze L1).

---

## Dependencies & Execution Order

- **Setup (P1)** → **Foundational (P2)** → **US1 (P3)** → US2/US3 (P4/P5) → **Polish (P6)**.
- **US1 depends on Foundational** (parser + config + resolver + handle). US1 is
  the MVP and is independently demoable once T015–T019 land.
- **US2** is mostly verification/guard tests over US1's implementation (T022 is a
  small guard in the same update-diff region). Depends on US1.
- **US3** is additive (override scaffold + identity guard + privacy tests) and
  does NOT block US1 — US1 works with dynamic roster resolution alone. The
  override **loader** (T008) is foundational; US3 adds the install scaffold + guard.
- Same-file ordering: T004/T005 → T006 (parser.sh); T009 → T010 (reconcile.sh);
  T015 → T017, T016 → T019 (reconcile.sh spec-issue region).

## Parallel Execution Examples

- **Foundational kick-off (different files)**: T004/T005 (parser.sh) ∥ T007/T008
  (config.sh) ∥ T011 (reconcile.sh handle) ∥ T012/T013 (test files). Then T006,
  T009→T010, T014.
- **US1 tests**: T020 ∥ T021 (separate bats files) after T015–T019.
- **US2 tests**: T023 ∥ T024 ∥ T025 (separate bats files) after US1.
- **US3**: T028 ∥ T029 after T026/T027.
- **Polish**: T030 ∥ T031 ∥ T032 ∥ T033.

## Implementation Strategy

- **MVP = Phase 1 + 2 + 3 (US1)**: enabling changes, the shared resolution layer,
  and the spec-Issue projection. Delivers the whole point — the board shows real
  authors — with dynamic member resolution and no override file required.
- **Increment 2 = US2**: lock idempotency + never-clobber + default-OFF parity
  with the regression tests (low code, high assurance).
- **Increment 3 = US3**: override ergonomics + identity-leak hardening for
  aliasing/non-members and the privacy guarantee.
- **Polish**: lint, docs, gated integration, full-suite green.

## Coverage map (success criteria → tasks)

| SC | Covered by |
|---|---|
| SC-001 author label present | T016, T020, T033 |
| SC-002 member → assignee on create | T017, T021, T033 |
| SC-003 idempotent zero-churn | T016/T017 design, T024 |
| SC-004 manual reassignment survives | T022, T023 |
| SC-005 default-OFF == baseline | T017, T025 |
| SC-006 no PII in files/labels | T011, T027, T028, T029 |
| SC-007 unknown/non-member graceful | T006, T010, T018 |
