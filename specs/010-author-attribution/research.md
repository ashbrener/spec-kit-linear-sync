# Phase 0 Research: Author-Based Attribution

**Feature**: `010-author-attribution`

**Date**: 2026-06-11

This document records the Phase 0 research decisions for feature 010 — mirroring
each spec's authorship into Linear via an account-independent `author:<handle>`
label plus an author assignee (on create, when resolvable). The feature re-points
the existing spec-001 FR-034 create-time assignee and clones the existing
`phase:*` label strip-and-set hygiene. It is parity-locked to the spec-kit-jira
author-attribution feature at the user-visible level; the internal author→user
resolution differs (dynamic, not a mandatory static map).

One clarification was resolved in the 2026-06-11 `/speckit-clarify` session — the
**unresolved-author assignee fallback** — encoded in D7 below.

**Unresolved NEEDS CLARIFICATION**: none.

---

## D1 — Author resolution order: `Owner:` line → git first-add → unknown

- **Decision**: Resolve exactly one author per spec, in priority order:
  1. An explicit `**Owner:**` (or `**Author:**`) line in the spec's `spec.md`
     metadata block (the same block that already carries `**Feature Branch:**`,
     `**Created:**`, `**Status:**`, `**Input:**`). Its value is the author
     identity, authoritative and account-independent.
  2. Fallback: the email of the **first** git author to add the spec directory —
     `git log --diff-filter=A --reverse --format='%ae' -- specs/NNN-*/ | head -1`.
  3. If neither resolves → author is **unknown**: no label, no assignee, no
     failure (FR-002).
- **Rationale**: An explicit owner line is an unambiguous, version-controlled,
  account-independent override that a spec author can set deliberately — it
  parallels the Jira sibling's FR-A and keeps cross-sink parity. Git first-add is
  the zero-config default that requires no author action and is filesystem-
  evident (Principle I / II). "First to add" (not last-touched, not most-commits)
  attributes the spec to its originator, which matches how spec ownership is
  understood and is deterministic across clones (it reads commit history, not
  mtime). Unknown-is-graceful honours Principle VIII.
