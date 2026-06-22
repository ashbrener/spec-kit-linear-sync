# Contract: Broadened Phase-Header Grammar

**Feature**: `013-subissue-cascade` | **Date**: 2026-06-22

Defines the broadened `split_phase_header` grammar and the ordinal/display split
in the shared `PARSER_PHASE_HEADER_AWK` prologue (consumed by `task_phases`,
`tasks_in_phase`, `phase_estimate`, and the near-miss diagnostic).

## 1. Grammar

A line is a parseable phase header iff:

```
^## Phase <INDEX><GATE>
  INDEX := [0-9]+            (digit run)   |   [A-Za-z]   (exactly one letter)
  GATE  := separator (':' | '—' em-dash | '-')  |  whitespace  |  end-of-line
```

Rejected (→ `out["ok"]=0`, near-miss diagnostic fires), unchanged from today:

- `## Phase one`   (INDEX `o`, then non-gate `n`)
- `## Phase 1Setup` (INDEX `1`, then non-gate `S`)
- `## Phase AB`    (INDEX `A`, then non-gate `B`)
- `## Phase :` / `## Phase` (no index)

The em-dash remains matched as a literal 3-byte UTF-8 sequence under `LC_ALL=C`
(never a bracket class), per the existing #34 locale-safety note.

## 2. Outputs

| Key | Value |
|---|---|
| `out["ok"]` | 1 if parseable, else 0 |
| `out["idx"]` | **ordinal** (int) — the single phase identifier: digit index as-is; single letter → `A/a=1 … Z/z=26` |
| `out["name"]` | trimmed phase name (may be empty) |

No new output field — the structure is unchanged from today; only `idx` gains a
numeric value for single-letter indices.

## 3. Downstream contract (UNCHANGED)

- `parser::task_phases` still emits one line per phase: `<idx>\t<name>` — **no
  contract change**, so every existing consumer/test stays valid.
- `parser::tasks_in_phase <tasks_md> <ordinal>` / `parser::phase_estimate` still
  match on `out["idx"]` — same logic, new numeric value for letter phases.
- The reconcile read loop is unchanged (`read -r phase_index phase_name`); it
  already uses `idx` for the `task-phase:<idx>` label, inter-phase blocking order,
  state lookup, AND the sub-issue title `Phase <idx> — <name>` — so a letter phase
  renders `Phase 1 — <name>` with zero loop changes.

## 4. Invariants

- **G1 (superset)**: every header that parsed before parses identically now
  (`idx ==` the authored number for numeric phases) — byte-for-byte back-compat
  (labels, titles, blocking, matching, and the `task_phases` output).
- **G2 (letter support, SC-004)**: `## Phase A —`/`## Phase B —` parse → one
  sub-issue per phase; `idx` = 1, 2 (alphabet position); labels `task-phase:1`,
  `task-phase:2`; titles `Phase 1 — …`, `Phase 2 — …`.
- **G3 (near-miss preserved, SC-005 / FR-009)**: `## Phase one`, `## Phase
  1Setup`, `## Phase AB`, `## Phase :` still fail to parse and still surface the
  near-miss diagnostic.
- **G4 (stable ordinal)**: a letter's ordinal is its alphabet position, so it is
  stable across phase reordering and idempotent across runs.
