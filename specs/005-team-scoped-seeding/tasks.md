# Tasks: Team-scoped / non-admin seeding

**Feature**: `005-team-scoped-seeding`
**Input**: [spec.md](./spec.md), [plan.md](./plan.md)
**Prerequisites**: plan.md (scope option, team-scoped labels, adopt path,
permission classification, per-family flow) is complete. Builds on spec
004's config loader.

**Tests**: included. The spec is a permissions/usability change whose
core promises (team-scoped teamId, adopt-without-create, actionable
permission message, idempotency) MUST be proven by tests.

**Organization**: tasks are grouped by `task phase`; `[P]` marks tasks
that touch disjoint files and may run in parallel. Each task lists exact
file paths.

## Phase 1: Config + docs surface (seed scope option)

- [ ] T001 Add the `linear.seed.scope` option to `config-template.yml`
  under the `linear:` block, documented with the allowed values
  (`workspace` | `team`) and the default (`team`, with auto-fallback to
  adopt). Keep the placement away from the captured-UUID maps so the
  splicer is unaffected. File: `config-template.yml`. (FR-005, FR-006)
- [ ] T002 [P] Add a localized "Non-admin / team-scoped seeding"
  subsection to `README.md` under Configuration: the `seed.scope` option
  and its default, the adopt-existing path, the auto-fallback behaviour,
  and a per-path permission table (workspace = workspace-admin; team =
  team-level create; adopt = none). Keep it self-contained so it does not
  touch the parser/reconcile sections the sibling PR (006) edits. File:
  `README.md`. (FR-015, SC-006)

## Phase 2: Config loader — seed-scope getter

- [ ] T010 In `src/config.sh` add the constants
  `CONFIG_SEED_SCOPE_DEFAULT="team"` and
  `CONFIG_SEED_SCOPES=("workspace" "team")`. File: `src/config.sh`.
  (FR-005)
- [ ] T011 In `src/config.sh` add `config::get_seed_scope`: echo
  `linear.seed.scope` when present and one of the allowed values; echo
  the default `team` when the block is absent (so a pre-005 config keeps
  working — FR-013); `config::_die` on an invalid value with an
  actionable hint listing the allowed values (Principle VIII). File:
  `src/config.sh`. (FR-005, FR-013)

## Phase 3: GraphQL — non-fatal classified mutate

- [ ] T020 In `src/graphql.sh` add `graphql::_classify_error <status>
  <body>` (internal): return one of `permission` / `limit` / `transport`
  / `graphql` per the plan's classification table (401/403 + forbidden /
  not-authorized / permission / admin → permission; 429 + rate-limit /
  limit-exceeded / too-many → limit; curl/5xx/unparseable → transport;
  other 200-errors[] → graphql). File: `src/graphql.sh`. (FR-004)
- [ ] T021 In `src/graphql.sh` add the public `graphql::mutate_capture
  <mutation> <vars>`: a non-fatal sibling of `graphql::mutate` that
  ALWAYS returns 0 and prints a JSON envelope `{ok, class, response?,
  message?}` on stdout. The API key stays inside this module (Principle
  VI). `graphql::mutate`'s exit-on-error contract is left UNCHANGED for
  existing callers. File: `src/graphql.sh`. (FR-004, FR-006)

## Phase 4: Seed — scope resolution + team-scoped labels

- [ ] T030 In `src/seed.sh` add the `--scope workspace|team` CLI flag
  (and `--scope=…`) to `seed::parse_args` + the usage text, storing it in
  a new `ARG_SEED_SCOPE` global (empty = unset). File: `src/seed.sh`.
  (FR-005)
- [ ] T031 In `src/seed.sh` add `seed::resolve_scope`: precedence
  `--scope` flag → `config::get_seed_scope` → default `team`. Resolve
  once in `main`, log the chosen scope, and pass it down. File:
  `src/seed.sh`. (FR-005, FR-006)
- [ ] T032 In `src/seed.sh` extend `seed::create_label <name> [color]
  [scope] [team_uuid]`: in `team` scope add `teamId` to the
  `IssueLabelCreateInput`; in `workspace` scope omit it exactly as today
  (FR-013). Preserve the dry-run log + placeholder UUID path. File:
  `src/seed.sh`. (FR-001, FR-013)

## Phase 5: Seed — adopt path + permission handling

- [ ] T040 In `src/seed.sh` add `seed::permission_hint <resource>
  <kind>`: the single actionable message body naming the failed resource,
  the failure kind (`permission`/`limit`), and the path forward (adopt
  existing / `--scope team`), routed through `summary::add`. Reused by
  every create-denied site. File: `src/seed.sh`. (FR-004, SC-003)
- [ ] T041 In `src/seed.sh` route `seed::create_workflow_state` through
  `graphql::mutate_capture`: on `ok` capture + report `created`; on
  `permission`/`limit` emit `seed::permission_hint` and return a distinct
  "denied" status (not a transport error); on `transport`/`graphql` fail
  closed as today. File: `src/seed.sh`. (FR-004, FR-012, FR-014)
- [ ] T042 In `src/seed.sh` route `seed::create_label` through
  `graphql::mutate_capture` with the same denied / fail-closed split as
  T041. File: `src/seed.sh`. (FR-004, FR-012, FR-014)
