# Output Contract: ADR Comment on the Spec Issue

**Spec**: `008-adr-mirroring` | **Phase**: 1 (Design) | **Date**: 2026-06-11

**Implements**: FR-002 (ADR comment per decision), FR-003 (stable hidden
marker), FR-004 (zero-churn idempotency), FR-005 (update-in-place),
FR-008 (coexists with clarify comments), FR-009 (Jira parity),
FR-010 (safety guarantees), FR-012 (no real coordinates in tracked files).

**New mutation introduced**: `reconcile::mutate_comment_update` —
the only new write operation added by this feature.

---

## 1. Hidden idempotency marker

Every ADR comment begins with a deterministic HTML comment on its own
line. This marker is the stable identity anchor: the reconciler locates
an existing comment by querying for a body whose first line equals this
marker (using the existing `reconcile::query_existing_comment_body`
machinery, which filters `comments.nodes` by `startswith($marker)`).

**Marker format**:

```
<!-- spec-kit-linear: adr <NNN>-<key> -->
```

Where:

- `adr` is the literal string that namespaces ADR markers and
  distinguishes them from other comment streams (e.g.
  `clarify-session`, `red-team-finding`).
- `<NNN>` is the zero-padded three-digit spec number (e.g. `008`),
  matching the `specs/NNN-feature-name/` directory name.
- `<key>` is the stable decision key as derived by
  `parser::adr_records` (§4 of `research-adr-grammar.md`): the
  explicit heading id (`D1`, `R3`) when present, else the title slug
  with optional positional suffix.

**Example markers** (placeholders only):

```
<!-- spec-kit-linear: adr 008-D1 -->
<!-- spec-kit-linear: adr 008-D2 -->
<!-- spec-kit-linear: adr 008-alias-layer-default-synthesis -->
<!-- spec-kit-linear: adr 008-alias-layer-default-synthesis-2 -->
```

The marker MUST be the very first line of the comment body (no
preceding blank line, no BOM). `reconcile::query_existing_comment_body`
matches on `startswith`, so any content before the marker would break
the lookup.

The `<NNN>-<key>` composite is stable across content edits and
reorderings of the `research.md` source (FR-003). It changes only if
the spec directory is renamed (a rare, operator-visible event) or if the
key itself changes (heading id removed or title changed — treated as a
new ADR; the old comment is orphaned and the new one is created fresh,
consistent with the clarify-session path).

---

## 2. Rendered comment body layout

The full comment body is byte-stable for an unchanged ADR: given the same
`research.md` source, two successive reconciles produce the identical byte
sequence and no Linear mutation occurs (FR-004, SC-002).

**Template** (Markdown; placeholders shown):

```markdown
<!-- spec-kit-linear: adr <NNN>-<key> -->
**ADR <key> — <Title>**

| Field | Value |
|---|---|
| **Status** | <status> |
| **Source** | `specs/<NNN>-<feature-slug>/research.md` |

**Decision**

<decision-text>

**Rationale**

<rationale-text>

**Alternatives considered**

<alternatives-text>
```

**Field rules**:

| Template field | Value source | When absent |
|---|---|---|
| `<key>` | `parser::adr_records` key field | Never absent (always derived) |
| `<Title>` | `parser::adr_records` title field | If empty, omit the `— <Title>` suffix from the heading line |
| `<status>` | `- **Status**:` bullet if present; else `Accepted` | Default `Accepted` (spec Assumptions §"Status default") |
| `<NNN>-<feature-slug>` | Derived from `<spec_dir>` path; never a real workspace path | — |
| `<decision-text>` | `parser::adr_records` decision field (unescaped) | Omit the **Decision** section entirely |
| `<rationale-text>` | `parser::adr_records` rationale field (unescaped) | Omit the **Rationale** section entirely |
| `<alternatives-text>` | `parser::adr_records` alternatives field (unescaped) | Omit the **Alternatives considered** section entirely |

Omitting a section means both the bold heading line and the body below it
are absent from the rendered comment. The table rows for Status and Source
are always present.

**Byte-stability requirement**: the rendered body is produced by a
deterministic template expansion with no timestamps, random values, or
Linear-side state. The same `research.md` input always produces the same
byte sequence, so a byte-for-byte comparison (`[[ "$existing_body" == "$body" ]]`)
is the correct idempotency test (mirroring the clarify-session path).

**Jira parity** (FR-009): the user-visible fields (key, title, status,
decision, rationale, alternatives, source back-reference) and their
one-per-decision-comment placement match the spec-kit-jira ADR feature.
The hidden marker format is Linear-specific
(`<!-- spec-kit-linear: adr … -->` vs the Jira equivalent) but the
rendered body above the marker is parity-locked.

---

## 3. Idempotency state machine

`reconcile::sync_adr_comments` runs the following state machine for each
ADR record emitted by `parser::adr_records`:

