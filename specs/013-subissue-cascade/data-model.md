# Data Model: Lifecycle Cascade to Task-Phase Sub-Issues

**Feature**: `013-subissue-cascade` | **Date**: 2026-06-22

No new Linear entity, no schema/config/mapping change. This feature changes how an
existing field (the task-phase sub-issue's workflow state) is computed and
broadens the in-process phase-index model. Entities below are the in-process
values the parser + reconcile layers build.

---

## Entity: Spec lifecycle phase (existing, newly consumed by children)

| Field | Type | Source | Notes |
|---|---|---|---|
| `lifecycle_phase` | enum | `parser::lifecycle_phase` (PR/merge + artifact ladder) | One of specifying…merged. **Terminal** = `ready_to_merge` \| `merged`. |

**New use**: passed into `sync_task_phase_subissues` (4th arg) and used to decide
the child state source. Already authoritative for the parent (FR-013); now also
for the children.

---

## Entity: Task-phase sub-issue workflow state (changed computation)

| Condition | Sub-issue `stateId` source |
|---|---|
| spec lifecycle **terminal** (`ready_to_merge`/`merged`) | `done` (override — independent of checkboxes) |
| spec lifecycle **non-terminal** | `reconcile::subissue_state_key` (checkbox ratio — unchanged) |

- Applied on **both** the create-time `stateId` and the update-time state diff.
- `subissue_state_key` (todo/in_progress/done from the checkbox ratio) is itself
  **unchanged** — only its result is overridden on terminal phases.
- The sub-issue **description** (the `tasks.md` checklist mirror) is **unchanged**
  by this feature (FR-006): state = lifecycle truth; body = mirror.

**State transitions (per sub-issue, across reconciles):**

```text
spec implementing, 0 boxes ticked   → sub-issue Todo        (checkbox ratio)
spec implementing, all boxes ticked → sub-issue Done        (checkbox ratio)
spec → ready_to_merge / merged      → sub-issue Done         (cascade override)
merged spec, re-reconcile unchanged → no state write         (zero-churn, SC-002)
merged → (reopened) implementing    → sub-issue back to checkbox ratio
```

---

## Entity: Phase index — ordinal (broadened, single identifier)

`split_phase_header(line, out)` populates:

| Key | Type | Meaning | Used by |
|---|---|---|---|
| `out["ok"]` | 0/1 | parseable phase header? | all phase consumers |
| `out["idx"]` | int (ordinal) | digit index as-is; single letter → `A/a→1 … Z/z→26` | the **single** phase identifier: `task-phase:<ordinal>` label, inter-phase blocking order, `tasks_in_phase`/`phase_estimate` match, AND the sub-issue title `Phase <ordinal> — <name>` |
| `out["name"]` | string | trimmed phase name | sub-issue title/name |

**Grammar (broadened, separator-gated):** the `## Phase` prefix then `[0-9]+`
**or** a single `[A-Za-z]`, then a separator (`:` / em-dash / `-`) **or** whitespace **or**
end-of-line. Anything else → `out["ok"]=0` (near-miss). So `## Phase one`,
`## Phase 1Setup`, `## Phase AB`, `## Phase :` all remain **rejected**.

**Validation / invariants:**
- Numeric phase ⇒ `idx ==` the authored number (byte-for-byte back-compat:
  labels, titles, blocking, matching unchanged).
- Letter phase ⇒ `idx` = alphabet position (stable under reorder); the title
  normalizes to `Phase <ordinal>` (e.g. `Phase 1`). No display token.
- **No phase-enumeration contract change**: `parser::task_phases` still emits
  `<idx>\t<name>`; `tasks_in_phase`/`phase_estimate` still match on `idx`. Only
  the numeric value differs for letter phases.

---

## Resolution examples

| Header | ok | idx | name | sub-issue title | label |
|---|---|---|---|---|---|
| `## Phase 1: Setup` | 1 | 1 | Setup | `Phase 1 — Setup` | `task-phase:1` |
| `## Phase A — Overlay` | 1 | 1 | Overlay | `Phase 1 — Overlay` | `task-phase:1` |
| `## Phase B — Customers` | 1 | 2 | Customers | `Phase 2 — Customers` | `task-phase:2` |
| `## Phase one` | 0 | — | — | (near-miss warning) | — |
| `## Phase 1Setup` | 0 | — | — | (near-miss warning) | — |
