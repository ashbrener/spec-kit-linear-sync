<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

<!-- Everything below is OUTSIDE the SPECKIT-managed block on purpose, so
     `specify integration upgrade` cannot overwrite it. Keep project rules here. -->

The current plan is `specs/007-configurable-mapping/plan.md` (configurable
artifact mapping — operator-configurable spec→Linear mapping with the spec-001
mapping preserved as the frozen zero-config default; resolves design issue #17;
faithful port of the spec-kit-jira `specs/002-configurable-mapping` model).
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
