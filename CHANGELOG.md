# Changelog

All notable changes to **spec-kit-linear-sync** are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### ADR / decision-record mirroring — spec 008

- **Your decisions now reach the tracker.** The `Decision / Rationale /
  Alternatives` blocks in each spec's `research.md` are mirrored as ADR comments
  on that spec's Linear Issue — one comment per decision, in an ADR layout (id,
  title, status, decision, rationale, alternatives, source). It rides the
  existing `after_*` hooks; no new command, no config. Works for any spec that
  has a `research.md`; a spec without one is a graceful no-op.
- **Idempotent + update-in-place.** Each ADR is keyed by a hidden
  `<!-- spec-kit-linear: adr <NNN>-<key> -->` marker (heading id `D<N>`/`R<N>`,
  else a title slug); an unchanged corpus is zero-churn, a revised decision
  updates its one comment in place, a new decision adds one comment. (Update-in-
  place is Principle I — the filesystem is canonical; it is the sole behavioural
  delta from the clarify-comment path, and the one new mutation, `commentUpdate`.)
- **Parity** with the spec-kit-jira ADR feature: the user-visible comment shape
  matches across both sinks. No config/schema change; `extension.id` stays
  `linear`.

## [0.4.0] — 2026-06-10 — Configurable artifact mapping (#17) + lifecycle fixes

