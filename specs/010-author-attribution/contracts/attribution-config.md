# Contract: Attribution Config & Authors Override

**Feature**: `010-author-attribution` | **Date**: 2026-06-11

Defines the additive `linear.attribution.*` config block, its accessors with
defaults, and the optional gitignored authors-override file. All additive and
default-OFF: an install with no `attribution:` block behaves byte-for-byte as
today (FR-015 / SC-005).

## 1. `linear-config.yml` delta (committed)

```yaml
linear:
  # ... existing operator/team/project/mapping keys unchanged ...
  attribution:
    enabled: false                              # master switch (default false)
    assignee: true                              # author assignee on create when resolvable
    label: true                                 # stamp author:<handle>
    author_source: [owner_line, git_first_add]  # resolution order
    authors_file: linear-authors.local.yml      # optional override (gitignored)
    subissue_label: false                       # inherit author label onto sub-issues
```

- Parsed by the existing `config::_parse_file` (shallow two-level YAML; lists via
  the existing inline-`[a, b]` handling). NO new parser.
- The block is OPTIONAL. Absent ⇒ every accessor returns its default below.
- `authors_file` is resolved relative to `.specify/extensions/linear/` when not
  absolute.

## 2. Accessors (config.sh) — name → default → semantics

| Accessor | Default | Semantics |
|---|---|---|
| `config::attribution_enabled` | `false` | echoes `true`/`false`; gate for all attribution writes |
| `config::attribution_assignee` | `true` | author assignee on create when enabled + resolvable |
| `config::attribution_label` | `true` | stamp `author:<handle>` when enabled |
| `config::attribution_source_order` | `owner_line git_first_add` | space-separated order; unknown tokens skipped |
| `config::authors_file_path` | `.specify/extensions/linear/linear-authors.local.yml` | override-map path |
| `config::attribution_subissue_label` | `false` | sub-issue author-label inheritance |

**Contract rules**:
- Every accessor MUST be **safe when the block/key is absent** (return the default;
  never error) — the default-OFF backward-compat guarantee.
- `config::attribution_enabled == false` ⇒ callers MUST NOT stamp an author label
  and MUST resolve the create-time assignee via the existing
  `reconcile::_resolve_operator_assignee_id` (FR-034) — i.e. today's behaviour.

## 3. Authors override file (gitignored) — `linear-authors.local.yml`

```yaml
schema_version: 1
authors:
  alice@example.com:
    handle: alice
    linear_user_id: "00000000-0000-0000-0000-000000000000"
  contractor@example.com:
    handle: contractor
    linear_user_id: null     # known author, no Linear account → label only
```

**Loader** `config::load_authors_override <path>`:
- Absent file ⇒ no-op, success (dynamic roster still resolves members).
- Populates module globals (e.g. `CONFIG_AUTHORS_HANDLE[<key>]`,
  `CONFIG_AUTHORS_USER_ID[<key>]`) keyed by the lowercased email/handle.
- `linear_user_id: null` or omitted ⇒ recorded as the sentinel "non-member".
- MUST tolerate keys that are bare handles (non-email owner-line values).

**File-placement contract**:
- Real file: `.specify/extensions/linear/linear-authors.local.yml` — **gitignored**
  by the existing `*.local.yml` glob (NO `.gitignore` change required).
- Committed: `.specify/extensions/linear/linear-authors.local.yml.sample` ONLY,
  with placeholder values (all-zero UUID, `example.com` emails).
- `install.sh` scaffolds the `.sample` and ensures the glob is present (idempotent).

## 4. Identity-leak guard (install.sh) — extension of `assert_no_identity_leak`

The existing guard (warn by default; hard-fail under
`SPECKIT_LINEAR_STRICT_IDENTITY=1`) MUST additionally reject:

- a **tracked** `linear-authors.local.yml` (i.e. not the `.sample`) — `git
  ls-files` match;
- any email-shaped (`\S+@\S+\.\S+`) or Linear-UUID-shaped
  (`[0-9a-f]{8}-...`) string in a committed `linear-config.yml` or any committed
  `*.sample` author file (placeholders excepted: `example.com`, all-zero UUID).

**SC-006 acceptance**: `tests/unit/install_identity_leak.bats` extended to assert
a planted real-looking authors file / email / UUID is caught.

## 5. Backward-compatibility contract (SC-005)

With `enabled:false` or no `attribution:` block:
- NO `author:*` label is ever written.
- The create-time assignee is the operator (FR-034), unchanged.
- No `users` query is issued (the roster fetch is lazy and gated on enablement).
- Output (summary, mutations) is byte-for-byte identical to the pre-feature
  baseline — the regression guard.
