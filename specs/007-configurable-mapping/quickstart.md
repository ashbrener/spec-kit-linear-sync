# Quickstart — Configurable Artifact Mapping

How an operator drives the configurable artifact mapping. Mapping, detection,
and validation live entirely in the source-agnostic config layer (`config.sh`);
the reconcile engine stays vendor-neutral. Real coordinates live only in the
gitignored `.specify/extensions/linear/linear-operator.local.yml` and the
`.env`; this file uses placeholders only (FR-018).

Every mode below preserves the constitutional differentiators: idempotency
(zero-churn re-run), drift-awareness on the spec-level work unit, and
fail-closed config-load.

---

## 1. Zero-config (the safe upgrade)

Do nothing. With no `mapping:` block, the alias layer synthesizes today's
shipped default — `repo→Project`, `spec→Issue`, `phase→sub-issue`,
`task→in-body checklist` — byte-for-byte. No file rewrite, no version bump.

```bash
/speckit.linear.push --all --dry-run    # confirm: same creates/updates as before
/speckit.linear.push --all
```

A no-config upgrade changes nothing; a re-run is zero churn.

**What Linear looks like:**

```
Project  (one per repo)
└── Issue  (one per spec)
    └── sub-issue  (one per task phase)
            tasks rendered as an in-body checklist
```

This is the frozen zero-config default. It is upgrade-safe: a pre-feature
`linear-config.yml` with no `mapping:` block loads unchanged and projects
byte-identically.

---

## 2. The #17 spec-as-Project shape

The headline configurable choice. Promote each spec to its own **Project**,
making task phases first-class Issues and individual tasks sub-issues. Add a
`mapping:` block under `linear:` in
`.specify/extensions/linear/linear-config.yml`:

```yaml
linear:
  team:
    id: "<TEAM-UUID>"
  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "none"
      phase:
        artifact: "Issue"
        relationship_to_parent: "none"
      task:
        artifact: "sub-issue"
        relationship_to_parent: "parent"
```

**What Linear looks like:**

```
Project (repo)           ← repo level, unchanged
Project (spec)           ← each spec becomes its own Project
└── Issue  (task phase)
    └── sub-issue  (individual task)
```

This resolves design issue #17 entirely through the `mapping:` grammar — no
code change. The `spec` level carries a stable `speckit-spec:NNN` label as its
filesystem-derived identity so re-runs match and update rather than re-create.

---

## 3. Partial mapping (per-level inheritance)

Override only the levels you care about. Unspecified levels inherit the
synthesized default — this is not all-or-nothing. To promote just the spec
level while leaving phase and task untouched:

```yaml
linear:
  team:
    id: "<TEAM-UUID>"
  mapping:
    levels:
      spec:
        artifact: "Project"
        relationship_to_parent: "none"
```

**Result:** `spec→Project` uses the configured artifact; `repo`, `phase`, and
`task` fall back to the synthesized default (`Project`, `sub-issue`,
`checklist`). A re-run against unchanged state is zero churn.

A partial block that specifies only some levels mirrors identically to a full
block that spells out the same overrides alongside the defaults.

---

## 4. Narrative super-level — L0 Milestone (optional, off by default)

Turn on a narrative level above the repo. Off by default; no Milestone is
created when the key is absent or `enabled: false`.

```yaml
linear:
  team:
    id: "<TEAM-UUID>"
  mapping:
    super_level:
      enabled: true
      artifact: "Milestone"       # Linear's free-form narrative primitive
      on_absent: "degrade"        # fold onto the repo level — never hard-fail
      source: "spec_input"        # spec.md "Input:" line; NEVER inferred
```

**Where Project Milestones are available:** one Milestone is created above the
repo level; its narrative is populated only from the explicit `source` field
(the spec's input description), never inferred or fabricated.

**Where Project Milestones are unavailable** (the team/plan does not support
them): the run degrades gracefully — the narrative folds onto the repo-level
Project behind a stable marker, repo grouping is carried as a label, and the
run succeeds. No hard failure.

The spec-level work unit remains the backward-drift anchor in both cases; the
narrative super-level is not a new drift surface.

---

## 5. What gets rejected

Before any Project, Issue, or sub-issue is created or modified, the config
layer validates every configured relationship against an **offline
relationship-validation matrix**. Any failure hard-halts at config-load and
writes nothing (fail-closed, Principle VIII). No partial mirrors are possible.

The three classes of nonsensical hierarchy relationships are rejected:

| Configured combination | Why it is rejected |
|---|---|
| `blocks` or `relates` used as a hierarchy (parent→child) link | These are dependency-style links, not nesting primitives. A hierarchy built on `blocks` would produce a corrupt Linear graph. |
| `parent` declared on the **top level** (the `repo` level) | The repo level has no parent; a `parent` relationship there is structurally impossible. |
| `artifact: "checklist"` paired with any `relationship_to_parent` other than `"checklist"` | The checklist sentinel is not a standalone Linear issue; it must render into its parent's body. Pairing it with `parent` or `none` is incoherent. |

Allowed hierarchy links are `parent` (native sub-issue nesting), `none` (top
level), and `checklist` (renders into the parent body).

Validation is offline — it requires no Linear API call — and completes before
any write.

---

## 6. Grammar parity with spec-kit-jira

The Linear `mapping:` block above is structurally equivalent to the
spec-kit-jira `mapping:` grammar: same level names (`repo` / `spec` / `phase`
/ `task`), same `artifact` + `relationship_to_parent` field shape, same
optional/additive alias semantics, same relationship-matrix shape. A reader of
one sink's config file understands the other.

---

## 7. Before pushing — run the exact CI locally

```bash
shellcheck --shell=bash --severity=style src/*.sh
yamllint -d relaxed .github/workflows/ci.yml
npx --yes markdownlint-cli2 "specs/**/*.md" "*.md"
bats --recursive tests/unit
```

Privacy guard (`tests/unit/no-real-identifiers.bats`) must stay green — no
real Linear coordinates in any tracked file (FR-018).
