<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

<!-- Everything below is OUTSIDE the SPECKIT-managed block on purpose, so
     `specify integration upgrade` cannot overwrite it. Keep project rules here. -->

The current plan is `specs/014-hook-health/plan.md` (hook self-healing — the
community `add --from <zip> --force` update path silently strips the bridge's six
`after_*` auto-sync hooks from `.specify/extensions.yml`, so auto-sync stops and
the board drifts unnoticed. The bridge now self-reports its own hook health: on
every `speckit.linear.push` (reconcile) and `speckit.linear.status` it classifies
each `after_*` hook as present/disabled/absent and, when any are absent, emits a
single loud once-per-run warning naming the missing hooks + the
`/speckit.linear.install` remediation; `status` adds a first-class hook-health
line and never changes its exit code. Interactive runs additionally OFFER a single
y/N consented self-heal that re-registers all missing hooks at once (reusing
install's idempotent `register_after_hooks`, preserving `enabled: false`);
non-interactive runs are warn-only and mutate nothing. Surface-don't-enforce
(Principle VIII); detection lives in new `src/hookcheck.sh`; additive, no
constitution amendment; jira-sibling parity is a follow-up). It builds on
`specs/013-subissue-cascade/plan.md` (lifecycle cascade to task-phase sub-issues +
single-letter phase grammar A→1…Z→26), `specs/012-readable-titles/plan.md`
(readable Issue titles), `specs/010-author-attribution/plan.md` (author attribution),
`specs/008-adr-mirroring/plan.md` (ADR / decision-record mirroring) and
`specs/007-configurable-mapping/plan.md` (configurable mapping, resolves #17).
It builds on the shipped baselines: `specs/006-faithful-projection/plan.md`,
`specs/005-team-scoped-seeding/plan.md`, `specs/004-config-identity-split/plan.md`,
the drift-aware write-authority redesign at `specs/003-drift-aware-authority/plan.md`,
the v0.1.1 install-ergonomics plan at `specs/002-install-ergonomics/plan.md`, and
the v0.1.0 baseline at `specs/001-spec-kit-linear-bridge/plan.md`.

Always check `.specify/memory/constitution.md` (v2.1.0, 8 principles) before
proposing implementation changes — the Constitution Check gate is
non-negotiable. (v2.1.0 amended the data-model-mapping clause: the spec-001
mapping is the frozen zero-config default; alternative mappings are
operator-configurable per spec 007, bounded by the fail-closed relationship
matrix.) Use canonical spec-kit vocabulary throughout (`task phase`,
`Phase N — <Name>`, never `wave / W0`).