- [ ] T043 In `src/seed.sh` update `seed::reconcile_workflow_states`:
  when the find-by-name probe already returned a UUID, report it as
  `adopted` (distinct from the create path); when create is DENIED, fall
  back to the probed existing UUID if present (adopt) else record the
  state as could-not-provision by name. File: `src/seed.sh`. (FR-002,
  FR-003, FR-006, FR-011, FR-012)
- [ ] T044 In `src/seed.sh` update `seed::reconcile_labels` and
  `seed::reconcile_agent_labels`: pass the resolved scope (and team UUID)
  to `create_label`; report existing as `adopted`; on DENIED, fall back
  to the probed UUID (adopt) — capturing agent-label UUIDs into
  `SEED_AGENT_LABEL_UUIDS` unchanged — else record could-not-provision by
  name. File: `src/seed.sh`. (FR-002, FR-003, FR-006, FR-011, FR-012)
- [ ] T045 In `src/seed.sh` `main`: after both families run, if any
  PERSISTED resource (workflow_state_uuids / default_state_uuids /
  agent_label_uuids) is still unresolved (neither created nor adopted),
  emit a single clear summary listing every such resource by name and
  promote the exit code (FR-011). The config write-back
  (`seed::write_config_uuids`) and its splicer remain UNCHANGED — the
  captured shape is identical across scopes/paths (FR-008). File:
  `src/seed.sh`. (FR-011, FR-008)

## Phase 6: Tests — unit

- [ ] T050 [P] New `tests/unit/seed_scope.bats`: (a) team-scoped
  `create_label` includes `teamId` in the mutation body; workspace scope
  omits it; (b) `seed::resolve_scope` precedence (flag > config >
  default); (c) the find-by-name probe captures an existing UUID with NO
  create mutation (adopt); (d) a `permission`-class create emits the
  actionable hint naming the resource + adopt path; (e) the
  could-not-provision listing names every unresolved persisted resource.
  Source `src/seed.sh` (source-safe under the `BASH_SOURCE==$0` guard).
  File: `tests/unit/seed_scope.bats`. (FR-001, FR-002, FR-004, FR-005,
  FR-011)
- [ ] T051 [P] Extend `tests/unit/graphql.bats`: `graphql::mutate_capture`
  classifies 403 → `permission`, 429 → `limit`, 200+errors[] → `graphql`,
  curl-fail/5xx → `transport`, and 200-clean → `ok` with the response
  echoed; and it returns 0 in every case (non-fatal). File:
  `tests/unit/graphql.bats`. (FR-004)
- [ ] T052 [P] Extend `tests/unit/config.bats`: `config::get_seed_scope`
  returns the configured value, returns the default `team` when the block
  is absent, and halts (exit 2) on an invalid value. File:
  `tests/unit/config.bats`. (FR-005, FR-013)

## Phase 7: Tests — integration

- [ ] T060 [P] New `tests/integration/us5b-seed-team-scoped.bats` (US1):
  with `--scope team`, every `issueLabelCreate` mutation body carries the
  team UUID as `teamId`, workflow states are created team-scoped, all
  UUIDs are captured into config, and no workspace-scoped label create is
  issued. Exit 0. File: `tests/integration/us5b-seed-team-scoped.bats`.
  (FR-001, FR-009, SC-001)
- [ ] T061 [P] New `tests/integration/us5b-seed-adopt.bats` (US2): with
  all required workflow states + labels pre-existing (locate returns one
  node each), the run captures every persisted UUID and issues ZERO
  create mutations, reporting them as adopted. A partial-existing variant
  adopts the present ones and reports the missing ones by name. File:
  `tests/integration/us5b-seed-adopt.bats`. (FR-002, FR-003, SC-002,
  SC-005)
- [ ] T062 [P] New `tests/integration/us5b-seed-permission.bats` (US3):
  a create that returns HTTP 403 (permission) produces a message naming
  the resource + the adopt/team-scoped path, and the run falls back to
  adopting the probed existing resource rather than hard-failing. File:
  `tests/integration/us5b-seed-permission.bats`. (FR-004, FR-006, SC-003)

## Phase 8: ANALYZE + gates

- [ ] T070 Run the ANALYZE consistency pass across spec.md / plan.md /
  tasks.md; fix any drift (terminology, FR coverage, scope claims) before
  IMPLEMENT is considered done.
- [ ] T071 Run all gates green: `shellcheck --shell=bash --severity=style`
  on every changed `src/*.sh`; `bats tests/unit/`; the relevant
  integration suites (`RUN_INTEGRATION_TESTS=1 bats
  tests/integration/us5b-*.bats tests/integration/us4-seed-*.bats`);
  `yamllint -d relaxed` on changed YAML; `npx --yes markdownlint-cli2` on
  changed Markdown.

## Dependencies

- Phase 2 (`config::get_seed_scope`) precedes Phase 4 scope resolution.
- Phase 3 (`mutate_capture`) precedes Phase 5 permission handling.
- Phase 4 (scope + team-scoped labels) precedes Phase 5 (adopt/deny
  routing reuses the scoped create).
- Phases 6–7 (tests) follow the source they cover, but the test FILES are
  `[P]` against each other (disjoint paths).
- Phase 8 is last.
