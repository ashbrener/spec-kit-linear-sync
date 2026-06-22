#!/usr/bin/env bats
# tests/unit/letter_phase_enumeration.bats — 013: letter phases flow through the
# unchanged 2-field task_phases contract by ordinal; near-miss preserved.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
PARSER_SH="${SRC_ROOT}/src/parser.sh"

setup() {
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/speckit-letterphase-XXXXXX")"
    cat > "${TEST_TMP}/tasks.md" <<'EOF'
## Phase A — Overlay
- [ ] T001 build overlay
- [x] T002 wire route
## Phase B — Customers
- [ ] T003 customers screen
## Phase one — not a phase
- [ ] T999 ignored
EOF
}
teardown() { [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]] && rm -rf "${TEST_TMP}"; }

@test "task_phases stays 2-field, emitting ordinals for letter phases" {
    run bash -c "source '${PARSER_SH}'; parser::task_phases '${TEST_TMP}/tasks.md'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = $'1\tOverlay' ]
    [ "${lines[1]}" = $'2\tCustomers' ]
    [ "${#lines[@]}" -eq 2 ]   # '## Phase one' excluded
}

@test "tasks_in_phase matches a letter phase by its ordinal (A → 1)" {
    run bash -c "source '${PARSER_SH}'; parser::tasks_in_phase '${TEST_TMP}/tasks.md' 1 | cut -f1"
    [ "${lines[0]}" = "T001" ]
    [ "${lines[1]}" = "T002" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "tasks_in_phase ordinal 2 → Phase B's task" {
    run bash -c "source '${PARSER_SH}'; parser::tasks_in_phase '${TEST_TMP}/tasks.md' 2 | cut -f1"
    [ "${lines[0]}" = "T003" ]
    [ "${#lines[@]}" -eq 1 ]
}

@test "near-miss diagnostic still flags '## Phase one'" {
    run bash -c "source '${PARSER_SH}'; parser::phase_header_near_misses '${TEST_TMP}/tasks.md'"
    [[ "$output" == *"## Phase one — not a phase"* ]]
}
