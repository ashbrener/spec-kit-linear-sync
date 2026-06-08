# Implementation Plan: Config / identity split

**Branch**: `004-config-identity-split` | **Date**: 2026-06-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification at `specs/004-config-identity-split/spec.md` (11 FRs, 5 SCs)

## Summary

Split the per-repo Linear binding into two files so the shareable
binding can be committed safely while each operator's identity stays
local:

- **`linear-config.yml`** (committed) keeps ONLY the shareable binding —
  team/project UUIDs, `workflow_state_uuids`, `default_state_uuids`,
  `agent_label_uuids`, workspace info, and the behaviour toggles.
- **`linear-operator.local.yml`** (gitignored) holds the per-operator
  identity (`user_id`, `name`, `email`).

The reconciler resolves the operator assignee through a documented
cascade — environment → operator-local file → (interactive prompt) —
and NEVER from the committed config. A legacy single-file config that
still carries `operator.*` keys is migrated once, idempotently, with a
single notice. The doc-vs-`.gitignore` contradiction (`linear-config.yml`
is documented as committed but currently gitignored) is resolved by
REMOVING the `linear-config.yml` ignore entry and ignoring the new
operator-local file instead.

## Technical Context

**Language/Version**: Bash 4+ (existing bridge runtime; macOS bash 3.2
is rejected at install per FR-018b).
**Primary Dependencies**: `bash`, `curl`, `jq`, `git` (no new deps —
the operator-local file is parsed by the SAME shallow awk/sed YAML
reader already in `src/config.sh`; `yq` stays out per the existing
plan §Technical Context).
**Storage**: consumer-repo filesystem only (two YAML files under
`.specify/extensions/linear/`). No backend, no daemon, no DB
(constitution Architectural Constraints).
**Testing**: `bats` (unit + integration), `shellcheck`, `yamllint -d
relaxed`, `markdownlint-cli2`.
**Target Platform**: operator workstations (macOS / Linux) + GitHub
Actions runner (Layer E, env-var key path).
**Project Type**: single bash project (`src/*.sh` + `tests/`).
**Performance Goals**: unchanged — reconcile latency budget is
dominated by Linear round-trips; the extra local-file read is a single
`[[ -f ]]` + shallow parse, negligible.
**Constraints**: idempotency (Principle II), drift-awareness (SC-017 /
Principle IV), fail-closed writes, `extension.id == linear`,
`/speckit.linear.*` surface unchanged (FR-009, FR-010).
**Scale/Scope**: one config + one operator file per consumer repo.

## The two-file model

### File 1 — `linear-config.yml` (committed, shareable binding)

Path: `.specify/extensions/linear/linear-config.yml` (unchanged).
Contents after this feature:

```yaml
schema_version: 1
config_version: 2          # bumped: operator block removed
linear:
  workspace: { name, url_key }      # informational
  team: { id, key, name }           # id is authoritative
  project: { id, name }             # id is authoritative
  workflow_state_uuids: { … 9 … }   # seeded
  default_state_uuids: { … 3 … }    # seeded
  agent_label_uuids: { claude, codex }
sync: { enabled, idle_window_days, emit_summary }
webhook: { … }
git_hooks: { … }
```

The `linear.operator` block is REMOVED from the committed template.
There is no operator-identifying data anywhere in this file (SC-002).

### File 2 — `linear-operator.local.yml` (gitignored, operator identity)

Path: `.specify/extensions/linear/linear-operator.local.yml`.
The `*.local.yml` suffix is matched by one `.gitignore` glob so any
future operator-local sibling is covered by the same entry.

```yaml
# spec-kit-linear — operator-local identity (NEVER COMMIT)
schema_version: 1
operator:
  user_id: "…"   # UUID — Linear assignee
  name:    "…"   # informational
  email:   "…"   # informational, used in the memory block "last touched by"
```

Rationale for the path/name (spec Assumptions): lives alongside the
shared config under `.specify/extensions/linear/`; the `*.local.*`
shape is the conventional "operator-local, never commit" marker and
collapses to a single `.gitignore` glob.

## Resolution cascade (identity + key)

Both operator identity and the API key resolve through the SAME
documented precedence (FR-005, FR-006):

