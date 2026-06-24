# Contract: `src/hookcheck.sh`

**Feature**: 014-hook-health | **Date**: 2026-06-24

The new module's public surface. CLI tools have no HTTP API; the "contract" is the
function signatures the `reconcile.sh` and `status.sh` entrypoints depend on, plus the
behavioral guarantees tested by `tests/unit/hookcheck*.bats`. All functions are
side-effect-free (read-only) EXCEPT `hookcheck::offer_selfheal`, which mutates only on
explicit interactive consent.

Include-guard at top (R3): `[[ -n "${_HOOKCHECK_SH_LOADED:-}" ]] && return 0; readonly _HOOKCHECK_SH_LOADED=1`.

---

## Constants

```bash
# Mirrors install.sh INSTALL_AFTER_HOOK_NAMES (pinned identical by unit test, R6).
readonly -a HOOKCHECK_AFTER_HOOK_NAMES=(
  after_specify after_clarify after_plan after_tasks after_implement after_analyze
)
# Path to the consumer hook registry; overridable for tests.
: "${HOOKCHECK_EXTENSIONS_YML:=.specify/extensions.yml}"
```

---

## `hookcheck::classify <hook_name> [<yml_path>]`

Classify one hook (R1/R2).

- **stdout**: exactly one of `present` | `disabled` | `absent`.
- **exit**: `0` on a successful classification; `2` if `<yml_path>` exists but is
  unreadable/malformed (caller maps to `unverifiable`); the function never exits the
  process.
- **Guarantees**:
  - `present` ⟺ the 2-space-indented `<hook>:` block contains `extension: linear` without
    `enabled: false`.
  - `disabled` ⟺ that linear entry has `enabled: false` (FR-004).
  - `absent` ⟺ no linear entry under that hook.
  - Uses the SAME block grammar as `install::_hook_already_registered` (FR-007).

## `hookcheck::assess [<yml_path>]`

Aggregate over all six hooks (once per run).

- **stdout**: a single line `overall=<present|partial|none|unverifiable|not_installed>`
  followed by `missing=<space-separated names>` and `disabled=<space-separated names>`
  (machine-readable; exact serialization fixed by tests).
- **exit**: always `0` (non-blocking; `unverifiable`/`not_installed` are values, not
  failures — FR-003/FR-008).
- **Guarantees**: `not_installed` when the file is absent; `unverifiable` when present
  but unparseable; `present` when zero hooks are `absent`; `none` when all six are
  `absent`; `partial` otherwise.

## `hookcheck::warn_once <overall> <missing...>`

Emit the reconcile warning at most once per run (R8, FR-002/FR-010).

- **Effect**: when `overall ∈ {partial, none}` and `_RECONCILE_HOOKS_WARNED == 0`,
  call `summary::add warned "<N> auto-sync hook(s) not registered (<names>); run /speckit.linear.install to restore"`
  and set `_RECONCILE_HOOKS_WARNED=1`. When `overall == unverifiable`, emit one
  informational `summary::add` row instead. When `present`/`not_installed`, emit
  nothing.
- **Guarantees**: never blocks; idempotent within a run (SC-006); zero rows on a clean
  set (SC-002).

## `hookcheck::status_line <overall> <missing...> -- <disabled...>`

Render the status report line (FR-006).

- **stdout**: a human line — `Auto-sync hooks: all present` / `partial — missing: …` /
  `none registered — run /speckit.linear.install` (and notes any `disabled[]` as
  intentional).
- **exit**: always `0`; MUST NOT call `status::promote_exit` (R7) — status exit code
  unchanged.

## `hookcheck::offer_selfheal <overall> <missing...>`

Interactive consented re-registration (FR-009; the ONLY mutating function).

- **Preconditions**: `overall ∈ {partial, none}` AND interactive (`[[ -t 0 ]]`).
  Otherwise returns `0` having done nothing (non-interactive = warn-only).
- **Effect**: prompt a single y/N over `/dev/tty` (env-overridable
  `HOOKCHECK_TTY`, mirroring `RECONCILE_DRIFT_TTY`): `Re-register N missing auto-sync hook(s) now? [y/N]`.
  - On `y`/`Y` → lazy-`source install.sh` (guarded) and call
    `install::register_after_hooks` (adds only `missing[]`, preserves `disabled[]`),
    then `summary::add updated` and re-assess.
  - On anything else / empty / EOF → no-op (decline) + the standing warning.
- **Guarantees**: mutates `.specify/extensions.yml` ONLY on explicit `y`; never
  re-enables an `enabled: false` hook (delegates to install's idempotent path); never
  touches Linear or `specs/**`.

---

## Behavioral contract summary (maps to Success Criteria)

| Function | SC |
|----------|----|
| `assess` + `warn_once` | SC-001 (100% warn when missing), SC-002 (0 false positives), SC-006 (once per run) |
| `warn_once` / `offer_selfheal` non-blocking | SC-003 (never changes exit disposition) |
| `offer_selfheal` → `register_after_hooks` agree with `assess` | SC-004 (post-install: 0 warnings) |
| `status_line` | SC-005 (correct state; status exits 0) |