- **Alternatives considered**: last author / most-commits author (rejected —
  non-deterministic ownership; a reviewer's typo fix would steal authorship);
  spec-kit `feature.json` author field (rejected — no such field exists; would
  require a spec-kit change); CODEOWNERS (rejected — path-pattern ownership, not
  per-spec authorship, and not present in most consumer repos).

---

## D2 — `Owner:` line grammar + email-vs-handle interpretation

- **Decision**: `parser::spec_owner_line` scans `spec.md` for the first line
  matching `^\s*[-*]?\s*\*\*(Owner|Author)\*\*\s*:\s*(.+)$` (tolerating the
  `**Owner:**` and `**Owner**:` bold variants and an optional leading list
  marker) and returns the trimmed value. Interpretation of that value:
  - If it **contains `@`** → treat it as an **email**; resolve to a Linear user
    via D4 (roster/override) and derive the handle via D3.
  - If it **does not** contain `@` → treat it as an **explicit handle**: use it
    directly for the `author:<handle>` label (after the D3 sanitiser), and
    resolve it to a Linear user **only** via an override-map entry keyed by that
    handle (else label-only / unassigned). This lets a team write
    `**Owner:** alice` and pin `alice → <uuid>` once in the gitignored override.
- **Rationale**: Git authorship is email-keyed, so an email owner line composes
  directly with the git path and the `users` roster. Allowing a bare handle keeps
  the owner line human-friendly and still non-PII in the label, while keeping
  any handle→UUID binding in the gitignored override (never committed). One
  parser, two value shapes, no schema negotiation.
- **Alternatives considered**: require the owner line to be an email (rejected —
  unfriendly; teams think in handles); parse `Name <email>` RFC-5322 form only
  (rejected — over-engineered; the `@`-test covers the useful cases and a bare
  name still works as a handle). The `Name <email>` form is still handled: it
  contains `@`, so the email inside is extracted by the D3 sanitiser's email
  detection (local-part of the `<...>` address).

---

## D3 — Handle derivation: override handle → email local-part, sanitised, non-PII

- **Decision**: The `<handle>` in `author:<handle>` is, in order: (a) an explicit
  `handle:` from the override-map entry; else (b) for an email identity, the
  **local-part** (before `@`); else (c) for a bare-handle owner line, the value
  itself. The chosen token is then **sanitised** to a label-safe, non-PII form:
  lowercased, runs of non-`[a-z0-9._-]` collapsed to `-`, leading/trailing `-`
  trimmed, capped at a reasonable length. A label MUST NEVER contain a full
  email address (the `@domain` is dropped by construction; FR-005 / SC-006).
- **Rationale**: The local-part is a stable, recognisable, low-PII token (no
  domain, no full address) and is exactly what the Jira sibling uses, preserving
  parity. The override `handle:` lets operators choose a canonical token when the
  local-part is ugly or collides. Sanitising guarantees the token is a valid,
  predictable Linear label name and never leaks a routable address.
- **Alternatives considered**: full email in the label (rejected — PII leak on a
  potentially shareable Issue; violates FR-005); Linear displayName as handle
  (rejected — requires a successful user resolve, so non-members would get no
  handle; the label must work account-independently); a hash of the email
  (rejected — unreadable; defeats the human-attribution purpose).

---

## D4 — Author→Linear-user resolution: dynamic `users` roster, override first

- **Decision**: Resolve an author email to a Linear user UUID as follows:
  1. **Override map first** — if the gitignored authors file has an entry for
     this email (or handle), use its `linear_user_id`. A value of `null` (or an
     entry that omits it) means "known author, no Linear account" → no assignee.
  2. **Workspace roster** — otherwise query the Linear `users` connection once
     per reconcile and match the author email **case-insensitively** against
     member emails. `users(first: 250, includeArchived: false)` with cursor
     pagination (`pageInfo { hasNextPage endCursor }`) until exhausted; index
     `nodes { id email active }` into a module-global cache
     (`_RECONCILE_WORKSPACE_USERS_*`). Skip `active == false` members for
     assignment (a deactivated user is not a valid assignee).
  3. **No match** → return empty (non-member): label-only, unassigned.
- **Rationale**: Linear's `users` query returns members **with their email**
  (unlike Jira's GDPR-restricted email search), so dynamic resolution needs no
  committed configuration for members whose git email matches their Linear email
  — this is the central simplification over the Jira sibling and the reason the
  override map is *optional* here. Caching one paginated fetch keeps cost O(1) in
  spec count (Principle II re-run-cheapness). Override-first lets operators alias
  git-email ≠ Linear-email and pin non-members deterministically.
- **Alternatives considered**: a mandatory static map like Jira (rejected —
  unnecessary on Linear; forces PII into a file even when the roster suffices);
  `users(filter:{ email:{ eq } })` per author (rejected — N queries vs one cached
  roster; more API calls, same result); resolve via `viewer`/org only (rejected —
  that is the operator, not arbitrary authors). **Field-name note**: the root
  field is `users` (a `UserConnection`), NOT `workspaceMembers` (which is not a
  Linear API field) — an earlier code-recon draft used the wrong name; the
  contract pins `users`.

---

## D5 — Optional gitignored override file: `linear-authors.local.yml`

- **Decision**: An OPTIONAL operator-local file at
  `.specify/extensions/linear/linear-authors.local.yml`, modelled exactly on the
  spec-004 `linear-operator.local.yml` split:

  ```yaml
  schema_version: 1
  authors:
    alice@example.com:        # git author email (or a bare handle key)
      handle: alice           # optional; overrides the derived handle
      linear_user_id: "<uuid>"   # optional; explicit assignee
    contractor@example.com:
      handle: contractor
      linear_user_id: null    # known author, no Linear account → label only
  ```

  - The file is **gitignored** by the existing `.specify/extensions/linear/
    *.local.yml` glob (already present for spec 004 — no `.gitignore` change).
  - Only a **`linear-authors.local.yml.sample`** with placeholder values is
    committed (mirrors the operator sample). `install.sh` scaffolds it.
  - The loader `config::load_authors_override` parses it into module globals with
    the existing shallow-YAML parser; **absent file = graceful no-op** (dynamic
    roster resolution still works).
- **Rationale**: Reusing the spec-004 model (same directory, same gitignore glob,
  same `.sample` discipline, same identity-leak guard) means zero new privacy
  surface and consistency with the operator-identity store. Optionality is the
  whole point — the map exists for aliasing and non-members, not as a
  prerequisite.
- **Alternatives considered**: a committed authors map (rejected — would put real
  emails/UUIDs in the tree, violating FR-011 / SC-006 and the #69 identity
  hardening); a global `~/.config` author map (rejected — Principle V forbids
  per-operator global state); embed authors in `linear-config.yml` (rejected —
  mixes committed binding with gitignored identity, the exact thing spec 004
  split apart).

---

## D6 — Config grammar: additive `linear.attribution.*`, default OFF

- **Decision**: Add an additive, default-OFF block to `linear-config.yml`, parsed
  by the existing `config::_parse_file` (shallow two-level YAML), with accessors
  mirroring the spec-007 `mapping.*` / spec-004 operator accessors:

  ```yaml
  linear:
    attribution:
      enabled: false              # master switch; absent/false ⇒ today's behaviour
      assignee: true              # set author assignee on create when resolvable
      label: true                 # stamp author:<handle>
      author_source: [owner_line, git_first_add]   # resolution order (D1)
      authors_file: linear-authors.local.yml        # optional override (D5)
      subissue_label: false       # inherit author label onto sub-issues (default off)
  ```

  Accessors (all defaulting safely): `config::attribution_enabled` (default
  false), `config::attribution_assignee` (default true), `config::attribution_label`
  (default true), `config::attribution_source_order` (default `owner_line
  git_first_add`), `config::authors_file_path` (default the D5 path),
  `config::attribution_subissue_label` (default false).
- **Rationale**: Default-OFF guarantees byte-for-byte backward compatibility
  (FR-015 / SC-005) — an existing install with no `attribution:` block behaves
  exactly as today (operator assignee per FR-034, no author label). Independent
  sub-toggles (assignee vs label vs sub-issue inheritance) let an operator take
  the account-independent label track without touching assignees, or vice versa
  (FR-016). Reusing the existing parser avoids any grammar work.
- **Alternatives considered**: default-ON (rejected — silently changes every
  existing board; violates SC-005); a single boolean with no sub-toggles
  (rejected — operators with non-member-heavy teams want label-only; FR-016
  requires independent control); a separate config file for attribution
  (rejected — it is binding-adjacent policy, belongs in `linear-config.yml`).

---

## D7 — Unresolved-author assignee fallback = UNASSIGNED (clarified)

- **Decision**: When attribution is **ON** and the author cannot be mapped to a
  Linear user (unknown author, or a known non-member), the spec Issue is left
  **unassigned** on create — the bridge omits `assigneeId` and does **not** fall
  back to the operator. The `author:<handle>` label is still stamped whenever the
  author is non-unknown. Operator-as-assignee survives **only** when attribution
  is OFF (FR-009 / FR-015). Resolved in the 2026-06-11 `/speckit-clarify` session.
- **Rationale**: A neutral "no Linear owner yet" is a truthful mirror of the
  filesystem reality and avoids re-introducing the very "everything shows the
  operator" noise the feature exists to remove. Leaving it unassigned is also the
  least-surprising create-only behaviour — an operator can still manually assign
  in Linear and that survives (FR-008).
- **Alternatives considered**: keep the operator as fallback (rejected by the
  clarification — re-creates operator-noise for the unresolved subset, defeating
  the feature's purpose for exactly the specs that most need clear ownership);
  fail the reconcile on an unresolved author (rejected — violates Principle VIII
  / FR-002 graceful degradation).

---

## D8 — Label strip-and-set + create-only assignee integration points

- **Decision**: Reuse the existing machinery at the spec-Issue site:
  - **Label**: in the spec-Issue desired-label computation (the same place
    `phase:*` is filtered and re-added), strip any existing `author:*` label and
    add the resolved `author:<handle>` (when attribution.label is ON and the
    author is non-unknown). Resolution to a label UUID goes through
    `reconcile::_resolve_label_id` with **create-allowed** — `author:*` is added
    to the auto-create allowlist alongside `speckit-spec:*` / `task-phase:*`.
  - **Assignee (create only)**: at the existing create-time assignee site, when
    attribution is ON compute the assignee as `author UUID if resolvable else
    omit`; when OFF, keep `reconcile::_resolve_operator_assignee_id` (FR-034).
    The **update** path continues to never send `assigneeId` (FR-008) — no
    change there, so manual reassignment persists.
  - **Sub-issues**: inherit the `author:<handle>` label only when
    attribution.subissue_label is ON (default OFF); sub-issues never receive the
    author assignee (FR-013).
- **Rationale**: Strip-and-set is already proven idempotent for `phase:*`; the
  `author:*` namespace is bridge-owned exactly like `phase:*`, so a manual
  `author:*` edit is reconciled away (Principle I) while the create-only assignee
  preserves the FR-034 handoff carve-out. Touching only the create-time assignee
  value (not the update path) keeps the idempotency contract intact.
- **Alternatives considered**: a separate `issueUpdate` to set the author
  assignee post-create (rejected — would clobber manual reassignment on every
  run; breaks FR-008); setting the author label via a dedicated mutation outside
  the label-diff (rejected — bypasses the proven diff/zero-churn path).

---

## D9 — Summary surface: per-spec INFO row (resolved author + source)

- **Decision**: Emit a per-spec INFO row via the existing `summary::add info`
  showing the resolved author, the source, and the assignment outcome, e.g.
  `spec 010: author=alice@example.com (owner_line) → assigned <uuid-tail>` /
  `… (git_first_add) → unassigned (non-member)` / `author=unknown (no owner/git)`.
  Attribution-OFF emits nothing new.
- **Rationale**: Principle VIII observability + FR-003 — an operator must be able
  to see how each spec was attributed and why a given spec ended up unassigned,
  without enabling debug logging. Reuses the spec-003 drift-surface INFO row
  model; no new output channel.
- **Alternatives considered**: warn-level for unresolved authors (rejected — an
  unknown/non-member author is expected and not a problem; INFO is correct);
  no summary line (rejected — fails FR-003's "surface resolved author + source").

---

## D10 — Identity-leak guard extension (#69 posture)

- **Decision**: Extend `install::assert_no_identity_leak` so that, in addition to
  the operator keys/emails it already scans for, it rejects (a) a **committed**
  (tracked, non-`.sample`) `linear-authors.local.yml`, and (b) any email-shaped
  string or Linear-UUID-shaped string in committed `linear-config.yml` /
  `*.sample`. The `.sample` ships only placeholder values. Warn by default;
  hard-fail under the existing `SPECKIT_LINEAR_STRICT_IDENTITY=1`.
- **Rationale**: The whole privacy contract (SC-006, FR-011) hinges on the
  authors map never being committed; the guard that already protects the operator
  file is the natural, consistent enforcement point. Reusing its warn/strict
  modes keeps one identity-hygiene surface.
- **Alternatives considered**: a brand-new guard (rejected — duplicates the #69
  machinery); rely on `.gitignore` alone (rejected — a glob miss or a force-add
  would silently leak; defence-in-depth wants the scan too).

---

## D11 — Testing strategy

- **Decision**: Unit-first with stubbed transport, mirroring `tests/unit/
  reconcile.bats` (source + stub `graphql::*` + assert). Coverage:
  - `parser::spec_owner_line` (bold variants, list-marker, `Name <email>`, absent);
  - `parser::spec_git_first_author` (temp git repo, first-add wins over later
    commits; no-history → empty);
  - `parser::resolve_author` (owner beats git; git fallback; both absent → unknown);
  - config accessors + **default-OFF** assertions; `config::load_authors_override`
    (alias entry, `null` user, absent file → no-op);
  - `reconcile::_resolve_author_user` (override-first; roster case-insensitive
    match; inactive skipped; non-member → empty);
  - `reconcile::_author_handle` (local-part, override handle, sanitiser drops
    `@domain`, never emits a raw email);
  - label strip-and-set for `author:*`; **assignee OMITTED on update**;
    **unassigned on unresolved when ON**; **attribution-OFF == baseline**
    (operator assignee, no author label) — the SC-005 byte-for-byte guard;
    identity-leak guard rejects a committed authors file.
  - Integration (gated `RUN_INTEGRATION_TESTS`): a two-author fixture repo →
    each spec Issue carries the right label and the right assignee/unassigned.
- **Rationale**: The behavioural invariants (idempotency, create-only assignee,
  default-OFF parity, no-PII) are all unit-checkable offline; this is the proven
  pattern in this repo and keeps CI hermetic.
- **Alternatives considered**: integration-only (rejected — slow, needs a live
  workspace, can't run in CI per `RUN_INTEGRATION_TESTS=0`).

---

## D12 — Cross-sink parity map (vs spec-kit-jira author-attribution)

- **Decision**: Lock parity at the **user-visible level**; document the internal
  divergence:

  | Aspect | Linear (this feature) | Jira sibling | Locked? |
  |---|---|---|---|
  | Authorship label | `author:<handle>` | `author:<handle>` | **Yes** (visible) |
  | Assignee timing | on create only, never update | on create only, never update | **Yes** (visible) |
  | Author resolution | `Owner:` line → git first-add → unknown | same | **Yes** (visible) |
  | Unresolved fallback | unassigned (D7) | project default / unassigned | visible-equivalent |
  | Handle source | override handle → email local-part | same | **Yes** (visible) |
  | Identity → account | **dynamic** `users` roster; override **optional** | **static map mandatory** (GDPR) | **No** (internal) |
  | Default-assignee policy note | N/A (Linear has no lead-auto-assign) | FR-G PROJECT_LEAD caveat | internal |
  | Opt-in, default OFF | yes | yes | **Yes** (visible) |

- **Rationale**: This is the exact precedent set by spec 008 (ADR mirroring):
  match what the operator sees across sinks, let the plumbing differ where the
  platforms differ. The dynamic-vs-static resolution is invisible to the board.
- **Alternatives considered**: force a mandatory static map on Linear too for
  literal internal parity (rejected — needless PII and config burden; parity is a
  user-visible contract, not an implementation one).