```
1. environment      (highest — CI / ephemeral override)
2. operator-local file
3. interactive prompt (TTY only; non-interactive skips)
```

### Identity cascade (new `config::resolve_operator_user_id`)

| Step | Source | Notes |
|------|--------|-------|
| 1 | `LINEAR_OPERATOR_USER_ID` env var | highest precedence (matches `LINEAR_API_KEY` env-first convention) |
| 2 | `operator.user_id` in `linear-operator.local.yml` | the local file |
| 3 | interactive prompt | only on a TTY; non-interactive falls through |
| — | none resolved | warn once + proceed UNASSIGNED (FR-011) — never fail |

Name/email follow the same file/env sourcing for the memory-block
"last touched by" cell; they are informational and never gate a sync.

### Key cascade (unchanged behaviour, documented + extended)

`graphql::_load_api_key` already does env → `.env`. We extend it to
also read `LINEAR_API_KEY` from the operator-local file as a middle
tier so a worktree with no per-worktree `.env` can still authenticate
when the key lives in the discoverable local file (FR-006, US4). Order:
env → operator-local file → `.env` → (interactive, install path only).

## Migration mechanism (legacy `operator.*` → local file)

Triggered lazily on `config::load` (so BOTH reconcile and install hit
it) when the committed `linear-config.yml` still carries `operator.*`
keys:

1. Detect `linear.operator.user_id` (or name/email) present in the
   loaded committed config.
2. If `linear-operator.local.yml` does NOT already exist, write it from
   the legacy values (the local file is authoritative if it already
   exists — edge case in spec; legacy values are then just dropped).
3. Strip the `operator:` block from `linear-config.yml` in place
   (awk, same portable style as the existing field substituters).
4. Emit EXACTLY ONE migration notice (a one-shot latch keyed on a
   module global so a single process never repeats it; idempotent
   across runs because step 3 removes the trigger).

Idempotency: once the `operator:` block is gone from the committed
config, the detector never fires again — no repeat notice (FR-007,
SC-003). The migration is one-way (spec Assumptions).

## Source functions that change

| File | Function | Change |
|------|----------|--------|
| `src/config.sh` | module state | add `CONFIG_OPERATOR_VALUES` + `CONFIG_OPERATOR_LOADED_PATH`; add `CONFIG_OPERATOR_LOCAL_PATH_DEFAULT` const; add `_CONFIG_MIGRATION_NOTICE_EMITTED` latch |
| `src/config.sh` | `config::load` | after parsing committed file, run `config::_maybe_migrate_operator_block`, then load the operator-local file if present |
| `src/config.sh` | `config::_load_operator_file` (new) | parse `linear-operator.local.yml` into `CONFIG_OPERATOR_VALUES` (reuses `_parse_file` machinery via a second array) |
| `src/config.sh` | `config::_maybe_migrate_operator_block` (new) | detect legacy `operator.*`, write local file, strip block, one-shot notice |
| `src/config.sh` | `config::resolve_operator_user_id` (new) | the env → local-file cascade (interactive prompt deferred to caller/install); NEVER reads committed config |
| `src/config.sh` | `config::get_operator_user_id` / `_name` / `_email` | re-point to the operator-local store (back-compat: still echo empty, no halt) |
| `src/reconcile.sh` | `reconcile::_resolve_operator_assignee_id` | call `config::resolve_operator_user_id` (cascade) instead of `config::get_operator_user_id` (committed-config read) |
| `src/reconcile.sh` | memory block `operator_email` | source via the cascade-backed getter |
| `src/graphql.sh` | `graphql::_load_api_key` | insert operator-local-file tier between env and `.env` |
| `src/install.sh` | const | add `INSTALL_OPERATOR_LOCAL_PATH` |
| `src/install.sh` | `install::write_config` | stop writing the `operator:` block into the committed config; instead call `install::_write_operator_local_file` |
| `src/install.sh` | `install::_write_operator_local_file` (new) | scaffold `linear-operator.local.yml` with resolved identity |
| `src/install.sh` | `install::_ensure_operator_local_gitignored` (new) | ensure `.specify/extensions/linear/*.local.yml` is in `.gitignore`; add if absent (FR-003) |
| `src/install.sh` | `install::main` | call the two new helpers after `write_config` |
| `config-template.yml` | — | remove `operator:` block; bump `config_version`; document the two-file model + which file is committed |
| `.gitignore` | — | REMOVE `linear-config.yml` ignore; ADD `.specify/extensions/linear/*.local.yml` |
| `README.md` | — | document the two-file model, cascade, and commit policy |

