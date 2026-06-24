# Implementation Plan: Hook Self-Healing (auto-sync hook health check)

**Branch**: `014-hook-health` | **Date**: 2026-06-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/014-hook-health/spec.md`

## Summary

The community install/update path (`specify extension add linear --from <zip> --force`)
silently strips the bridge's six `after_*` auto-sync hooks from the consumer's
`.specify/extensions.yml`, so auto-sync quietly stops and the board drifts
unnoticed. This feature makes the bridge **self-report its own hook health**: on
every `speckit.linear.push` (reconcile) and `speckit.linear.status`, it classifies
each of the six `after_*` hooks as **present** / **disabled** / **absent**, and when
any are absent emits a single loud, named, once-per-run warning pointing at the
`/speckit.linear.install` fix. `status` adds a first-class hook-health line (and
never changes its exit code). In an **interactive** session, push and status
additionally OFFER a single y/N consented self-heal that re-registers ALL missing
hooks in place; **non-interactive** runs are warn-only and mutate nothing.

Technical approach: a new dependency-light module `src/hookcheck.sh` owns
detection (an `awk` walk of `.specify/extensions.yml` using the SAME block grammar
as install's `install::_hook_already_registered`, extended to read `enabled:`).
The warning rides the existing structured-summary + one-shot-warning machinery
(`summary::add warned` + a `_RECONCILE_HOOKS_WARNED` latch). The consented
self-heal reuses install's idempotent `install::register_after_hooks` (which already
adds only absent hooks and preserves `enabled: false`), invoked behind an
interactivity + `/dev/tty` consent prompt mirroring the spec-003 `--on-drift`
precedent. No Linear calls, no new runtime dependency.

## Technical Context

**Language/Version**: Bash 4.4+ (CI matrix: bash 4.4 + 5.2 on ubuntu, 5.2 on macOS)

**Primary Dependencies**: coreutils + `awk` + `grep` (already required); `jq` (already
required, used only by `status` JSON path). **No new dependency** (FR-008).

**Storage**: consumer repo files only — reads `.specify/extensions.yml`; the
consented self-heal writes `.specify/extensions.yml` (operator-owned config), never
any `specs/**` or Linear state.

**Testing**: `bats` (unit in `tests/unit/`, integration in `tests/integration/`);
`shellcheck --shell=bash --severity=style` over all `src/**` in one invocation.

**Target Platform**: operator workstations (macOS/Linux) running spec-kit; runs
inside `speckit.linear.push` / `speckit.linear.status`.

**Project Type**: single Bash project (CLI/library) — `src/*.sh` modules sourced by
`reconcile.sh` and `status.sh` entrypoints.

**Performance Goals**: negligible — one `awk` pass over a small local YAML per run;
must add no perceptible latency to a reconcile.

**Constraints**: non-blocking in 100% of cases (SC-003); warning at most once per
run (SC-006); zero false positives on a fully-registered or deliberately-disabled
set (SC-002); detection must agree with install's restore (SC-004, FR-007); no Linear
writes; mutate nothing on the warn/non-interactive path (FR-008).

**Scale/Scope**: six fixed hook names; a handful of consumer specs per run. Small,
self-contained surface — one new module + insertion points in `reconcile.sh` and
`status.sh`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

This is an **additive** feature — no principle is redefined or removed, so no
constitutional amendment is required (per the versioning rules, additive guidance is
at most a MINOR doc concern, and this adds no constraint to the constitution itself).

| Principle | Assessment |
|-----------|------------|
| **I. Filesystem is source of truth** | PASS. Detection reads only local `.specify/extensions.yml`. The consented self-heal writes that operator-owned config in response to **local detection + explicit operator consent**, NOT in response to any Linear change — Principle I forbids Linear→filesystem mirroring, which this does not do. No `specs/**` write. |
| **II. Reconcile, never event-push** | PASS. The check reads full hook state each run, is idempotent, holds no cross-run cache, and is safe to re-run with zero churn (warn-only path mutates nothing). |
| **III. Layered idempotency (D+E)** | PASS. Lives entirely in Layer D (reconcile/status). No Layer E (webhook) change; touches no labels/comments/sub-issues/workflow-state. |
| **IV. Write-authority follows filesystem (drift-aware)** | PASS. Orthogonal — no spec-level Linear write; no branch gating involved. |
| **V. UUID binding, per-repo config** | N/A — no Linear identifiers touched. |
| **VI. OAuth-first** | PASS. No Linear API call at all; nothing to authenticate. |
| **VII. Memory-just-works, escape hatches beside it** | PASS — and this feature **directly serves** VII. It surfaces when the `optional: false` auto-registered hooks have gone missing, and the self-heal **re-registers only ABSENT hooks while preserving `enabled: false`** (reusing install's idempotent path), honoring VII's rule "MUST honour `enabled: false` and MUST NOT silently re-enable on reinstall." |
| **VIII. Surface, don't enforce — observable failure** | PASS — the defining principle here. The warning **never blocks** (FR-003/SC-003), is emitted as a structured `summary::add warned` row naming the missing hooks + remediation, and the only mutation is **interactive + explicitly consented**; non-interactive runs mutate nothing, so the bridge never "fixes the operator's workflow unilaterally." `status` exit code is unchanged (FR-006). |

**Vocabulary**: uses canonical terms (`after_*` hooks, `speckit.linear.push/status`,
`.specify/extensions.yml`). No "wave/W0".

**Gate result: PASS** (no violations; Complexity Tracking left empty).

## Project Structure

### Documentation (this feature)

```text
specs/014-hook-health/
├── plan.md              # This file (/speckit-plan output)
├── spec.md              # Feature spec (clarified 2026-06-23 + 2026-06-24)
├── research.md          # Phase 0 output (this command)
├── data-model.md        # Phase 1 output (this command)
├── quickstart.md        # Phase 1 output (this command)
├── contracts/
│   └── hookcheck.md     # Phase 1 output — hookcheck.sh function contracts
├── checklists/
│   └── requirements.md  # /speckit-specify output (all [x])
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
src/
├── hookcheck.sh         # NEW — detection (classify present|disabled|absent) +
│                        #       once-per-run warning helper + consented self-heal
│                        #       wrapper. Dependency-light; reuses install's writer.
├── reconcile.sh         # EDIT — source hookcheck.sh; fire the once-per-run check
│                        #        in reconcile::main (after spec enumeration);
│                        #        add `_RECONCILE_HOOKS_WARNED` latch.
├── status.sh            # EDIT — source hookcheck.sh; add hook-health line to
│                        #        emit_human + field to emit_json; offer self-heal
│                        #        interactively; exit code unchanged.
├── install.sh           # REUSE (no behavior change) — register_after_hooks /
│                        #        _hook_already_registered / INSTALL_AFTER_HOOK_NAMES /
│                        #        INSTALL_EXTENSIONS_YML are the canonical anchors.
└── summary.sh           # REUSE — summary::add warned / info.

tests/
├── unit/
│   ├── hookcheck.bats           # NEW — classify present/disabled/absent; missing-set;
│   │                            #       malformed file → "could not verify"; name-list
│   │                            #       pinned to install's INSTALL_AFTER_HOOK_NAMES.
│   └── hookcheck_selfheal.bats  # NEW — interactive consent (yes→register, no→no-op),
│                                #       non-interactive never mutates, all-at-once.
└── integration/
    ├── us1-hook-health-warn.bats   # NEW — stripped hooks → push warns once, not blocked.
    └── us2-status-hook-health.bats # NEW — status reports present/partial/none, exit 0.

docs/  (or README.md)
└── README.md            # EDIT (FR-011) — `--from <release-zip>` install/update
                         #   one-liner + "re-run /speckit.linear.install after --force".
```

**Structure Decision**: Single Bash project. Detection is isolated in a new
`src/hookcheck.sh` so both the `reconcile.sh` and `status.sh` entrypoints can source
it without duplicating the YAML grammar, and so it is unit-testable in isolation.
Re-registration is NOT re-implemented — it delegates to the existing, idempotent,
`enabled:false`-preserving `install::register_after_hooks` (integration approach
chosen in research.md R3).

## Complexity Tracking

> No Constitution Check violations — section intentionally empty.
