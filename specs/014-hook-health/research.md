# Phase 0 Research: Hook Self-Healing

**Feature**: 014-hook-health | **Date**: 2026-06-24

All spec clarifications were resolved during `/speckit-specify` + `/speckit-clarify`
(Sessions 2026-06-23 and 2026-06-24). No `NEEDS CLARIFICATION` markers remain in the
Technical Context. The decisions below resolve the **implementation** unknowns the
plan surfaced.

---

## R1 — Hook classification: present / disabled / absent

**Decision**: A per-hook three-state classifier. For each of the six `after_*`
names, walk `.specify/extensions.yml` and return exactly one of:

- `present` — the 2-space-indented `<hook>:` block contains an `extension: linear` entry that is
  NOT `enabled: false`.
- `disabled` — that linear entry exists but carries `enabled: false`.
- `absent` — no linear entry under that hook (key missing, or present with only
  non-linear extensions).

Only `absent` counts as "missing" for the warning (FR-004: `disabled` is intentional).

**Rationale**: The spec needs three states, not the install path's two
(`registered` vs not). Install's `install::_hook_already_registered` answers "is there
a linear entry" but ignores `enabled:`. We extend the same block grammar to also read
the `enabled:` line so `disabled` is distinguishable from `present`.

**Alternatives considered**: A YAML parser dependency (`yq`) — rejected, violates
FR-008 "no new runtime dependency". Reusing `_hook_already_registered` verbatim —
rejected, it can't see `enabled: false`, so it would wrongly count a disabled hook as
present (acceptable for "not absent") but can't drive the status `disabled` reporting.

---

## R2 — Detection grammar (awk), mirrors install

**Decision**: One `awk` pass per hook anchored exactly like
`install::_hook_already_registered` (src/install.sh:1800): enter the block on a line
matching `^  <hook>:`, leave it on the next top-level-2-space key
`^  [a-zA-Z_]+:[[:space:]]*$`, and inside the block detect `extension:[[:space:]]*linear`
and `enabled:[[:space:]]*false`. The classifier reports `disabled` if the linear entry
is seen together with `enabled: false` in the same block, else `present`; `absent` if
no linear entry seen.

**Rationale**: Byte-for-byte the same block-boundary grammar install uses to write and
de-dupe hooks guarantees **detection and restore agree** (FR-007, SC-004) — the same
notion of "linear is registered under hook X". A single shared grammar avoids
false-positive/negative skew between the writer and the reader.

**Edge**: a hook block listing multiple extensions (e.g. `git` + `linear`) — the walk
only sets state from the linear entry; the git entry is ignored. Hand-edited files
with the linear entry but no `extension:` line → treated as absent (no linear anchor).

---

## R3 — Self-heal integration: reuse install's writer without source pollution

**Decision**: The consented self-heal calls **`install::register_after_hooks`**
(src/install.sh:1739) — it is already idempotent, adds only absent hooks, and
preserves any `enabled: false` (src/install.sh:1772 short-circuits on
`_hook_already_registered`). To make install's functions callable from
`reconcile.sh`/`status.sh` without the double-source `readonly` hazard (install.sh
re-`source`s summary/git_helpers/graphql, which reconcile/status already sourced),
add **idempotent include-guards** to the shared libs and to install.sh:

```bash
[[ -n "${_HOOKCHECK_SH_LOADED:-}" ]] && return 0
readonly _HOOKCHECK_SH_LOADED=1
```

`src/hookcheck.sh` lazily `source`s `install.sh` only when an accepted self-heal needs
the writer (keeping the warn/detection path dependency-light), relying on the guards so
re-sourcing summary/git_helpers/graphql is a no-op.

