# Contract: Lifecycle Cascade to Sub-Issue State

**Feature**: `013-subissue-cascade` | **Date**: 2026-06-22

Defines how the spec's terminal lifecycle drives task-phase sub-issue state.

## 1. Signature change (reconcile.sh)

```
reconcile::sync_task_phase_subissues <spec_issue_id> <feature_number> <spec_dir> <lifecycle_phase>
```

- New 4th positional arg `lifecycle_phase` (the value already computed in
  `process_spec`). Optional-safe: an empty 4th arg ⇒ non-terminal behaviour
  (today's), so the change is backward-tolerant.

### Call site (process_spec)

```diff
- reconcile::sync_task_phase_subissues "$spec_issue_id" "$feature_number" "$spec_dir"
+ reconcile::sync_task_phase_subissues "$spec_issue_id" "$feature_number" "$spec_dir" "$lifecycle_phase"
```

## 2. State-key resolution (per phase, both create + update paths)

```
is_terminal(lifecycle_phase) := lifecycle_phase ∈ { ready_to_merge, merged }

state_key :=
    is_terminal ? "done"
                : reconcile::subissue_state_key "$tasks_md" "$ordinal"   # unchanged
state_uuid := config::get_default_state_uuid "$state_key"               # 'done' is an existing key
```

- Applied identically on the **create** `stateId` and the **update** state diff
  (`cur_state != state_uuid → {stateId}`), so a stranded board heals on the next
  reconcile whether the sub-issue is being created or already exists.
- `reconcile::subissue_state_key` is **unchanged** (the non-terminal path).

## 3. Invariants

- **C1 (cascade, SC-001)**: terminal spec ⇒ every sub-issue `stateId` = the `done`
  UUID, regardless of `tasks.md` checkboxes.
- **C2 (idempotent, SC-002)**: terminal→`done` is deterministic ⇒ a second
  reconcile over unchanged state issues no sub-issue state write.
- **C3 (no regression, SC-003)**: non-terminal spec ⇒ sub-issue state is the
  checkbox ratio, byte-identical to pre-feature behaviour.
- **C4 (body unchanged, FR-006)**: the sub-issue description (tasks.md mirror) is
  not modified; only `stateId` is driven by the cascade.
- **C5 (layers)**: Layer E (webhook) is untouched — it flips only the parent
  workflow state; the cascade is Layer-D (reconcile) only.