```
┌─────────────────────────────────────────────────────────────────────┐
│ For each ADR record <key, body>                                     │
│                                                                     │
│   query_existing_comment_body(<spec_issue_id>, <marker>)            │
│              │                                                      │
│        ┌─────┴──────┐                                               │
│        │            │                                               │
│      null        {id, body}                                         │
│        │            │                                               │
│        │     body == fresh_body?                                    │
│        │       ┌────┴────┐                                          │
│        │     yes         no                                         │
│        │       │         │                                          │
│     CREATE   SKIP      UPDATE                                       │
│  (commentCreate)      (commentUpdate)                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**CREATE (0 existing)**: call `reconcile::mutate_comment_create
<spec_issue_id> <body>` (existing machinery, unchanged). The new
comment starts with the marker so future queries locate it.

**SKIP (body matches)**: log `"adr <key> comment in sync"` and
continue. Zero Linear mutations. This is the steady-state for an
unchanged corpus (SC-002).

**UPDATE (body differs)**: call `reconcile::mutate_comment_update
<comment_id> <body>` (new mutation, §4). This is the path that diverges
from the clarify-session contract (§5).

---

## 4. `reconcile::mutate_comment_update` — the only new mutation

### 4.1 Signature

```bash
reconcile::mutate_comment_update <comment_id> <body>
```

- `<comment_id>`: the Linear comment UUID returned by
  `reconcile::query_existing_comment_body` (the `.id` field of the
  `{id, body}` JSON object).
- `<body>`: the freshly rendered markdown comment body (including the
  leading marker line).

### 4.2 Dry-run behaviour

When `ARG_DRY_RUN == 1`:

```bash
reconcile::log "DRY-RUN commentUpdate id=${comment_id} body_len=${#body}"
summary::add updated "commentUpdate (dry-run)"
return 0
```

This mirrors the logging pattern of `mutate_comment_create` and all
other `mutate_*` wrappers (e.g.
`reconcile::log "DRY-RUN commentCreate issue=${issue_id} body_len=${#body}"`).

### 4.3 GraphQL mutation shape

```graphql
mutation UpdateAdrComment($input: CommentUpdateInput!) {
    commentUpdate(input: $input) {
        success
        comment { id }
    }
}

# CommentUpdateInput {
#   id:   String!   # the existing comment UUID
#   body: String!   # full replacement markdown body
# }
```

Variables:

```json
{
  "input": {
    "id": "<comment_id>",
    "body": "<body>"
  }
}
```

### 4.4 Success and error handling

On `success == true`: call `summary::add updated "commentUpdate <comment_id>"` and return 0.

On transport failure (non-zero exit from `graphql::mutate`):
`summary::add error "commentUpdate <comment_id> failed (transport)"`,
call `reconcile::promote_exit 1`, and return 1.

On `success != true`: `summary::add error "commentUpdate <comment_id> did not return success=true"`,
call `reconcile::promote_exit 1`, and return 1.

Comment failures do NOT block the rest of the reconcile (inherited from
the existing comment contract in `linear-graphql-mutations.md` §4.5).

### 4.5 Placement in the source

`mutate_comment_update` lives in `src/reconcile.sh` immediately after
`reconcile::mutate_comment_create` (line ~1820), keeping the comment
mutation wrappers contiguous and easy to audit together.

---

## 5. Contrast with the clarify-session path

The clarify-session path (`reconcile::sync_clarify_comments`) diverges
in the UPDATE case:

| Concern | Clarify-session path | ADR path |
|---|---|---|
| On body divergence | **warn-don't-overwrite**: `summary::add warned "…existing comment body diverges…; not overwriting"` | **update-in-place**: `mutate_comment_update <id> <body>` |
| Mutation on divergence | none | `commentUpdate` |
| Rationale | Operator may have added nuance to a clarification comment | Filesystem is canonical (Principle I); ADR comments are read-only mirrors |

The warn-don't-overwrite policy on the clarify path exists because
clarification comments may carry operator-added context that is not
captured in `spec.md` bullets. ADR comments carry no such operator
surface: they are strict read-only mirrors of `research.md` decision
blocks (Principle I), and the spec explicitly models manual edits as
"not a control surface" (`spec.md` §"Edge Cases"). Therefore, update-in-place
is not only safe but required by Principle I: "operator-side mutations in
Linear … the next reconcile overwrites them."

This difference is the sole behavioural delta between the two paths and
the sole reason `mutate_comment_update` is introduced as a new mutation.

---

## 6. Principle I justification for update-in-place

Constitution v2.1.0, **Principle I — Filesystem is the source of truth**:

> The filesystem is the single source of truth for all spec-kit state.
> operator-side mutations in Linear (edits, re-assignments, state
> changes) are valid and respected for fields that are NOT managed by the
> bridge; for fields that ARE managed, the next reconcile re-asserts the
> filesystem value.

ADR comment bodies are wholly managed by the bridge — the entire body is
rendered deterministically from `research.md`. An operator editing the
comment body in Linear introduces a divergence between the filesystem
source and the Linear mirror. Principle I requires the next reconcile to
re-assert the filesystem value. `mutate_comment_update` is the mechanism
that fulfils this requirement.

Contrast: the clarify-session comment body is partly operator-extensible
(the operator may add nuance not captured in `spec.md`), so
warn-don't-overwrite is the more conservative and correct posture there.

---

## 7. Scope boundary

`mutate_comment_update` is the **only new mutation** introduced by
spec 008. The mutation count in `linear-graphql-mutations.md` §8
increases by exactly one (`commentUpdate` at reconcile-time). All
other mutations (`commentCreate`, the issue mutations, the webhook
mutation) are unchanged.

No new config keys, no new binding fields, no new workflow states, no
new label families, and no new Linear entity types are introduced by
this feature. The reconcile call site adds one invocation of
`reconcile::sync_adr_comments` after `reconcile::sync_clarify_comments`
in `process_spec` (plan.md §"Source Code"); the existing
`query_existing_comment_body` and `mutate_comment_create` are reused
without modification.