Back-compat getters (`config::get_operator_*`) keep their signatures
and empty-on-absence contract so any caller (and tests) that still
calls them keeps working; they now read the operator-local store.

## Constitution Check

Checked against `.specify/memory/constitution.md` v2.0.0 (8 principles).

- **I — Filesystem is truth**: unchanged. The bridge still never writes
  back to the spec corpus from Linear. The migration writes the
  operator-local file and edits the committed config, both filesystem-
  side install/config concerns, not a Linear→FS flow. PASS.
- **II — Reconcile, never event-push**: unchanged. Identity is resolved
  fresh each run from the cascade; no diff cache, no sidecar "last
  seen". The operator-local file is configuration, not a per-event
  cache. Stable identity still derives from filesystem-evident keys.
  PASS.
- **III — Layered idempotency (D+E)**: unchanged. Layer boundaries
  untouched; this is a config/identity change only. Migration is
  idempotent. PASS.
- **IV — Write-authority follows the filesystem (drift-aware)**:
  unchanged. No change to drift detection, the warn-don't-block
  disposition, or SC-017. FR-009 preserves it explicitly. PASS.
- **V — UUID-based binding, per-repo config**: STRENGTHENED. Principle
  V's rule "Per-operator global config … is forbidden" is honoured —
  the operator-local file is per-REPO (under the repo's
  `.specify/extensions/linear/`), not a `~/.config/` global. Cloning
  the repo + supplying the operator's own identity (env or local file)
  is sufficient to drive sync; the committed binding alone makes a
  clone sync-ready (it just creates issues unassigned until the
  operator supplies identity, per FR-011). Runtime lookups stay
  UUID-based. PASS — note this resolves the prior latent violation
  where the committed config carried operator identity yet was meant
  to be self-describing-and-shareable.
- **VI — OAuth-first, keys-at-the-edges**: PRESERVED. Interactive
  paths still use the official MCP and never prompt for a key on the
  reconcile path. The key cascade only documents and extends the
  existing env/`.env` edge sourcing (adds the operator-local tier);
  the key is still never committed or globalised — the operator-local
  file is gitignored exactly like `.env`. PASS.
- **VII — Memory-just-works**: unchanged. No hook registration change;
  `/speckit.linear.*` surface unchanged (FR-010). PASS.
- **VIII — Surface, don't enforce; observable failure**: PRESERVED and
  reinforced. No-identity is surfaced as a WARNING and the sync
  proceeds unassigned (FR-011) — never a silent skip, never a hard
  fail. The migration emits exactly one structured notice. Malformed
  operator-local file surfaces the same clear diagnostic the config
  loader emits (edge case). Canonical vocabulary retained. PASS.

**Result**: No principle is violated; Principle V's intent is better
satisfied after the split. No amendment required. The Constitution
Check gate is GREEN.

## Project Structure

### Documentation (this feature)

```
specs/004-config-identity-split/
├── spec.md
├── plan.md              # this file
├── tasks.md             # /speckit.tasks output
└── checklists/
    └── requirements.md
```

### Source (existing files touched — no new modules)

```
src/
├── config.sh        # operator-local store, migration, cascade resolver
├── reconcile.sh     # assignee resolution via cascade
├── graphql.sh       # key cascade gains operator-local tier
└── install.sh       # scaffold local file + gitignore entry; stop writing operator block
config-template.yml  # operator block removed; two-file model documented
.gitignore           # un-ignore linear-config.yml; ignore *.local.yml
README.md            # two-file model + cascade + commit policy
tests/
├── unit/
│   ├── config.bats                 # extend: no operator.*, migration, cascade
│   ├── install_config_split.bats   # new: local-file scaffold + gitignore
│   └── no-real-identifiers.bats    # still green (template has no identity)
└── integration/
    └── (existing safety suites stay green)
```

## Complexity Tracking

No constitutional deviations. No new dependencies. No new architectural
layers. The change is contained to four existing `src/*.sh` modules,
two config/docs files, `.gitignore`, and tests.
