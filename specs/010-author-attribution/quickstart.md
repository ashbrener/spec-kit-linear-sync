# Quickstart: Author-Based Attribution

**Feature**: `010-author-attribution` | **Date**: 2026-06-11

Operator-facing: what author attribution does, how to turn it on, and what shows
up in Linear. **Opt-in, default OFF** — doing nothing changes nothing.

## What it does

Makes each spec's Linear Issue reflect **who authored the spec**, not who ran the
sync. Two independent tracks:

- **`author:<handle>` label** — always stamped (works for everyone, including
  people with no Linear account).
- **Assignee** — the spec Issue is assigned to the author *on creation*, **only**
  when the author is a Linear member. A manual reassignment in Linear is never
  overwritten.

Authors who aren't Linear members (or can't be resolved) get the label but the
Issue is left **unassigned** — a neutral mirror, never the operator.

## Enabling it

Add an `attribution:` block to `.specify/extensions/linear/linear-config.yml`:

```yaml
linear:
  attribution:
    enabled: true        # everything below only applies when this is true
    assignee: true       # assign the author on create (members only)
    label: true          # stamp author:<handle>
```

That's the whole minimum. The next reconcile (any `after_*` hook, or
`speckit.linear.push`) applies it.

## How the author is resolved

Per spec, in order:

1. An explicit owner line in `spec.md` — add either to the metadata block:
   ```markdown
   **Owner:** alice@example.com
   ```
   (`**Author:**` works too; a bare handle like `**Owner:** alice` also works.)
2. Otherwise, the **first** person to commit the spec directory (git history).
3. Otherwise *unknown* — no label, no assignee, no error.

You'll see how each spec resolved in the run summary:

```text
INFO  spec 010-author-attribution: author=alice@example.com (owner_line) → assigned …e4f1
INFO  spec 011-foo: author=bob@example.com (git_first_add) → unassigned (non-member)
INFO  spec 012-bar: author=unknown (no owner/git) → unassigned
```

## Members are matched automatically

If a spec author's git email matches their Linear email, the bridge resolves them
to the right Linear user **automatically** — no configuration needed. (Linear lets
the bridge read the member roster; this is the main difference from the Jira
sibling, which needs a static map.)

## Optional: aliasing & non-members

Only needed when a git email ≠ a Linear email, or to pin a handle for someone with
no account. Create a **gitignored** override file
`.specify/extensions/linear/linear-authors.local.yml` (copy the committed
`.sample`):

```yaml
schema_version: 1
authors:
  alice@personal-laptop.local:     # the git email
    handle: alice
    linear_user_id: "…alice's Linear user id…"
  contractor@agency.example:
    handle: contractor
    linear_user_id: null           # known author, no Linear account → label only
```

This file is **never committed** (the `*.local.yml` gitignore rule covers it); only
the placeholder `.sample` is tracked. The bridge refuses to let real emails/IDs
land in committed files.

## Turning individual tracks off

- Label only (don't touch assignees): `assignee: false`.
- Assignees only (no labels): `label: false`.
- Also tag sub-issues with the author label: `subissue_label: true` (default off;
  sub-issues are never *assigned* to the author).

## What stays the same

- **Disabled / no block** → exactly today's behaviour: Issues assigned to the
  operator, no author labels.
- A **manual reassignment** in Linear always survives a reconcile.
- Re-running over unchanged specs writes nothing (zero churn).
- The bridge never writes back to your filesystem; authorship is read from
  `spec.md`/git only.

## Verify

1. Enable the block, run a reconcile.
2. Check a spec Issue: it carries `author:<handle>` and (for a member author) the
   right assignee.
3. Reassign one Issue manually in Linear, reconcile again → your assignment
   stays; the label is unchanged.
4. Confirm `git status` shows no `*.local.yml` staged and no real identifiers in
   `linear-config.yml`.
