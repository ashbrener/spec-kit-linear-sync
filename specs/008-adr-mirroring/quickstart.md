# Quickstart: ADR / Decision-Record Mirroring

**Spec**: `008-adr-mirroring` | **Phase**: 1 — Design

The decisions you record in a spec's `research.md` automatically show up as
comments on that spec's Linear Issue the next time you sync. There is no extra
command and no new config — it rides the same `after_*` hooks and
`/speckit.linear.push` path that already keeps your spec Issues current.

---

## What it does

Every `Decision / Rationale / Alternatives` block in a spec's `research.md` is
mirrored as a single comment on that spec's Linear Issue. One decision block
becomes one comment. The comment shows the decision id, title, status, the
decision text, the rationale, the alternatives considered, and a back-reference
to the source file.

The mirroring happens inside the existing reconcile pass — the same run that
creates or updates the spec Issue, posts clarify-session comments, and
updates task-phase sub-issues. ADR comments land alongside those artifacts
without disturbing them.

---

## Before and after

### In `research.md`

```markdown
## D1 — Choose the comment-keying strategy

- **Decision**: Key each ADR comment by the explicit heading id when present,
  else by a stable slug derived from the decision's title. Status: Accepted.
- **Rationale**: The key must survive content edits and reordering, so content
  itself cannot be the key; a slug derived from the title is stable across
  those changes.
- **Alternatives considered**: Key by content hash (rejected — any edit would
  lose the existing comment); key by ordinal position (rejected — reordering
  would mis-match all comments downstream of the move).
```

### Comment that appears on the spec's Linear Issue

```text
**ADR D1 — Choose the comment-keying strategy**
Status: Accepted

**Decision**
Key each ADR comment by the explicit heading id when present,
else by a stable slug derived from the decision's title.

**Rationale**
The key must survive content edits and reordering, so content
itself cannot be the key; a slug derived from the title is stable
across those changes.

**Alternatives considered**
Key by content hash (rejected — any edit would lose the existing comment);
key by ordinal position (rejected — reordering would mis-match all
comments downstream of the move).

Source: specs/NNN-feature/research.md
<!-- spec-kit-linear: adr NNN-d1 -->
```

---

## Idempotency — exactly one comment per decision, always

- **First sync**: each decision block produces one new comment on the spec Issue.
- **Re-sync, nothing changed**: zero comments are created, zero are edited.
  Running the reconciler repeatedly against an unchanged `research.md`
  produces no activity in Linear.
- **Decision updated on disk**: the bridge finds the existing comment by its
  stable key and updates it in place. No duplicate is created.
- **New decision added on disk**: one new comment is created for it. Existing
  ADR comments are untouched.

The key used for matching is the explicit heading id (`D1`, `R2`, and so on)
when present, or a stable slug derived from the decision's title when no
explicit id is given. Either way, the key does not change when you edit the
decision text, so updates land on the right comment.

---

## The hidden identity marker

Each ADR comment carries a single hidden marker line:

```text
<!-- spec-kit-linear: adr NNN-<key> -->
```

The bridge uses this marker on every reconcile to locate the existing comment
for that decision. Do not delete that line — removing it causes the bridge to
treat the decision as new and post a duplicate comment rather than updating
the one that already exists.

---

## Specs with no decisions

A spec whose `research.md` does not exist, or exists but contains no
`Decision / Rationale / Alternatives` blocks, produces no ADR comments and no
error. The reconcile completes normally, exactly as it would for any other spec.
The absence of decisions is not a problem the operator needs to address.

---

## Parity with the Jira bridge

ADR mirroring works the same way in the `spec-kit-jira` extension: the same
source (`research.md` decision blocks), the same per-decision-comment placement
on the spec issue, and the same comment layout (fields, ordering, source
back-reference). A team running both bridges sees the same decisions in both
trackers.

---

## Out of scope (this release)

The following are deliberate non-goals for this feature:

- **Linear Documents as a richer ADR home**: mirroring prose ADRs into a
  Linear Document rather than a comment (Option B). This is a possible later
  feature; today every decision becomes a comment on the spec Issue.
- **`docs/adr/` as a source**: reading decision records from a `docs/adr/`
  directory. Today the only source is each spec's own `research.md`.
