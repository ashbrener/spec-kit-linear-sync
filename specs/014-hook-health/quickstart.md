# Quickstart: Hook Self-Healing (014)

**Feature**: 014-hook-health | **Date**: 2026-06-24

How an operator experiences the feature, and how to verify it end-to-end.

## The problem it solves

Updating the bridge with `specify extension add linear --from <release-zip> --force`
silently strips the six `after_*` auto-sync hooks from `.specify/extensions.yml`.
Auto-sync then stops firing and your Linear board drifts without any signal. This
feature makes that failure loud and one-command fixable.

## What you'll see

### On a sync (reconcile / `speckit.linear.push`)

If any auto-sync hooks are missing, the run still completes and adds a warning row:

```text
⚠ 3 auto-sync hook(s) not registered (after_tasks, after_implement, after_analyze);
  run /speckit.linear.install to restore
```

In an interactive terminal it then offers a one-key fix:

```text
Re-register 3 missing auto-sync hook(s) now? [y/N]
```

- `y` → re-registers exactly the missing hooks (any hook you deliberately set
  `enabled: false` is left untouched), and the next sync shows no warning.
- anything else → no change; the warning stands. Run `/speckit.linear.install` later
  to restore.

In CI / hook-fired / non-interactive runs there is **no prompt and no mutation** —
just the warning.

### On demand (`speckit.linear.status`)

A first-class hook-health line, always exit 0:

```text
Auto-sync hooks: partial — missing: after_tasks, after_implement
```

(or `all present`, or `none registered — run /speckit.linear.install`).

## Update one-liner (FR-011)

Pin to the latest release tag and re-register hooks after a `--force` update:

```bash
specify extension add linear \
  --from https://github.com/ashbrener/spec-kit-linear-sync/releases/download/v<X.Y.Z>/linear-v<X.Y.Z>.zip \
  --force
# --force strips after_* hooks; restore them:
/speckit.linear.install
```

## Verify it (acceptance walkthrough)

1. **Warn on missing (US1 / SC-001)** — in a repo where the `linear` `after_*` hooks
   were removed from `.specify/extensions.yml`, run a reconcile → the run completes
   AND prints the named warning. (`tests/integration/us1-hook-health-warn.bats`.)
2. **No false positives (SC-002)** — with all six registered, reconcile prints no
   hook-health warning; a hook set to `enabled: false` produces no warning.
3. **Non-blocking (SC-003)** — a reconcile that would otherwise succeed still exits
   the same with the warning present.
4. **Status states (SC-005)** — run `speckit.linear.status` in repos with all / some /
   none registered → reports present / partial(+names) / none, exit 0 each time.
   (`tests/integration/us2-status-hook-health.bats`.)
5. **Once per run (SC-006)** — `--all` over many specs warns exactly once.
6. **Detect/restore agree (SC-004)** — accept the self-heal (or run
   `/speckit.linear.install`); a subsequent reconcile shows zero hook-health warnings.

## Run the tests

```bash
bats tests/unit/hookcheck.bats tests/unit/hookcheck_selfheal.bats
bats tests/integration/us1-hook-health-warn.bats tests/integration/us2-status-hook-health.bats
shellcheck --shell=bash --severity=style src/*.sh   # all src in ONE invocation
```

> Note: `tests/unit/config.bats` "resolve_operator_user_id NEVER reads identity from
> the committed config" fails in THIS dogfood repo only (a local
> `linear-operator.local.yml` is present) and passes in CI — not a regression.
