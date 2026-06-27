# Phase 1 Data Model: Hook Self-Healing

**Feature**: 014-hook-health | **Date**: 2026-06-24

This feature has no persistent data store and no Linear entities. The "data" is the
in-memory assessment of the consumer's local hook registrations. Two conceptual
entities (from spec Key Entities), modeled as Bash values.

---

## Entity: Hook registration (per `after_*` hook)

The state of one of the six `after_*` hooks for the `linear` extension in
`.specify/extensions.yml`.

| Field | Source | Values |
|-------|--------|--------|
| `name` | fixed set | one of `after_specify`, `after_clarify`, `after_plan`, `after_tasks`, `after_implement`, `after_analyze` |
| `state` | classified from file (R1/R2) | `present` \| `disabled` \| `absent` |

**Classification rules** (R1):

- `present` — the 2-space-indented `<name>:` block contains `extension: linear` and NOT `enabled: false`.
- `disabled` — that linear entry exists with `enabled: false` → intentional, NOT missing (FR-004).
- `absent` — no linear entry under `<name>` → counts as **missing** (drives the warning).

**Identity / uniqueness**: the six names are the fixed key set, mirrored from
`install.sh:INSTALL_AFTER_HOOK_NAMES` and pinned by a unit test (R6).

---

## Entity: Hook-health assessment (per run)

The aggregate over all six hooks, computed once per reconcile/status run.

| Field | Type | Meaning |
|-------|------|---------|
| `overall` | enum | `present` (all six present/disabled) \| `partial` (≥1 absent, ≥1 present) \| `none` (all six absent) \| `unverifiable` (malformed file) \| `not_installed` (no extensions.yml) |
| `missing[]` | list of names | the `absent` hooks (named in the warning / status line) |
| `disabled[]` | list of names | the `enabled: false` hooks (reported by status; never warned) |

**State transitions** (assessment per run; no persistence between runs):

```text
read .specify/extensions.yml
  ├─ file absent ........................ overall = not_installed → no warning (out of scope)
  ├─ file unreadable / malformed ........ overall = unverifiable → informational "could not verify"
  └─ file parsed
        classify each of 6 hooks → present | disabled | absent
        ├─ 0 absent ..................... overall = present  → no warning (SC-002)
        ├─ all 6 absent ................. overall = none     → warn + (interactive) offer self-heal
        └─ some absent .................. overall = partial  → warn naming missing + (interactive) offer
```

**Derived outputs**:

- **Reconcile (push)**: when `overall ∈ {partial, none}` → one `summary::add warned`
  row (once per run, FR-010): count + named missing hooks + `/speckit.linear.install`
  remediation. When `unverifiable` → one informational row. Never blocks (FR-003).
- **Status**: a first-class line reflecting `overall` (`present` / `partial` naming
  `missing[]` / `none`), plus `disabled[]` noted as intentional. Exit code unchanged
  (R7).
- **Self-heal (interactive only)**: when `overall ∈ {partial, none}` and `[[ -t 0 ]]`,
  offer a single y/N; on `y`, call `install::register_after_hooks` (re-adds exactly
  `missing[]`, preserves `disabled[]`), then re-assess so a follow-up run reports
  `present` (SC-004).

**Validation rules**: assessment is read-only except the consented self-heal; an
`unverifiable` or `not_installed` overall MUST suppress the self-heal offer and MUST
NOT halt the run.
