# Feature Specification: Hook Self-Healing (auto-sync hook health check)

**Feature Branch**: `014-hook-health`

**Created**: 2026-06-23

**Status**: Draft

**Input**: User description: "The only community install/update path (`add --from <zip> --force`) silently strips the bridge's `after_*` auto-sync hooks, so auto-sync quietly stops and the operator doesn't notice until the board drifts. Make the bridge detect its own missing hooks and surface a loud, named warning pointing at the one-command fix — turning silent drift into an obvious re-run-install."

## Overview

The only sanctioned way to install/update a community spec-kit extension is
`specify extension add linear --from <release-zip> --force`. That `--force`
reinstall **strips the bridge's six `after_*` auto-sync hook registrations** from
the consumer's `.specify/extensions.yml` (it bypasses the CLI's hook
backup/restore). The failure is **silent**: auto-sync simply stops firing on
`/speckit.*` lifecycle commands, and the operator only discovers it when the
Linear board has drifted out of date. Because community extensions have no
frictionless `update` (a deliberate spec-kit gap, out of our control), this
stripping recurs on every upgrade.

This feature makes the bridge **self-report its own hook health**. When it runs —
`speckit.linear.push` (the reconcile) and `speckit.linear.status` — it checks
whether its six `after_*` hooks are still registered for the `linear` extension
and, if any are missing, emits a **loud, named warning** in the structured
summary naming the absent hooks and the one-command remediation
(`/speckit.linear.install`). `status` also reports hook health as a first-class
line. It is **detection + surfacing only** (surface, don't enforce — Principle
VIII): the warning never blocks the operation it rode in on, the restore path is
the existing `/speckit.linear.install` (which already re-registers idempotently),
and a hook the operator deliberately disabled (`enabled: false`) is **not**
treated as missing.

## Clarifications

### Session 2026-06-23

- Q: On detecting missing hooks, warn-only or also offer to self-heal (re-register)? → A: **WARN + consented self-heal.** push/status emit the named warning, and in an INTERACTIVE session additionally OFFER (operator y/N) to re-register the missing hooks in place; NON-INTERACTIVE (CI / hook-fired) is warn-only and never mutates. Restoration still also available via `/speckit.linear.install`.

### Session 2026-06-24

- Q: Does the consented self-heal offer also appear during `speckit.linear.status`, or is `status` report-only? → A: **Both.** When interactive and hooks are missing, `status` ALSO offers the y/N re-register (same rule as the reconcile/push path), not just a report line — the operator who proactively checks can fix on the spot.
- Q: Does `status` change its exit code when hooks are missing? → A: **No — always exit 0.** Hook health is surfaced as a report line only and never alters `status`'s exit disposition (surface, don't enforce); it is not a CI gate.
- Q: On consent, re-register all missing hooks at once or prompt per hook? → A: **All at once.** A single y/N re-registers every missing `after_*` hook in place.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A stripped hook set becomes a loud one-line fix (Priority: P1)

A developer updated the bridge via `add --from <zip> --force`, which silently
removed the `after_*` hooks. The next time they run a sync (`speckit.linear.push`,
or any reconcile), the run **warns loudly** that auto-sync hooks are not
registered and tells them exactly how to fix it (`/speckit.linear.install`). The
silent drift is now impossible to miss.

**Why this priority**: This is the whole point — converting a silent, board-
drifting failure into an obvious, named, one-command fix. It directly addresses
the reported pain.

**Independent Test**: In a repo whose `.specify/extensions.yml` has had the
`linear` `after_*` hooks removed, run `speckit.linear.push` and confirm the run
completes (not blocked) AND emits a warning naming the missing hooks + the
`/speckit.linear.install` remediation.

**Acceptance Scenarios**:

1. **Given** the `linear` `after_*` hooks are absent from `.specify/extensions.yml`,
   **When** the bridge reconciles, **Then** it emits a warning naming how many /
   which hooks are missing and the `/speckit.linear.install` remediation, and the
   reconcile still completes normally (not blocked).
