# Contract: Author Resolution, Users Query & Issue Projection

**Feature**: `010-author-attribution` | **Date**: 2026-06-11

Defines (1) the parser surface that resolves an author from the filesystem,
(2) the read-only Linear `users` query and author→user mapping, and (3) how the
resolved author projects onto the spec Issue's label + create-time assignee.

---

## 1. Parser surface (parser.sh) — filesystem author resolution

### `parser::spec_owner_line <spec_md_path> → identity | ""`
- Scans for the first line matching (case-sensitive label, tolerant markup):
  `^\s*[-*]?\s*\*\*(Owner|Author)\*\*\s*:\s*(.+?)\s*$`
- Echoes the trimmed capture group. Empty output if absent.
- A `Name <email>` value is returned verbatim; the `@`-test downstream extracts
  the email.

### `parser::spec_git_first_author <spec_dir> → email | ""`
- `git -C <repo> log --diff-filter=A --reverse --format='%ae' -- <spec_dir> |
  head -1`.
- Empty if no git history, dir untracked, or not a git repo (graceful — no error,
  no `set -e` abort: capture as `x="$(…)" || x=""`).

### `parser::resolve_author <spec_dir> <spec_md> → "<identity>\t<source>"`
- Applies `config::attribution_source_order` (default `owner_line git_first_add`):
  first source that yields a non-empty identity wins.
- Emits `<identity>\t<source>` with `source ∈ {owner_line, git_first_add}`; emits
  `\tunknown` (empty identity) when no source resolves.
- Tab-separated, single line. No trailing newline beyond the record.

**Graceful contract**: none of these may fail the reconcile; absence is empty
output, not an error (FR-002 / Principle VIII).

---

## 2. Linear `users` query (read-only) — author→user mapping

### Query (reused `graphql::query` transport)

```graphql
query AttributionUsers($after: String) {
  users(first: 250, after: $after, includeArchived: false) {
    nodes { id email active }
    pageInfo { hasNextPage endCursor }
  }
}
```

- Root field is **`users`** (a `UserConnection`) — NOT `workspaceMembers`.
- Paginate via `pageInfo.hasNextPage`/`endCursor` until exhausted.
- Index `nodes` into the per-run cache; key by `lower(email)`; record `id` +
  `active`.
- Fetched **lazily** — only when attribution is enabled AND at least one author
  needs assignee resolution. Fetched **at most once** per reconcile (cache).
- Failure (network/permission) ⇒ warn once, treat all authors as non-members for
  this run (label-only), do NOT halt (Principle VIII).

### `reconcile::_resolve_author_user <identity> → uuid | ""`
1. **Override first**: if `config::load_authors_override` recorded `<identity>`
   (or its handle) → return its `linear_user_id`, or `""` if the sentinel
   non-member / `null`.
2. **Roster**: if `<identity>` contains `@`, look up `lower(identity)` in the
   cached roster; return `id` iff present and `active`.
3. Else `""` (non-member / unknown / inactive).

### `reconcile::_author_handle <identity> → handle`
- Override `handle` → email local-part → bare identity (D3), then sanitise
  (lowercase, collapse non-`[a-z0-9._-]` to `-`, trim `-`, length-cap).
- MUST NOT emit a string containing `@` or a full email (SC-006).

---

## 3. Projection onto the spec Issue

### Label (when `config::attribution_label` && author ≠ unknown)
- At the spec-Issue desired-label computation (same site as `phase:*`):
  - strip every existing `author:*` from the current label set;
  - add `author:<handle>`;
  - resolve names→UUIDs via `reconcile::_resolve_label_ids_array`; `author:*` is
    added to the **auto-create allowlist** in `reconcile::_resolve_label_id`
    (alongside `speckit-spec:*`, `task-phase:*`).
- **Idempotent**: unchanged author ⇒ identical label set ⇒ no `issueUpdate`
  (zero churn, SC-003). Author change ⇒ exactly one strip + one add.

### Create-time assignee
| Condition | `assigneeId` on create |
|---|---|
| attribution OFF | operator (`_resolve_operator_assignee_id`, FR-034) |
| ON + `assignee` true + author resolves to active member | author UUID |
| ON + author unresolved (unknown / non-member / inactive) | **omitted (unassigned)** (D7) |
| ON + `assignee` false | omitted (unassigned); label still stamped |

### Update-time assignee
- **Never sent**, in all cases (FR-008). Manual reassignment persists. This is
  the existing FR-034 invariant — unchanged by this feature.

### Sub-issues
- Author **label** inherited iff `config::attribution_subissue_label` (default
  OFF). Author **assignee** never set on sub-issues (FR-013).

---

## 4. Summary projection (summary.sh) — FR-003

One INFO row per spec when attribution is enabled:

```text
INFO  spec 010-author-attribution: author=alice@example.com (owner_line) → assigned …e4f1
INFO  spec 011-foo: author=bob@example.com (git_first_add) → unassigned (non-member)
INFO  spec 012-bar: author=unknown (no owner/git) → unassigned
```

Attribution OFF ⇒ no author INFO rows.

---

## 5. Invariants (acceptance-bearing)

- **I1 (idempotency, SC-003)**: second run over unchanged disk ⇒ 0 author label
  writes, 0 assignee writes.
- **I2 (never-clobber, SC-004)**: `assigneeId` absent from every `issueUpdate`
  input ⇒ manual reassignment survives.
- **I3 (default-OFF parity, SC-005)**: OFF ⇒ no author label, operator assignee,
  no `users` query — identical to baseline.
- **I4 (no PII, SC-006)**: no label contains `@`; no real email/UUID in any
  tracked file; identity-leak guard green.
- **I5 (graceful, SC-007)**: unknown/non-member author never halts the reconcile.
