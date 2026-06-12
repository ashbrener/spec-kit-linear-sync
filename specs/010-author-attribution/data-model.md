# Data Model: Author-Based Attribution

**Feature**: `010-author-attribution` | **Date**: 2026-06-11

This feature introduces **no new Linear entity** and **no schema/mapping change**.
It adds in-process entities (a resolved author, a handle, an optional override
map, a config block) and projects them onto two existing Linear attributes of the
**spec Issue**: an `author:<handle>` label and the create-time `assigneeId`. The
entities below are the internal model the parser/config/reconcile layers build.

---

## Entity: Resolved Author

The identity attributed to one spec. Account-independent.

| Field | Type | Source | Notes |
|---|---|---|---|
| `identity` | string | filesystem | An email (contains `@`) or a bare handle, from the `Owner:` line or git first-add email. Empty ⇒ unknown. |
| `source` | enum | resolver | `owner_line` \| `git_first_add` \| `unknown`. Surfaced in the summary (FR-003). |
| `handle` | string | derived | The non-PII label token (D3). Present iff `source ≠ unknown`. |
| `linear_user_id` | UUID? | override / roster | Resolved assignee. `null`/absent ⇒ non-member (label-only, unassigned). |

**Resolution rule (FR-001, D1)**: `owner_line` value if a `**Owner:**`/`**Author:**`
line exists in `spec.md`; else the first git author email to add the spec dir;
else `unknown`. **State**: a pure function of filesystem state — recomputed every
reconcile, never cached to disk (Principle II).

**Validation**:
- `unknown` ⇒ no label, no assignee, no failure (FR-002).
- `handle` is sanitised label-safe and MUST NOT contain `@` or a full email
  (FR-005 / SC-006).
- `linear_user_id`, when set, MUST be a member that is not archived/inactive
  (D4) — otherwise treated as non-member (unassigned).

---

## Entity: Author Handle

The stable, non-PII token rendered into `author:<handle>`.

| Derivation order | Value |
|---|---|
| 1. override `handle:` | explicit token from the override entry |
| 2. email identity | local-part (before `@`) |
| 3. bare-handle identity | the owner-line value itself |

Then **sanitised**: lowercase → collapse non-`[a-z0-9._-]` to `-` → trim leading/
trailing `-` → length-cap. Example: `Alice.Smith@corp.example` → `alice.smith`;
override `handle: asmith` → `asmith`.

**Invariant**: the resulting label name never contains the `@domain` portion.

---

## Entity: Authors Override Map (optional, gitignored)

Operator-local aliasing + non-member pinning. Modelled on the spec-004
`linear-operator.local.yml`. **Never committed** (the `*.local.yml` gitignore glob
covers it); only a `.sample` with placeholders is tracked.

```yaml
schema_version: 1
authors:
  <git-email-or-handle>:
    handle: <token>          # optional — overrides derived handle
    linear_user_id: <uuid>   # optional — explicit assignee; null = known non-member
```

| Field | Type | Required | Meaning |
|---|---|---|---|
| `schema_version` | int | yes | `1` |
| `authors` | map | yes | keyed by git author email (preferred) or a bare handle |
| `authors.<k>.handle` | string | no | overrides D3 derivation |
| `authors.<k>.linear_user_id` | UUID \| null | no | explicit assignee; `null`/absent ⇒ non-member |

**Validation**: absent file ⇒ no-op (dynamic roster still resolves members).
A tracked (non-`.sample`) instance is rejected by the identity-leak guard (D10).

---

## Entity: Workspace Users Roster (runtime cache)

A per-reconcile, in-memory index of Linear members, fetched once.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | candidate `assigneeId` |
| `email` | string | matched case-insensitively against the author identity |
| `active` | bool | inactive members are skipped for assignment |

**Source**: the `users` connection (paginated, D4). **Lifetime**: a module-global
cache (`_RECONCILE_WORKSPACE_USERS_*`) populated lazily on first author lookup and
reused for the rest of the run. **Not persisted** to disk (Principle II).

---

## Entity: Attribution Config Block

Additive, default-OFF policy in `linear-config.yml` under `linear.attribution`.

| Key | Type | Default | Controls |
|---|---|---|---|
| `enabled` | bool | `false` | master switch; OFF ⇒ today's behaviour (FR-015) |
| `assignee` | bool | `true` | set author assignee on create when resolvable (FR-007) |
| `label` | bool | `true` | stamp `author:<handle>` (FR-004) |
| `author_source` | list | `[owner_line, git_first_add]` | resolution order (D1) |
| `authors_file` | path | `linear-authors.local.yml` | optional override (D5) |
| `subissue_label` | bool | `false` | inherit author label onto sub-issues (FR-014) |

**Validation**: unknown keys ignored (forward-compat); `enabled:false`/absent ⇒
no author label and operator assignee unchanged (the SC-005 byte-for-byte guard).

---

## Projection onto the spec Issue (existing attributes)

| Linear attribute | Off (today) | On + resolved member | On + non-member/unknown |
|---|---|---|---|
| Label `author:*` | absent | `author:<handle>` (strip-and-set) | `author:<handle>` if non-unknown; absent if unknown |
| `assigneeId` (create) | operator (FR-034) | author UUID | **omitted (unassigned)** (D7/FR-009) |
| `assigneeId` (update) | never sent | never sent | never sent (FR-008) |
| Sub-issue label | n/a | author label iff `subissue_label` on | same |
| Sub-issue assignee | operator (FR-034) | never the author (FR-013) | n/a |

**State transitions** (per spec, across reconciles):

```text
disk author A (member)  → create: assignee=A, label=author:a
disk author changes A→B → update: label strip author:a, set author:b; assignee UNCHANGED (create-only)
operator reassigns in UI → next reconcile: assignee UNCHANGED (never sent on update); label still reconciled
attribution toggled OFF  → next reconcile: author label removed on update; assignee not re-asserted
author becomes unknown   → update: author:* label stripped (none re-added); assignee unchanged
```