2. **Given** all six hooks are registered, **When** the bridge reconciles, **Then**
   no hook-health warning is emitted.
3. **Given** the operator deliberately set a hook `enabled: false`, **When** the
   bridge reconciles, **Then** that hook is treated as intentionally disabled (not
   "missing") and raises no warning.

---

### User Story 2 - Check hook health on demand (Priority: P2)

An operator wants to verify auto-sync is wired without waiting for a drift. They
run `speckit.linear.status` and see hook-registration health as a first-class line
(all present / partial-with-the-missing-ones-named / none registered).

**Why this priority**: Useful for proactive checks and incident triage, but
secondary to the automatic warning on the reconcile path (US1), which catches the
problem without the operator thinking to look.

**Independent Test**: Run `speckit.linear.status` in repos with all / some / none
of the hooks registered and confirm each reports the corresponding health state.

**Acceptance Scenarios**:

1. **Given** all six hooks registered, **When** `status` runs, **Then** it reports
   hook health as fully present.
2. **Given** some hooks missing, **When** `status` runs, **Then** it reports
   partial health and names the missing hooks.
3. **Given** no `linear` hooks registered, **When** `status` runs, **Then** it
   reports auto-sync as not wired, with the `/speckit.linear.install` remediation.

---

### Edge Cases

- **Operator-disabled hook** (`enabled: false`): intentional → not "missing", no
  warning (distinguished from absent).
- **No `.specify/extensions.yml` at all** (bridge never installed in this tree):
  out of the feature's scope to nag — handled as the existing not-installed path,
  not a per-reconcile hook-health warning.
- **Partial set** (some hooks present, some absent — e.g. a hand-edited file):
  warn, naming exactly the absent ones.
- **Warning cadence**: at most once per reconcile run (not once per spec), matching
  the existing one-shot-warning pattern, so an `--all` sweep doesn't repeat it.
- **The check never blocks**: a malformed/unreadable `.specify/extensions.yml`
  degrades to "could not verify hook health" (informational), never halting the
  reconcile (Principle VIII).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On `speckit.linear.push` (reconcile) and `speckit.linear.status`, the
  bridge MUST determine whether each of its six `after_*` hooks (`after_specify`,
  `after_clarify`, `after_plan`, `after_tasks`, `after_implement`,
  `after_analyze`) is registered for the `linear` extension in the consumer's
  `.specify/extensions.yml`.
- **FR-002**: When one or more of those hooks are **absent**, the reconcile MUST
  emit a single structured warning per run that states how many are missing, names
  the missing hooks, and gives the `/speckit.linear.install` remediation.