**Rationale**: Re-implementing the YAML writer in hookcheck would duplicate fragile
append/create logic and risk drifting from install's grammar (defeating FR-007). The
include-guard is a small, broadly-beneficial hardening that makes the modules safely
composable; install.sh's `main` is already guarded
(`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, src/install.sh:3667), so sourcing it runs no
side effects.

**Alternatives considered**:
- **Subprocess** `bash install.sh <reinstall>` — rejected: install's `main` runs full
  dependency/config verification and prompts, far more than a hook re-register; no
  narrow flag exists today.
- **Add a narrow `--register-hooks-only` flag to install.sh** — viable, but a larger
  surface change than include-guards; deferred unless the guard approach hits a snag
  in `/speckit-analyze`.

**Guard scope**: add guards to `summary.sh`, `git_helpers.sh`, `graphql.sh`,
`config.sh`, `parser.sh`, `install.sh`, `hookcheck.sh`. Each guard is a 2-line no-op
on second source; existing single-source callers are unaffected. This is the one piece
to re-validate in analyze (cross-file shellcheck + full bats run).

---

## R4 — Interactivity detection + consent prompt

**Decision**: Reuse the spec-003 `--on-drift` prompt precedent
(src/reconcile.sh:4258, 4346): treat the run as interactive when `[[ -t 0 ]]`, and
read the y/N answer from `/dev/tty` (overridable via an env var for tests, mirroring
`RECONCILE_DRIFT_TTY`). Default on empty/EOF/non-`y` = **decline** (no-op + warning).
Non-interactive (`[[ ! -t 0 ]]`, CI / hook-fired) → never prompt, never mutate
(FR-009, Out-of-Scope).

**Rationale**: There is an established, tested pattern in this codebase for an
interactive proceed/abort prompt over `/dev/tty` (not inherited stdin). Matching it
keeps behavior and testing consistent and satisfies "interactive only, consented".

**Prompt shape**: a single y/N covering ALL missing hooks at once (clarification
2026-06-24): e.g. `Re-register N missing auto-sync hook(s) now? [y/N]`.

---

## R5 — Malformed / unreadable / absent extensions.yml

**Decision**:
- **No `.specify/extensions.yml`** → out of scope to nag (the bridge-not-installed
  path); emit no hook-health warning (spec Edge Cases).
- **Present but unreadable/malformed** → degrade to an informational
  "could not verify hook health" (`summary::add info`/`warned`, non-blocking), never a
  halt (FR-008, Principle VIII).

**Rationale**: The check must never convert a parse problem into a failed reconcile.
The classifier returns a distinct `unverifiable` sentinel that the caller maps to the
informational message and skips the self-heal offer.

---

## R6 — Guaranteeing detect/restore agreement (FR-007, SC-004)

**Decision**: `hookcheck.sh` defines the six hook names by **sourcing install.sh and
reading `INSTALL_AFTER_HOOK_NAMES`** (the single source of truth), OR, on the
dependency-light detection path, mirrors them in `HOOKCHECK_AFTER_HOOK_NAMES` with a
unit test asserting the two arrays are identical. Chosen: **mirror + pin test**, so
detection needs no install.sh source (keeps the hot path light); a
`tests/unit/hookcheck.bats` case fails if the mirrored list ever drifts from
`INSTALL_AFTER_HOOK_NAMES`.

**Rationale**: Keeps detection zero-dependency while making divergence a red test, not
a silent bug. After a real `/speckit.linear.install`, the same names + same grammar
guarantee a subsequent reconcile sees them all present (SC-004).

---

## R7 — `status` exit code unchanged (FR-006, clarification 2026-06-24)

**Decision**: The hook-health line is appended to `status::emit_human` /
`status::emit_json` output only; it does not call `status::promote_exit` (the existing
exit-code escalator, src/status.sh:166) and does not set any non-zero disposition.
`status` exits exactly as it would without the feature.

**Rationale**: Surface-don't-enforce (Principle VIII) and the explicit clarification
that hook health is informational, not a CI gate. Reusing the existing
`promote_exit` machinery only for genuine errors keeps status's contract stable.

---

## R8 — Warning cadence (once per run, FR-010 / SC-006)

**Decision**: Mirror the existing one-shot-warning latch
(`_RECONCILE_OPERATOR_WARNED` at src/reconcile.sh:175, `_RECONCILE_OVERVIEW_WARNED` at
:203). Add `declare -g _RECONCILE_HOOKS_WARNED=0`; the hook-health check runs once in
`reconcile::main` (after spec enumeration, before/around the per-spec loop) guarded by
the latch so an `--all` sweep warns at most once. `status` runs once by nature (single
emit), so it needs no latch.

**Rationale**: Exactly the established pattern; an `--all` sweep already proves the
latch keeps operator/overview warnings to one row.

---

## Resolved decisions summary

| # | Decision |
|---|----------|
| R1 | Three-state classifier: present / disabled / absent; only absent = "missing". |
| R2 | One `awk` block-walk per hook, same grammar as `install::_hook_already_registered`, extended to read `enabled:`. |
| R3 | Self-heal calls `install::register_after_hooks`; add idempotent include-guards so modules compose safely; lazy-source install.sh on accepted heal. |
| R4 | Interactive = `[[ -t 0 ]]`; consent y/N over `/dev/tty` (env-overridable); default decline; non-interactive never mutates. |
| R5 | No file → no nag; malformed → informational "could not verify", never halt. |
| R6 | Mirror hook names in hookcheck + unit test pinning to `INSTALL_AFTER_HOOK_NAMES`. |
| R7 | Status hook-health is report-only; never touches exit code. |
| R8 | `_RECONCILE_HOOKS_WARNED` once-per-run latch in `reconcile::main`. |
