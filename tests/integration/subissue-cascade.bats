#!/usr/bin/env bats
# tests/integration/subissue-cascade.bats — 013 end-to-end over fixture repos
# (numeric + letter specs), gated by RUN_INTEGRATION_TESTS=1. Exercises the
# composed parser + cascade behaviour: a merged spec drives every phase to Done;
# a letter-indexed merged spec still enumerates phases (by ordinal) and Done.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
load "${SRC_ROOT}/tests/helpers/integration-helpers.bash"
PARSER_SH="${SRC_ROOT}/src/parser.sh"
RECONCILE_SH="${SRC_ROOT}/src/reconcile.sh"

setup() {
    integration::skip_unless_enabled
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-cascade-e2e-XXXXXX")"
    mkdir -p "${TEST_TMP}/numeric" "${TEST_TMP}/letter"
    printf '## Phase 1: Setup\n- [ ] T001 a\n## Phase 2 — Core\n- [ ] T002 b\n' > "${TEST_TMP}/numeric/tasks.md"
    printf '## Phase A — Overlay\n- [ ] T001 a\n## Phase B — Customers\n- [ ] T002 b\n' > "${TEST_TMP}/letter/tasks.md"
}
teardown() { [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"; }

# Resolve every phase's state key for a tasks.md at a given lifecycle phase.
phase_keys() {  # <tasks_md> <lifecycle_phase>
    bash -c "
        source '${RECONCILE_SH}' 2>/dev/null || true
        while IFS=\$'\t' read -r idx name; do
            [ -n \"\$idx\" ] || continue
            reconcile::_phase_state_key '$2' '$1' \"\$idx\"
        done < <(parser::task_phases '$1')
    "
}

@test "merged NUMERIC spec (un-ticked boxes) → every phase Done" {
    run phase_keys "${TEST_TMP}/numeric/tasks.md" merged
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "done" ]
    [ "${lines[1]}" = "done" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "merged LETTER spec → 2 phases enumerated (ordinals) and every phase Done" {
    # phases enumerate (parser broadening) ...
    run bash -c "source '${PARSER_SH}'; parser::task_phases '${TEST_TMP}/letter/tasks.md'"
    [ "${lines[0]}" = $'1\tOverlay' ]
    [ "${lines[1]}" = $'2\tCustomers' ]
    # ... and cascade drives both Done
    run phase_keys "${TEST_TMP}/letter/tasks.md" merged
    [ "${lines[0]}" = "done" ]
    [ "${lines[1]}" = "done" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "non-terminal spec → phases follow the checkbox ratio (un-ticked → todo)" {
    run phase_keys "${TEST_TMP}/numeric/tasks.md" implementing
    [ "${lines[0]}" = "todo" ]
    [ "${lines[1]}" = "todo" ]
}

@test "deterministic: merged keys identical across two passes (zero-churn)" {
    run phase_keys "${TEST_TMP}/letter/tasks.md" merged; local a="$output"
    run phase_keys "${TEST_TMP}/letter/tasks.md" merged; local b="$output"
    [ "$a" = "$b" ]
}