Headlines the operator-configurable spec→Linear mapping (spec 007, resolving the
long-standing #17 design question) plus a lifecycle-inference fix (#61). The
default mapping is unchanged and the command surface is the same; `extension.id`
stays `linear`. The configurable projection was validated end-to-end against a
real Linear workspace (created the `Initiative > Project > Issue > sub-issue`
hierarchy and re-ran zero-churn).

### Configurable artifact mapping — spec 007

Resolves the #17 design question ("should a spec become a Project or an Issue?")
by making the spec→Linear mapping operator-configurable, while keeping the
spec-001 mapping (repo→Project, spec→Issue, phase→sub-issue, task→checklist) as
the **frozen zero-config default** — existing installs are byte-for-byte
unchanged (no file rewrite, no config-version bump).

- **Constitution v2.0.0 → v2.1.0 (MINOR).** The data-model-mapping clause now
  names the spec-001 mapping the frozen default and permits a bounded, opt-in
  configurability surface (alias-synthesized default when absent; offline,
  fail-closed relationship + Linear-native containment validation; all logic in
  the source-agnostic config layer).
- **Config layer (shipped).** An optional `mapping:` block in `linear-config.yml`
  lets you set, per spec-kit level (repo/spec/phase/task), the Linear artifact
  and its parent relationship, plus an off-by-default narrative super-level (L0).
  The config layer resolves it (with per-level inheritance from the synthesized
  default) and validates it at config-load, failing closed before any write on
  nonsensical mappings — `blocks`/`relates` as nesting, `parent` on the top
  level, checklist misuse, or a hierarchy Linear cannot build (e.g.
  Project-under-Project). Linear's real hierarchy is honoured:
  `Initiative > Project > Issue > sub-issue` (the narrative super-level is an
  Initiative — Linear Milestones live inside a Project and cannot contain one).
  The #17 spec-as-Project shape is `repo→Initiative, spec→Project, phase→Issue,
  task→sub-issue`.
- **Projection (implemented).** The non-default shapes now project to Linear:
  the **#17 spec-as-Project** chain mirrors `Initiative > Project > Issue >
  sub-issue` (idempotent — every level matches/updates by a stable identity
  marker or label, zero-churn on re-run), and the optional **L0 narrative
  super-level** creates an Initiative above the repo Project (narrative from the
  spec `**Input**:` line only) and degrades gracefully where Initiatives aren't
  available on the plan. Backward-drift detection is preserved on the spec-level
  work unit in the mapped path too (anchored on the phase Issues' state vs disk;
  the L0 Initiative is never a drift surface). The default projection is
  untouched; non-default combinations not yet projected are surfaced and skipped
  (never a silent partial). `extension.id` stays `linear`; the command surface is
  unchanged. The configurable projection is new — validate on a test workspace
  before relying on it in production.
- **Live-dogfood fixes** found while validating the #17 projection against a real
  Linear workspace: `--dry-run` no longer errors when previewing the mapped path
  (placeholder ids were leaking into real queries); long spec bodies go in the
  Project/Initiative `content` field (Linear caps `description` at 255 chars); and
  the spec→Project nesting uses the correct `initiativeToProjectCreate` junction
  mutation.

### Lifecycle fix

- **Linear issues no longer stick at "in-progress" (#61).** The reconciler now
  reads the spec's real branch from `plan.md` (`**Branch**:`) for the PR-state
  lookup instead of guessing from the directory name. When the two differ (a spec
  dir `014-*` whose work merged on branch `015-*`), the merged PR is now detected
  and the issue moves to merged, rather than falling back to artifact inference
  and being overwritten to in-progress every sync. Falls back to the dir-derived
  name when `plan.md` has no branch line (no change when they already match).

## [0.3.0] — 2026-06-08 — Config/identity split, team-scoped seeding, faithful projection

Three spec-driven features (specs 004/005/006). `extension.id` stays `linear`;
the command surface is unchanged. Existing installs migrate automatically.

- **Config / identity split (#38, #20) — spec 004.** `linear-config.yml` now holds
  only the shareable team/project binding and is safe to commit; your operator
  identity (`user_id`/name/email) moves to a gitignored operator-local file.
  Identity and API key resolve via an env → local-file → prompt cascade (no more
  per-worktree `.env` copies). Legacy single-file configs auto-migrate with a
  one-time notice. The docs/`.gitignore` contradiction is resolved.
- **Team-scoped / non-admin seeding (#41) — spec 005.** Seed without
  workspace-admin: team-scoped label creation, an adopt-existing path (capture
  UUIDs of states/labels that already exist), graceful permission-error handling,
  and a `--scope workspace|team` option (default `team`).
- **Faithful projection (#34, #42) — spec 006.** `push` now accepts `## Phase N`
  headers with `:`, `—`, `-`, or whitespace separators (was colon-only → silent
  zero sub-issues), and the Linear issue description inlines the spec's own
  content (Input + Overview + body, capped with clean-boundary truncation + a
  full-spec link).

All existing safety guarantees (idempotency, drift-awareness, fail-closed) hold.

## [0.2.2] — 2026-06-07 — Bug-fix round from community reports

Fixes from the first wave of external issue reports (thanks @davieshq, @rcollette).
No behavior changes beyond the fixes; `extension.id` stays `linear`.

- **Fixed (#33, #39, #40):** seed no longer writes a duplicate `default_state_uuids`
  key into `linear-config.yml`. The managed UUID blocks now update in place, so the
  file stays valid (single-key) YAML and formats cleanly.
- **Fixed (#36):** the reconcile summary now counts created issues/sub-issues
  correctly (the counts were being lost to a subshell, so it reported `Created: 0`).
- **Fixed (#35):** `pull` and `status` now surface the "malformed config" diagnostic
  instead of exiting with a silent code 2.
- **Fixed (#42):** removed the hardcoded README-anchor links from generated issue
  descriptions — they only resolved against this repo, so they were dead links for
  every consumer.
- **Added (#34):** `push` now warns when it sees a `## Phase N` heading that isn't in
  the `## Phase N:` form (previously those were skipped silently, yielding 0
  sub-issues). Broadening which header styles are accepted is tracked separately.

## [0.2.1] — 2026-06-03 — Rename to spec-kit-linear-sync + pull alignment fix

Branding/metadata release: the repo and extension display name become
**`spec-kit-linear-sync`**, joining the `spec-kit-<tracker>-sync` family. No
behavior change — `extension.id` stays `linear`, so the command surface
(`/speckit.linear.*`) is unchanged, and GitHub redirects the old repo URL.

- **Fixed (#31):** `speckit.linear.pull --human` misaligned every column when a
  cell was empty (no `phase:*` label, `null` estimate) — `IFS=$'\t' read`
  collapsed empty fields (tab is IFS-whitespace), shifting later columns left.
  Now splits on a non-whitespace unit separator so empty fields are preserved.
- **Changed:** repository renamed `spec-kit-linear` → `spec-kit-linear-sync`;
  `extension.yml` `name`/`repository`/`homepage` updated. Functional identifiers
  (command ids, FR-033 hook markers, spec paths, the GitHub Action filename) are
  intentionally unchanged.

## [0.2.0] — 2026-05-31 — Drift-aware write-authority (spec 003)

Redefines write-authority from the v1.0.0 branch-gate to a **drift-aware** model. Implements the v2.0.0 constitution's amended Principle IV ("Write-Authority Follows The Filesystem").

- **Write from any worktree (FR-051)** — the FR-025 branch-gate is removed. Any worktree may reconcile a spec to Linear; the branch name is a heuristic for "who has the latest", not a permission gate. Fixes the founding pain: a merged spec (feature branch deleted) can now be reconciled from `main` with zero flags.
- **Backward-drift surfaced, never blocked (FR-052..FR-057, SC-017)** — before writing, the bridge compares disk vs Linear: if Linear's recorded lifecycle phase is further along than the disk-inferred phase, it emits a WARNING — then proceeds. Spec-dir commit recency (Linear's `updatedAt` newer than the spec dir's last commit, ±120s skew) only *corroborates* a phase drift; it never raises a warning on its own, so a no-op re-run — or a third-party edit that bumps `updatedAt` without advancing the phase — stays silent (SC-017 idempotency). The operator decides; the bridge surfaces, it does not enforce (Principle VIII).
- **`--on-drift=abort|proceed`** — non-interactive control over the drift disposition (default: proceed-and-warn). In an interactive TTY with no flag, the bridge prompts via `/dev/tty` (empty-enter = abort, default-safe).
- **`--retroactive` deprecated (FR-061)** — now a no-op alias emitting one deprecation INFO row; write-from-any-branch is the default, so the v0.1.1 stopgap is no longer needed.
- **Multi-worktree canonical pointer (FR-058)** — the memory block records the most-recent commit touching the spec dir, so the operator can see which worktree holds the freshest state.

Governance dependency: the v2.0.0 constitution amendment (Principle IV) shipped in v0.1.2 as a doc-only change; spec 003 is its runtime implementation. Constitution re-check: 8 Conform / 0 Drift (`validation/constitution-recheck-003.md`).

## [0.1.2] — 2026-05-29

Two reconcile/install bug fixes surfaced by downstream dogfood, plus the governance groundwork for the v0.2.0 drift-aware authority work.

### Fixed

- **Worktree-safe git hooks path (FR-033, #14)** — `install.sh` hardcoded `.git/hooks`, which is wrong in a git **worktree** (where `.git` is a file and hooks live elsewhere). FR-033's local-hook install silently wrote to a path git never reads for any worktree-based operator. Now resolves the hooks directory via `git rev-parse --git-path hooks` (worktree-safe, honors `core.hooksPath`), with a `.git/hooks` fallback and `mkdir -p`.
- **Detect merged specs from any branch (FR-013/FR-030, #15)** — a merged spec's Linear Issue stayed stuck at its pre-merge lifecycle state when reconciled from a non-feature branch. Root cause: `git_helpers::pr_state` queried `gh pr view --json merged`, but `merged` is not a valid `gh` JSON field — the call always errored and fell through to a git-only branch-reachability probe that can't resolve a deleted/non-local feature branch. Now uses `gh pr list --head <branch> --state all` (resolves by HEAD ref via the API regardless of checked-out branch); lifecycle correctly resolves to `merged` from any worktree.

### Changed — Governance

- **Constitution amended to v2.0.0 (#13)** — Principle IV redefined from "Write-Authority Follows The Worktree" (branch-gate enforcement) to **"Write-Authority Follows The Filesystem (Drift-Aware)"**: any worktree may write; the bridge surfaces backward-drift but does not block (Principle VIII). This is a backward-incompatible *governance* change (hence the constitution's MAJOR bump) that enables spec 003; it does **not** alter extension runtime behavior in this release — the drift-aware reconcile logic ships when spec 003 is implemented. The extension version line (0.1.2) and the constitution version line (2.0.0) are independent.

### Added — Tooling & docs

- **Dogfood-script interactive-flow block + `linear-install.md` vocab pass (#12)** — `scripts/dogfood.sh --interactive-flow` exercises spec 002's discovery install against a throwaway sandbox repo.
- **Community-catalog submission draft (#10)** — `validation/community-catalog-submission.md` with the ready-to-paste catalog entry + submission checklist.
- **Open design-questions parking lot (#18)** — `validation/design-questions.md` (inert, DO-NOT-IMPLEMENT) capturing the spec→Project question (tracking issue #17).

### Housekeeping

- Scrubbed private project names + local filesystem paths from public docs (#16).

## [0.1.1] — 2026-05-28

Install ergonomics redesign (spec 002) plus three dogfood-surfaced reconcile hotfixes. The headline change: the Linear API key is now the only thing an operator brings to install — team and project are discovered interactively, no UUIDs surfaced.

### Added — Install ergonomics redesign (spec 002)

- **Viewer-driven install discovery flow (FR-037..FR-043)** — the API key is now the only thing the operator brings. `/speckit.linear.install` resolves the key from `.env` (or env var, or interactive prompt), verifies via Linear's `viewer` query, then presents:
  - A numbered team picker (auto-picked silently when the workspace has one team); operator never sees a UUID.
  - A numbered project picker with a final "Create new project" option; if chosen, install issues `projectCreate` with the project name (defaults to repo dir) and surfaces the new project's Linear URL in the summary.
- **Backwards-compat preserved (FR-044, FR-045)** — `bash src/install.sh --team <UUID> --project <UUID>` still works bit-for-bit for CI / scripted installs. `--non-interactive` strictness tightened: now halts with a clear error rather than falling through to interactive prompts when flags are missing.
- **Self-install safety guard (FR-046)** — `install.sh` detects the `source == target` case (operator runs `specify extension add /path/to/spec-kit-linear --dev` from inside `/path/to/spec-kit-linear` itself) and exits with exit code 2 + a clear remediation message. Prevents the recursive `.specify/extensions/linear/.specify/extensions/linear/...` directory mess that hit macOS filename length limits during the first community-style dogfood.
- **Vendored `.git/` detection (FR-049)** — `install.sh` detects a vendored `.git/` directory at `.specify/extensions/linear/.git/` (caused by the spec-kit CLI's `--dev` install vendoring the source's full git tree) and surfaces a warning row in the dependency-verification report. Operator-actionable workaround documented in the install summary; no auto-delete (operator's filesystem).
- **README install commands corrected (FR-047)** — `--from` flag now requires the GitHub archive ZIP URL (`/archive/refs/heads/main.zip`), not the repo URL; bare repo URLs error with `BadZipFile`. The catalog form `specify extension add linear` documented as "once it's listed". `--dev <path>` documented as the local-development install. Operator-facing instructions now work on the first command they run.

### Fixed — Reconcile hotfixes (dogfood-surfaced)

- **`--retroactive` actually bypasses FR-025's write-authority gate (PR #3)** — v0.1.0 only suppressed the per-spec "non-authoritative worktree" warning row; the underlying gate in `sync_spec_issue` still fired and returned 0 without writing. Result: an operator with many existing specs ran `bash src/reconcile.sh --all --retroactive` from a non-`NNN-feature` branch and got ZERO mutations — breaking FR-014's promise that "first reconcile after install backfills every spec". The gate is now genuinely bypass-able when `--retroactive` is set; aggregated INFO row recorded once after the per-spec loop. Two new integration tests in `tests/integration/us5-retroactive-bypass-authority.bats` regression-pin both the bypass and the FR-025-default behavior.
- **Lazy-create `task-phase:N` labels for specs with 10+ phases (PR #4)** — `src/seed.sh` bootstraps `task-phase:1..9`; specs with 10+ task phases silently dropped their overflow sub-issues because the bridge couldn't resolve `task-phase:10+`. Reconcile now lazy-creates `task-phase:N` on first encounter (mirrors the `speckit-spec:NNN` / `agent:*` lazy-create precedent), so a spec with any number of phases mirrors completely. Regression test: `tests/integration/us1-task-phase-overflow.bats` (12-phase fixture).
- **Guard null `relations`/`labels` in the blocks-lookup path (PR #6)** — four `jq` `.nodes[]` iterations crashed with `Cannot iterate over null` when Linear returned `relations`/`labels` as `null` (a legitimate empty set) rather than `{nodes: []}`. Guarded with `(.nodes // [])[]` at all four sites; empty relation/label sets are now treated correctly as empty.

### Changed

- **`specs/001-spec-kit-linear-bridge/spec.md` FR-014** — added a clarifying note that `--retroactive` is the operator-facing flag delivering FR-014's contract; without it, FR-025 gates per-branch.
- **`commands/linear-push.md` `--retroactive` description** — now clearly states "bypasses FR-025 write-authority gate; intended for first-time adoption only".

### Validation

- **Constitution v1.0.0 re-check (T270)** — 8 Conform / 0 Drift; the Principle VI expansion (API key load-bearing at install) re-checks clean. See `validation/constitution-recheck-002.md`.
- **Dogfooded live** — spec 002 itself mirrored to the ACME Linear workspace (parent Issue + 6 task-phase sub-issues) during development.

### Acknowledgements

The install-ergonomics redesign and all three reconcile hotfixes were surfaced by the first real-operator dogfood of v0.1.0 into a downstream consumer repo. Real users surface real bugs; ship more.

## [0.1.0] — 2026-05-28

First public release. Mirror every spec on disk into a Linear Issue, kept in sync by spec-kit's own `after_*` hooks plus local git hooks plus a GitHub Actions webhook.

### Added — Commands

- **`/speckit.linear.install`** — interactive install ceremony. Resolves Linear Team / Project / operator UUIDs, captures operator identity via `viewer` query (FR-034), writes `.specify/extensions/linear/linear-config.yml`, registers `after_*` hooks in `.specify/extensions.yml` (FR-031), installs local git hooks (FR-033), optionally installs the GitHub Action layer with copy-paste `gh secret set LINEAR_API_TOKEN` instructions (FR-027 / FR-029). Verifies every external dependency it touches and surfaces a structured status report (FR-018b). Detects seeded-state and prompts to run seed inline (T063). Dogfood-safe install mode via `SPECKIT_LINEAR_DOGFOOD_SAFE=1` (FR-033b).
- **`/speckit.linear.seed`** — one-shot workspace setup. Creates 9 lifecycle workflow states (`Specifying`, `Clarifying`, `Planning`, `Tasking`, `Red-team`, `Implementing`, `Analyzing`, `Ready-to-merge`, `Merged`) and the `phase:*` + `task-phase:1..9` label families. Captures every UUID at creation and writes them back into `linear-config.yml.workflow_state_uuids` so renames in Linear's UI never break the bridge (FR-032). Idempotent.
- **`/speckit.linear.push`** — the reconciler. Fires automatically on every `/speckit.*` lifecycle command via auto-registered `after_*` hooks; also invokable on demand. Reconciles every `specs/NNN-feature/` directory in the consumer repo into the Linear Project. Idempotent: re-running on unchanged state produces zero churn (SC-002).
- **`/speckit.linear.status`** — read-only drift inspector. Per spec, flags mismatches between disk and Linear: lifecycle phase, current branch, last-touched timestamp, task-phase completion ratio. Surfaces the authority status (FR-025 — is the current worktree authoritative for each spec?). `--human` table or `--json`. Never writes.
- **`/speckit.linear.pull`** — read-only cross-repo unified view. `--repo` (default) shows every spec Issue in this repo's Project; `--workspace-wide` shows every spec Issue across every Project bound to the operator's team. Useful for the "what's everyone's spec status" question from any directory.

### Added — Architecture

- **Layer D (reconciler)** + **Layer E (GitHub Action webhook)** — both independently idempotent. Either alone keeps Linear converging; both together cover live commits and retroactive sync. Layer E flips Issues to `Ready-to-merge` and `Merged` in real time on PR events.
- **Workspace label** `speckit-spec:NNN` as the stable lookup key for every spec Issue (FR-004b). Duplicate-resolution: most-recent activity wins, others archived.
- **Memory block** — auto-managed markdown table on every spec Issue's description carrying current lifecycle phase, branch, worktree(s), last-touched timestamp, GitHub source link. Fully bridge-owned: rewritten on every reconcile. Operator annotations belong in Linear comments (FR-008), which the bridge never touches.
- **Local git hooks** (`post-checkout`, `post-commit`, `post-merge`) — fire the reconciler on branch switches, commits, and merges, so Linear stays in sync without re-running a spec-kit command (FR-033). No daemons, no crons, no filesystem watchers.
- **Write-authority gate** (FR-025 / FR-026) — only the worktree on a spec's feature branch may mutate that spec's Linear Issue. Other worktrees' syncs are read-only for that spec; current Linear state still surfaces for inspection.
- **Operator identity captured at install** via Linear's `viewer` query (FR-034). `assigneeId` stamped on every `issueCreate` (single-write-on-create — manual reassignment in Linear's UI persists across reconciles).
- **Fibonacci `[N]` story-point markers** on task lines (FR-035). Per-phase sum → sub-issue `estimate`; spec-level sum → spec Issue `estimate`. Tolerant: malformed markers ignored, no-marker omits `estimate` from the mutation (operator-set Linear value remains sticky). Graceful degrade when computed value exceeds the team's Linear estimation cap.
- **Agent identity stamping** (FR-036). Workspace label from the `agent:*` family (`agent:claude`, `agent:codex`) added to every Issue the bridge writes — sticky, never removed, allows kanban filtering by which AI agent worked on what. `Last reconciled by:` row in the memory block records the full model identifier + ISO timestamp.

### Added — Toolchain

- 5 bash modules under `src/`: `config.sh`, `graphql.sh`, `git_helpers.sh`, `summary.sh`, `parser.sh` — each independently unit-tested.
- Full bats matrix in CI: ubuntu × bash 4.4 + 5.2, macOS × bash 5.2 (macOS × bash 4.4 excluded — bash 4.4 source doesn't compile against Xcode 16.4 SDK; documented inline).
- Perf harness at `tests/perf/` — synthetic-fixture generator + threshold gate. N=10 cold 0.992s vs ≤30s target (30× SC-007 headroom); hot 0.840s vs ≤5s target (6× SC-008).
- Constitution v1.0.0 audit clean (7 Conform / 1 caveat / 0 Drift) — see `validation/constitution-recheck-2026-05-28.md`.
- Coverage measurement (T079) — pure-logic modules at ~80% effective coverage; GraphQL-talking modules validated end-to-end via 16 integration scenarios (gated on `RUN_INTEGRATION_TESTS=1`).

### Added — Documentation

- `README.md` in spec-kit community-extension catalog style.
- `CONTRIBUTING.md` with full lifecycle walkthrough for changes that add or amend FRs.
- `BRIEF.md` capturing the original architectural decisions from an internal planning session.
- Five validation artifacts under `validation/` feeding `/speckit-plan`'s research bundle.
- Full spec.md (36 FRs), plan.md (Constitution Check + Phase 0/1/2), tasks.md (84 tasks across 8 phases), data-model.md (Filesystem + Linear-side schemas), contracts/, quickstart.md.

### Reconcile-time behavior

- Lifecycle phase inferred entirely from filesystem state (FR-012): artifact presence ladder + task completion ratio + PR state.
- Retroactive sync converges to the right end-state in one reconcile without producing intermediate-phase artifacts in Linear's activity log (FR-014).
- 16 integration scenarios cover fresh-reconcile, idempotent-rerun, task-added, clarify-mirror, retroactive-sync, install-action, seed-fresh, seed-idempotent, seed-prompt, unseeded-halts, after-hook-fires, git-hook-fires, non-authoritative-worktree, status-staleness, pull-cross-repo.

[Unreleased]: https://github.com/ashbrener/spec-kit-linear/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/ashbrener/spec-kit-linear/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ashbrener/spec-kit-linear/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ashbrener/spec-kit-linear/releases/tag/v0.1.0
