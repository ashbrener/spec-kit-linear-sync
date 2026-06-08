# Tasks: Config / identity split

**Feature**: `004-config-identity-split`
**Input**: [spec.md](./spec.md), [plan.md](./plan.md)
**Prerequisites**: plan.md (two-file model, cascade, migration, touched
functions) is complete.

**Tests**: included (the spec is a security/config-model change; back-
compat and the no-leak invariant MUST be proven by tests).

**Organization**: tasks are grouped by `task phase`; `[P]` marks tasks
that touch disjoint files and may run in parallel. Each task lists exact
file paths.

## Phase 1: Config + docs surface (committed binding loses identity)

- [ ] T001 Remove the `linear.operator` block from `config-template.yml`,
  bump `config_version` to 2, and rewrite the header comment to describe
  the two-file model (which file is committed, which is local) and the
  resolution cascade. File: `config-template.yml`. (FR-001, FR-008,
  FR-004)
- [ ] T002 [P] Fix the `.gitignore` contradiction: REMOVE the
  `.specify/extensions/linear/linear-config.yml` ignore entry and its
  comment; ADD an ignore entry for the operator-local file glob
  `.specify/extensions/linear/*.local.yml` with a clear comment. File:
  `.gitignore`. (FR-004, FR-003, SC-005)
- [ ] T003 [P] Update `README.md`: document the two-file model
  (`linear-config.yml` committed = shareable binding;
  `linear-operator.local.yml` local = identity), the env → local-file →
  prompt cascade for identity and key, and the explicit commit policy.
  File: `README.md`. (FR-008, SC-005)

## Phase 2: Config loader — operator-local store + migration + cascade

- [ ] T010 In `src/config.sh` add module state for the operator-local
  store: `declare -gA CONFIG_OPERATOR_VALUES`,
  `CONFIG_OPERATOR_LOADED_PATH`, the
  `CONFIG_OPERATOR_LOCAL_PATH_DEFAULT=".specify/extensions/linear/linear-operator.local.yml"`
  constant, and a `_CONFIG_MIGRATION_NOTICE_EMITTED` one-shot latch.
  File: `src/config.sh`. (FR-002)
- [ ] T011 In `src/config.sh` add `config::_parse_file_into <path>
  <assoc-array-name>` (or refactor `_parse_file` to accept a target
  array) so the same shallow YAML reader can populate either
  `CONFIG_VALUES` or `CONFIG_OPERATOR_VALUES`. File: `src/config.sh`.
  (FR-002)
- [ ] T012 In `src/config.sh` add `config::_load_operator_file [path]`
  that parses `linear-operator.local.yml` into `CONFIG_OPERATOR_VALUES`
  when present (no-op + no halt when absent; malformed file surfaces the
  same `config::_die` diagnostic the committed loader emits). File:
  `src/config.sh`. (FR-002, edge: malformed local file)
- [ ] T013 In `src/config.sh` add
  `config::_maybe_migrate_operator_block <committed-path>`: detect a
  legacy `linear.operator.*` key in `CONFIG_VALUES`; if found, write the
  identity into the operator-local file (only when that file does not
  already exist — local file is authoritative), strip the `operator:`
  block from the committed file in place (portable awk), and emit
  EXACTLY ONE migration notice via the latch. File: `src/config.sh`.
  (FR-007, SC-003, edge: legacy + local-file-present)
- [ ] T014 In `src/config.sh` wire `config::load` to call
  `config::_maybe_migrate_operator_block` and then
  `config::_load_operator_file` after the committed file is parsed, so
  every entry point (reconcile + install) migrates and loads identity.
  File: `src/config.sh`. (FR-007)
- [ ] T015 In `src/config.sh` add `config::resolve_operator_user_id`
  implementing the cascade: `LINEAR_OPERATOR_USER_ID` env →
  `operator.user_id` from `CONFIG_OPERATOR_VALUES` → empty (caller warns
  + proceeds). MUST NOT read `CONFIG_VALUES[linear.operator.*]`. File:
  `src/config.sh`. (FR-005, FR-011)
- [ ] T016 In `src/config.sh` re-point `config::get_operator_user_id`,
  `config::get_operator_name`, `config::get_operator_email` to read the
  operator-local store (`CONFIG_OPERATOR_VALUES` + corresponding env
  vars), preserving their empty-on-absence / no-halt contract for
  back-compat callers. File: `src/config.sh`. (FR-002, FR-009)

## Phase 3: Reconcile + key cascade consumers

- [ ] T020 In `src/reconcile.sh` change
  `reconcile::_resolve_operator_assignee_id` to call
  `config::resolve_operator_user_id` (cascade) instead of
  `config::get_operator_user_id`, keeping the one-shot warn-and-proceed-
  unassigned behaviour. File: `src/reconcile.sh`. (FR-005, FR-011)
- [ ] T021 In `src/reconcile.sh` confirm the memory-block
  "last touched by" email cell sources from the cascade-backed
  `config::get_operator_email` (now operator-local), and that absence
  degrades gracefully (drop the `by …` suffix). File: `src/reconcile.sh`.
  (FR-005)
- [ ] T022 In `src/graphql.sh` extend `graphql::_load_api_key` to read
  `LINEAR_API_KEY` from the operator-local file as a tier BETWEEN the
  env var and `.env` (env → operator-local → `.env`), preserving the
  exit-2 fail-loud when nothing resolves. Document the cascade in the
  function header. File: `src/graphql.sh`. (FR-006, US4)