- **FR-003**: The hook-health warning MUST NOT block or fail the operation it rode
  in on — the reconcile/push completes normally (surface, don't enforce).
- **FR-004**: A hook the operator has explicitly disabled (`enabled: false`) MUST
  be treated as intentionally off, NOT as missing, and MUST NOT trigger the
  warning.
- **FR-005**: When all six hooks are registered (or intentionally disabled), the
  bridge MUST emit no hook-health warning.
- **FR-006**: `speckit.linear.status` MUST report hook-registration health as a
  first-class result line: fully present, partial (naming the missing hooks), or
  none registered. This report MUST NOT change `status`'s exit code — `status`
  always exits 0 regardless of hook health (the health line is informational, not
  a CI gate). (Clarified 2026-06-24.)
- **FR-007**: The detection MUST use the same notion of "is hook X registered for
  `linear`" that the install path uses to register them, so detection and the
  install-based restore agree (no false positives/negatives).
- **FR-008**: The check MUST read only the consumer's local `.specify/extensions.yml`,
  perform no Linear writes, add no new runtime dependency, and (on the warn path)
  mutate nothing; an unreadable/malformed file degrades to an informational
  "could not verify" rather than a halt.
- **FR-009**: On detecting missing hooks in an **interactive** session, the
  bridge MUST OFFER to re-register them in place (explicit operator y/N consent),
  reusing the install path's idempotent registration; a **non-interactive** run
  (CI / hook-fired / no TTY) MUST be warn-only and mutate nothing. This offer
  applies on BOTH the reconcile/`push` path AND `speckit.linear.status` (any
  interactive run that detects missing hooks offers the fix). A **single** y/N
  consent re-registers ALL missing `after_*` hooks at once (not one prompt per
  hook). Declining the offer is a no-op + the warning. `/speckit.linear.install`
  remains an equivalent restore. (Clarified 2026-06-23: warn + consented
  self-heal; 2026-06-24: offer on status too, single all-at-once consent.)
- **FR-010**: The warning MUST fire at most once per reconcile run (deduped across
  an `--all` sweep), matching the bridge's existing one-shot-warning pattern.
- **FR-011**: Documentation MUST give a crisp `--from <release-zip>` install/update
  one-liner (pinned to the latest release tag) AND a note to re-run
  `/speckit.linear.install` after a `--force` update to restore the auto-sync
  hooks, so the workaround and the self-report point at the same fix.
- **FR-012**: The feature MUST keep `extension.id` as `linear` and the command
  surface (`speckit.linear.*`) unchanged — detection lives inside existing
  commands, not a new command.

### Key Entities *(include if feature involves data)*

- **Hook registration set**: the six `after_*` entries for the `linear` extension
  in the consumer's `.specify/extensions.yml`, each either registered (enabled),
  intentionally disabled, or absent.
- **Hook-health state**: the per-run assessment — fully present / partial (with the
  named absent hooks) / none — surfaced as a warning (reconcile) and a status line.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With one or more `after_*` hooks absent, **100%** of reconcile runs
  surface a warning naming the missing hooks + the remediation (no silent runs).
- **SC-002**: With all hooks registered, **0** hook-health warnings are emitted
  (no false positives), and a deliberately `enabled: false` hook produces **0**
  warnings.
- **SC-003**: The hook-health warning never changes the reconcile's exit
  disposition — a run that would otherwise succeed still succeeds (the check is
  non-blocking in 100% of cases).
- **SC-004**: After the operator follows the remediation (`/speckit.linear.install`),
  a subsequent reconcile emits **0** hook-health warnings (detect and restore
  agree).
- **SC-005**: `speckit.linear.status` reports the correct hook-health state
  (present / partial / none) in 100% of the three cases, and exits 0 in 100% of
  cases regardless of hook health (the health line never alters status's exit
  disposition).
- **SC-006**: The warning appears at most **once per reconcile run** regardless of
  how many specs are processed.

## Assumptions

- **Resolved disposition** (clarification 2026-06-23): warn + consented self-heal —
  interactive offers in-place re-registration (operator y/N); non-interactive is
  warn-only; `/speckit.linear.install` is an equivalent restore.
- The install path's hook registration is idempotent and is the canonical restore
  (re-running install re-adds missing hooks), so no separate restore command is
  needed.
- "Registered" means an `after_<phase>` entry whose `extension` is `linear` exists
  and is not `enabled: false`; this matches how install detects an already-present
  hook.
- The warning reuses the bridge's existing structured-summary + one-shot-warning
  machinery (same surface as the operator-identity / overview warnings).

## Out of Scope

- Making `specify extension update linear` work (community extensions have no
  frictionless update by design; the trusted-catalog and default-catalog routes
  were considered and rejected).
- Changing how the extension installs or copies files into a consumer repo.
- Auto-mutating `.specify/extensions.yml` **without** operator consent or in a
  **non-interactive** run (the self-heal is interactive + consented only; CI/
  hook-fired runs never mutate).
- The spec-kit-jira sibling (same hook-stripping exposure; parity follow-up).
