# Implementation Plan: Team-scoped / non-admin seeding

**Branch**: `005-team-scoped-seeding` | **Date**: 2026-06-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification at `specs/005-team-scoped-seeding/spec.md` (15 FRs, 6 SCs)

## Summary

Make `/speckit.linear.seed` usable by a sub-team owner who lacks
workspace-admin (issue #41). Today the seed step creates labels
**workspace-scoped** (`teamId` omitted) and workflow states team-scoped,
and BOTH the workspace-label create and the workflow-state create require
permissions a sub-team owner may not hold. When a create fails the
operator gets a cryptic raw GraphQL error and is stuck.

This feature adds three cooperating mechanics, all built on spec 004's
new config loader and the existing UUID-capture-into-config behaviour:

- **Team-scoped seed mode** — a new `linear.seed.scope` config option
  (`workspace` | `team`, default `team`). In `team` scope, label creation
  passes `teamId` so the labels are created scoped to the operator's team
  and need only team-level permission (workflow states already take a
  team). `workspace` scope preserves today's behaviour byte-for-byte.
- **Adopt-existing path** — when a required workflow state or label
  already exists (matched by canonical name within scope), CAPTURE its
  UUID instead of creating it. Requires zero create permission. This is
  already half-built: the idempotency probe already finds-and-captures
  existing workflow-state UUIDs; we extend the same find-or-adopt logic to
  the resources the bridge persists and make "adopt" a first-class,
  reported outcome (distinct from the existing "skipped" line).
- **Graceful permission handling + auto-fallback** — a create call that
  fails with a *permission* or *limit* error is classified (not a blanket
  transport error) and turned into an actionable message naming the
  resource, the failure kind, and the adopt / team-scoped path. Under the
  default auto-detect, that classification triggers a per-resource
  fallback to adopt rather than a hard fail.

Idempotency, drift-awareness, fail-closed writes, the dry-run preview,
the UUID-capture-into-config shape, and `extension.id == linear` are all
preserved unchanged.

## Technical Context

**Language/Version**: Bash 4+ (existing bridge runtime; macOS bash 3.2
is rejected at install per FR-018b).
**Primary Dependencies**: `bash`, `curl`, `jq`, `git` — **no new deps**.
The scope option is parsed by the SAME shallow YAML reader already in
`src/config.sh`; permission-error classification is a `jq` inspection of
the GraphQL error envelope inside `src/graphql.sh`. `yq` stays out per
the existing plan §Technical Context.
**Storage**: consumer-repo filesystem only (the committed
`linear-config.yml`). No backend, no daemon, no DB (constitution
Architectural Constraints).
**Testing**: `bats` (unit + integration), `shellcheck --shell=bash
--severity=style` (CI severity), `yamllint -d relaxed`,
`markdownlint-cli2`.
**Target Platform**: operator workstations (macOS / Linux) + GitHub
Actions runner (Layer E unchanged by this feature).
**Project Type**: single bash project (`src/*.sh` + `tests/`).
**Performance Goals**: unchanged — seed latency is dominated by Linear
round-trips. Adopt adds no extra calls (it reuses the existing
find-by-name probe that already runs before every create).
**Constraints**: idempotency (Principle II), drift-awareness (Principle
IV / FR-014), fail-closed writes, dry-run preview, `extension.id ==
linear`. The captured-UUID config shape (FR-008) MUST be identical
across scopes and paths.
**Scale/Scope**: one config per consumer repo; the resource set is the
fixed 9 workflow states + 9 `phase:*` + 9 `task-phase:*` + 2 `agent:*`
labels + 3 default states the bridge already seeds.

## What "the bridge depends on" means for capture (FR-008 scope)

FR-008 / SC-005 require that "every workflow-state and label UUID the
bridge depends on" is written to config in the same shape regardless of
create-vs-adopt or scope. The resources whose UUIDs the bridge persists
(and therefore *depends on* at runtime) are exactly the three captured
maps today:

- `linear.workflow_state_uuids` (9 lifecycle states),
- `linear.default_state_uuids` (3 stock team states), and
- `linear.agent_label_uuids` (2 `agent:*` families).

The `phase:*` / `task-phase:*` label families are deliberately NOT
persisted — reconcile looks them up by name (workspace/team-stable), so
the bridge does not depend on their UUIDs in config. Adopt therefore
captures the SAME three maps a create-based seed captures; the captured
key set is identical between scopes and paths (SC-005). This keeps the
captured-config shape unchanged and the existing
`seed::write_config_uuids` splicer untouched.

## Seed scope as config (new `linear.seed.scope`)

```yaml
linear:
  seed:
    scope: team        # workspace | team   (default: team)
```

- Parsed by the existing shallow reader; surfaced by a new
  `config::get_seed_scope` getter that returns the configured value or
  the documented default `team` when the block is absent (so a pre-005
  config keeps working without an edit — FR-013).
- Honoured by `seed.sh`: `team` scope passes `teamId` to label creation
  (FR-001); `workspace` scope omits it exactly as today (FR-013).
- A `--scope workspace|team` CLI flag overrides config (operator escape
  hatch / install non-interactive path), mirroring how `--team` overrides
  `linear.team.id`.

## Permission/limit classification (new `graphql::mutate_capture`)

`graphql::mutate` exits on auth/4xx/GraphQL errors — correct for the
fail-closed reconcile path, but the seed adopt-fallback needs to *catch*
a permission/limit failure and re-route without the script dying. Today
`seed::create_*` already wraps the call in `if ! response=$(...)`, which
catches the subshell exit, but cannot tell a permission denial from a
5xx.

Add a non-fatal companion in `src/graphql.sh` (keys-at-the-edges stays
intact — the key never leaves this module):

```
graphql::mutate_capture <mutation> <vars>
  → always returns 0; prints a JSON envelope on stdout:
      { "ok": true,  "class": "ok",         "response": { … } }
      { "ok": false, "class": "permission", "message": "…" }
      { "ok": false, "class": "limit",      "message": "…" }
      { "ok": false, "class": "transport",  "message": "…" }
      { "ok": false, "class": "graphql",    "message": "…" }
```

Classification rules (FR-004, spec Assumption "detectable from the
tracker's error response"):

| Signal | Class |
|---|---|
| HTTP 401 / 403, or a GraphQL error whose code/type/message matches `forbidden` / `access denied` / `not authorized` / `permission` / `admin` | `permission` |
| HTTP 429, or a GraphQL error matching `rate limit` / `limit exceeded` / `too many` | `limit` |
| curl failure, unparseable status, 5xx after retry | `transport` |
| other GraphQL `errors[]` on 200 | `graphql` |
| 2xx, no `errors[]` | `ok` |

Ambiguous failures fall through to `transport` / `graphql` and the
existing fail-closed behaviour (spec Assumption) — they are NOT
misclassified as adoptable. Only `permission` / `limit` trigger the
adopt fallback + actionable message.

`graphql::mutate` keeps its current exit-on-error contract for every
existing caller (reconcile, the create paths that don't want fallback);
`mutate_capture` is purely additive.

## Seed control flow (per family, per FR-012)

Each resource family (workflow states, labels) is handled on its own
merits — create what it can, adopt/report the rest — never gated
all-or-nothing on one permission check (FR-012, edge "mixed
creatability").

```
for each required resource in family:
    uuid = find_by_name(scope)         # the existing probe
    if uuid present (exactly one):
        capture uuid → report "adopted"      # FR-002, FR-003
    elif uuid ambiguous (≥2 matches):
        warn + skip (no arbitrary capture)   # FR-010
    else:                                     # not found
        if create permitted (scope path):
            result = mutate_capture(create…)
            if result.ok:        capture → report "created"
            elif permission/limit:
                actionable message (names resource + adopt path)   # FR-004
                record as "could-not-create" for this resource     # FR-011
            else: fail closed (transport/graphql)                  # FR-014
        else (adopt-only, no create attempted):
            record as "not-found" (by name)                        # US2 AS#2
```

At end of run, if any required *persisted* resource (the three captured
maps) could be neither created nor adopted, emit a single clear summary
listing every such resource by name (FR-011, edge "nothing pre-existing
and no create permission") and exit non-zero — never a cryptic failure.

### Auto-detect / fallback (FR-006)

Default scope is `team` with auto-fallback to adopt. "Auto-fallback" is
realised by the per-family flow above: a `permission`/`limit` class on a
create automatically routes that resource to its adopt/report branch and
records which path was taken, rather than aborting the whole run. The
summary reports the path (e.g. "labels: 6 adopted, 3 created" or
"workflow states: create denied → adopted existing"). No separate
two-pass retry is needed because the find-by-name probe already runs
before every create, so the existing-resource UUID is already in hand
when a create is denied.

## Source functions that change

| File | Function | Change |
|------|----------|--------|
| `src/config.sh` | const | add `CONFIG_SEED_SCOPE_DEFAULT="team"` + `CONFIG_SEED_SCOPES=(workspace team)` |
| `src/config.sh` | `config::get_seed_scope` (new) | echo `linear.seed.scope` if present + valid; else the default `team`; halt on an invalid value (Principle VIII) |
| `src/graphql.sh` | `graphql::_classify_error` (new, internal) | map an HTTP status + body to one of `ok`/`permission`/`limit`/`transport`/`graphql` |
| `src/graphql.sh` | `graphql::mutate_capture` (new, public) | non-fatal mutate; prints the classification envelope; key stays in-module |
| `src/seed.sh` | CLI | add `--scope workspace|team` flag + usage text |
| `src/seed.sh` | `seed::resolve_scope` (new) | precedence: `--scope` flag → `config::get_seed_scope` → default `team` |
| `src/seed.sh` | `seed::create_label` | accept a scope arg; in `team` scope add `teamId` to `IssueLabelCreateInput` (FR-001); route through `mutate_capture`; classify permission/limit |
| `src/seed.sh` | `seed::create_workflow_state` | route through `mutate_capture`; classify permission/limit (workflow states are already team-scoped) |
| `src/seed.sh` | `seed::adopt_or_report` (new helper) | shared "found → adopt+report / not-found → record" used by both families |
| `src/seed.sh` | `seed::reconcile_workflow_states` | on create-denied, fall back to the already-probed existing UUID (adopt) or record could-not-provision |
| `src/seed.sh` | `seed::reconcile_labels` / `seed::reconcile_agent_labels` | pass scope to `create_label`; adopt-on-denied; capture agent-label UUIDs unchanged |
| `src/seed.sh` | `seed::permission_hint` (new) | the single actionable message body (names resource + kind + adopt / `--scope team` path) reused by every create-denied site (FR-004) |
| `src/seed.sh` | `main` | resolve scope, log it; after both families, emit the could-not-provision summary if any persisted resource is unresolved (FR-011) and promote exit code |
| `config-template.yml` | — | add the `linear.seed.scope` option (documented default `team`) |
| `README.md` | — | NEW localized "Non-admin / team-scoped seeding" subsection under Configuration: the scope option, the adopt path, and the per-path permission table (FR-015, SC-006). Kept distinct from parser/reconcile sections to avoid conflict with the sibling PR (006). |

Note: `seed::write_config_uuids` and the captured-map renderers are
UNCHANGED — the captured shape is identical across scopes/paths (FR-008),
so the splicer (and its #33/#39/#40 regression cover) is untouched.

## Constitution Check

Checked against `.specify/memory/constitution.md` v2.0.0 (8 principles).

- **I — Filesystem is truth**: unchanged. Seed still only writes UUIDs
  it captured from Linear back into the committed config; no Linear→spec
  flow. PASS.
- **II — Reconcile, never event-push**: PRESERVED. Seed stays a
  converge-from-any-state operation: find-or-(create|adopt) per resource,
  safe to re-run, zero churn on a no-op (FR-007). No per-event diff, no
  sidecar cache. Stable identity still derives from filesystem-evident
  keys (the seeded UUID). PASS.
- **III — Layered idempotency (D+E)**: unchanged. Seed is an install-time
  Layer-D helper; Layer E is untouched (the spec explicitly scopes this
  to seeding only). PASS.
- **IV — Write-authority follows the filesystem (drift-aware)**:
  unchanged. Seed is not a spec-level reconcile write; FR-014 keeps
  drift-awareness, fail-closed writes, and the dry-run preview intact for
  the reconcile path. PASS.
- **V — UUID-based binding, per-repo config**: STRENGTHENED. Both the
  created and the adopted paths capture UUIDs into the committed per-repo
  config; lookups stay UUID-based, never by name (the adopt MATCH is by
  name, but what is persisted and later looked up is the UUID). No
  per-operator global state introduced. Seed still captures every
  persisted UUID at resolution time with no post-seed name fallback. PASS.
- **VI — OAuth-first, keys-at-the-edges**: PRESERVED. The new
  `mutate_capture` lives inside `graphql.sh`; the API key never leaves
  that module. Seed remains one of the two legitimate key-using edges
  (Principle VI Rule 3). No key is committed or globalised. PASS.
- **VII — Memory-just-works**: unchanged. No hook-registration change;
  `/speckit.linear.*` surface unchanged. The scope option is config, not
  a new command. PASS.
- **VIII — Surface, don't enforce; observable failure**: REINFORCED.
  This feature's whole point is replacing a cryptic hard-fail with a
  named, actionable message (FR-004) and a clear could-not-provision
  listing (FR-011). Ambiguous adopt matches warn-and-skip rather than
  guess (FR-010). Every create/adopt/skip/deny flows through `summary::*`.
  Canonical vocabulary (`task-phase:N`, `Phase N`) retained. PASS.

**Result**: No principle is violated; Principles V and VIII are better
satisfied. No data-model mapping change, no new layer, no new dependency
— no amendment required. The Constitution Check gate is GREEN.

## Project Structure

### Documentation (this feature)

```
specs/005-team-scoped-seeding/
├── spec.md
├── plan.md              # this file
├── tasks.md             # /speckit.tasks output
└── checklists/
    └── requirements.md
```

### Source (existing files touched — no new modules)

```
src/
├── seed.sh         # scope option, team-scoped labels, adopt path,
│                   # permission classification + actionable message
├── config.sh       # config::get_seed_scope + default
└── graphql.sh      # graphql::mutate_capture + _classify_error (non-fatal)
config-template.yml # linear.seed.scope option documented
README.md           # localized non-admin / team-scoped seeding subsection
tests/
├── unit/
│   ├── seed_scope.bats        # new: team-scoped label teamId, scope
│   │                          #      resolution, adopt capture, permission
│   │                          #      hint, could-not-provision listing
│   ├── graphql.bats           # extend: mutate_capture classification
│   ├── config.bats            # extend: get_seed_scope + default
│   └── seed_write_config.bats # still green (splicer untouched)
└── integration/
    ├── us5b-seed-team-scoped.bats    # new: team scope passes teamId
    ├── us5b-seed-adopt.bats          # new: adopt captures w/o create
    ├── us5b-seed-permission.bats     # new: denied create → message + fallback
    └── us4-seed-*.bats               # existing seed suites stay green
```

(The `us5b-` prefix avoids colliding with the existing `us5-retroactive`
integration file from spec 003.)

## Complexity Tracking

No constitutional deviations. No new dependencies, no new architectural
layers, no data-model change. The work is contained to three existing
`src/*.sh` modules, the config template, a localized README subsection,
and tests. The captured-config shape and its splicer are untouched, so
the #33/#39/#40 duplicate-key regression cover continues to hold.