## Phase 4: Install — scaffold local file + gitignore guarantee

- [ ] T030 In `src/install.sh` add the
  `INSTALL_OPERATOR_LOCAL_PATH=".specify/extensions/linear/linear-operator.local.yml"`
  constant and stop writing the `operator:` block into the committed
  config: remove the `install::_write_operator_block` call from
  `install::write_config` (both the fresh-write and re-install arms).
  File: `src/install.sh`. (FR-001, FR-002)
- [ ] T031 In `src/install.sh` add
  `install::_write_operator_local_file` that scaffolds
  `linear-operator.local.yml` with the resolved identity
  (`INSTALL_SESSION_VIEWER_* / INSTALL_OPERATOR_*`); idempotent — do not
  clobber an existing operator-edited local file. File: `src/install.sh`.
  (FR-003)
- [ ] T032 In `src/install.sh` add
  `install::_ensure_operator_local_gitignored` (mirror
  `install::_ensure_dotenv_gitignored`): ensure
  `.specify/extensions/linear/*.local.yml` is present in `.gitignore`,
  adding it if absent (never silently skip). File: `src/install.sh`.
  (FR-003, US2 scenario 2)
- [ ] T033 In `src/install.sh` call
  `install::_ensure_operator_local_gitignored` and
  `install::_write_operator_local_file` from `install::main` right after
  `install::write_config`, and add a summary row for the scaffolded
  local file. File: `src/install.sh`. (FR-003)

## Phase 5: Tests (back-compat + no-leak invariant)

- [ ] T040 [P] Extend `tests/unit/config.bats`: the committed config
  fixture has NO `operator.*` keys and all existing getters/validate
  still pass (proves FR-001 + FR-009). File: `tests/unit/config.bats`.
- [ ] T041 [P] Add to `tests/unit/config.bats`: identity resolves via
  the cascade — (a) `LINEAR_OPERATOR_USER_ID` env wins over the local
  file; (b) with no env, `operator.user_id` resolves from the local
  file; (c) with neither, `config::resolve_operator_user_id` returns
  empty (no halt). File: `tests/unit/config.bats`. (FR-005, FR-011,
  cascade-precedence edge)
- [ ] T042 [P] Add to `tests/unit/config.bats`: legacy-config migration —
  a committed config with `operator.*` keys, on `config::load`, emits
  exactly ONE migration notice, writes the local file, and the committed
  file afterwards has no `operator:` block; a second `config::load`
  emits NO further notice (idempotent). File: `tests/unit/config.bats`.
  (FR-007, SC-003)
- [ ] T043 Add `tests/unit/install_config_split.bats`: install scaffolds
  `linear-operator.local.yml`, ensures the `*.local.yml` glob is in
  `.gitignore` (adds it when absent), and writes NO `operator:` block
  into the committed `linear-config.yml`. File:
  `tests/unit/install_config_split.bats`. (FR-002, FR-003, US2)
- [ ] T044 [P] Verify `tests/unit/no-real-identifiers.bats` stays green
  given `linear-config.yml` is now committable — confirm the committed
  template + tracked tree carry no operator identity (SC-002). Adjust
  the guard's bootstrap comment only if needed. File:
  `tests/unit/no-real-identifiers.bats`.
- [ ] T045 No-identity end-to-end: assert the reconcile assignee
  resolver warns once and returns empty (issues created unassigned)
  when neither env nor local file supplies identity — covered by a unit
  test exercising `reconcile::_resolve_operator_assignee_id` with an
  empty store. File: `tests/unit/reconcile.bats` (or `config.bats` if
  the resolver is config-level). (FR-011)

## Phase 6: Gates + cross-artifact consistency

- [ ] T050 Run `shellcheck --shell=bash` on every changed `src/*.sh`
  (config.sh, reconcile.sh, graphql.sh, install.sh) — zero findings.
- [ ] T051 [P] Run `bats tests/unit/` — all green (including the new +
  extended suites).
- [ ] T052 [P] Run the relevant integration suites
  (`install_e2e_*`, `us1-*`, drift) — all green; existing safety
  guarantees unchanged (FR-009).
- [ ] T053 [P] Run `yamllint -d relaxed` on `config-template.yml` and
  any changed YAML — clean.
- [ ] T054 [P] Run `npx --yes markdownlint-cli2` on `README.md`,
  `specs/004-config-identity-split/plan.md`, and `tasks.md` — clean.

## Dependencies

- Phase 2 (config loader) is the spine: T020–T022 (Phase 3) and the
  install helpers (Phase 4) depend on the new `config::*` surface.
- T010 → T011 → {T012, T013} → T014 → {T015, T016} (sequential within
  config.sh — same file).
- Phase 3 tasks depend on Phase 2; T020/T021 share `reconcile.sh`
  (sequential), T022 is independent (`graphql.sh`).
- Phase 4 tasks all touch `install.sh` (sequential): T030 → T031 → T032
  → T033.
- Phase 5 tests depend on the impl phases they cover; the `[P]` test
  files are disjoint.
- Phase 6 gates run last.

## Parallel execution example

Phase 1 fans out: T001 (`config-template.yml`), T002 (`.gitignore`),
T003 (`README.md`) touch disjoint files — run together. Phase 6
T051–T054 are independent gate commands — run together.
