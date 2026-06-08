#!/usr/bin/env bats
# tests/unit/seed_scope.bats — unit tests for spec 005 (team-scoped /
# non-admin seeding) seed-side mechanics.
#
# Covers, by sourcing src/seed.sh directly and stubbing the GraphQL layer
# (seed.sh is source-safe: main() only runs under the BASH_SOURCE==$0
# guard):
#
#   * team-scoped create_label passes teamId; workspace scope omits it (FR-001)
#   * seed::resolve_scope precedence: --scope flag > config > default (FR-005)
#   * the find-by-name probe captures an existing UUID with NO create (adopt,
#     FR-002/FR-003)
#   * a permission-class create emits the actionable hint naming the resource
#     and the adopt path (FR-004)
#   * the could-not-provision listing names every unresolved persisted
#     resource (FR-011)
#
# Compatible with bats-core 1.11.0.

SRC_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
SEED_SH="${SRC_ROOT}/src/seed.sh"

TEAM_UUID="aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"

# ---------------------------------------------------------------------------
# FR-001 — team-scoped label creation passes teamId; workspace omits it.
# We stub graphql::mutate_capture to RECORD the mutation variables it was
# handed, then echo an ok envelope. The test inspects the recorded vars.
# ---------------------------------------------------------------------------

@test "create_label: team scope adds teamId to the IssueLabelCreateInput (FR-001)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        # Stub the transport so no real call fires; record vars to a file.
        graphql::mutate_capture() {
            printf "%s" "$2" > "'"${BATS_TEST_TMPDIR}"'/vars.json"
            printf "%s" "{\"ok\":true,\"class\":\"ok\",\"response\":{\"data\":{\"issueLabelCreate\":{\"success\":true,\"issueLabel\":{\"id\":\"lbl-1\"}}}}}"
        }
        SEED_SCOPE="team"
        seed::create_label "phase:specifying" "" "team" "'"${TEAM_UUID}"'"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "lbl-1" ]
    run jq -r '.input.teamId' "${BATS_TEST_TMPDIR}/vars.json"
    [ "$output" = "${TEAM_UUID}" ]
}

@test "create_label: workspace scope omits teamId (FR-013)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        graphql::mutate_capture() {
            printf "%s" "$2" > "'"${BATS_TEST_TMPDIR}"'/vars.json"
            printf "%s" "{\"ok\":true,\"class\":\"ok\",\"response\":{\"data\":{\"issueLabelCreate\":{\"success\":true,\"issueLabel\":{\"id\":\"lbl-2\"}}}}}"
        }
        SEED_SCOPE="workspace"
        seed::create_label "phase:specifying" "" "workspace" "'"${TEAM_UUID}"'"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "lbl-2" ]
    run jq -r '.input.teamId // "ABSENT"' "${BATS_TEST_TMPDIR}/vars.json"
    [ "$output" = "ABSENT" ]
}

# ---------------------------------------------------------------------------
# FR-005 — scope resolution precedence: flag > config > default.
# ---------------------------------------------------------------------------

@test "resolve_scope: --scope flag wins over everything (FR-005)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        ARG_SEED_SCOPE="workspace"
        seed::resolve_scope
    '
    [ "$status" -eq 0 ]
    [ "$output" = "workspace" ]
}

@test "resolve_scope: no flag, no config loaded → default team (FR-005)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        ARG_SEED_SCOPE=""
        CONFIG_LOADED_PATH=""
        seed::resolve_scope
    '
    [ "$status" -eq 0 ]
    [ "$output" = "team" ]
}

@test "resolve_scope: invalid --scope value halts (FR-005)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        summary::start "test"
        ARG_SEED_SCOPE="org"
        rc=0
        seed::resolve_scope || rc=$?
        printf "rc=%s\n" "$rc"
        summary::emit
    '
    [[ "$output" == *"rc=2"* ]]
    [[ "$output" == *"invalid --scope value"* ]]
}

# ---------------------------------------------------------------------------
# FR-002 / FR-003 — adopt: an existing resource is captured by name with
# NO create mutation.
# ---------------------------------------------------------------------------

@test "reconcile_workflow_states: existing state is adopted with no create (FR-002)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        summary::start "test"
        # Probe returns a real UUID for every state → adopt path.
        seed::query_workflow_state() { printf "ws-uuid-for-%s\n" "$2"; }
        # If a create EVER fires, mark it so the test can detect the breach.
        seed::create_workflow_state() { printf "CREATE-FIRED" >> "'"${BATS_TEST_TMPDIR}"'/created"; printf "x\n"; }
        SEED_SCOPE="team"
        seed::reconcile_workflow_states "'"${TEAM_UUID}"'"
        # Every lifecycle key should be captured.
        printf "captured=%s\n" "${#SEED_WORKFLOW_UUIDS[@]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"captured=9"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/created" ]
}

# ---------------------------------------------------------------------------
# FR-004 — a permission-class create emits an actionable hint naming the
# resource and pointing at the adopt path.
# ---------------------------------------------------------------------------

@test "create_workflow_state: permission error → actionable hint + denied rc (FR-004)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        summary::start "test"
        graphql::mutate_capture() {
            printf "%s" "{\"ok\":false,\"class\":\"permission\",\"message\":\"HTTP 403: forbidden\"}"
        }
        rc=0
        seed::create_workflow_state "'"${TEAM_UUID}"'" "Specifying" "unstarted" "#fff" "1" || rc=$?
        printf "rc=%s\n" "$rc"
        summary::emit
    '
    # The denied sentinel rc is 10.
    [[ "$output" == *"rc=10"* ]]
    # The hint names the resource and points at the adopt path.
    [[ "$output" == *"Specifying"* ]]
    [[ "$output" == *"permission"* ]]
    [[ "$output" == *"ADOPT"* ]] || [[ "$output" == *"adopt"* ]]
}

# ---------------------------------------------------------------------------
# FR-011 — the could-not-provision listing names every unresolved persisted
# resource.
# ---------------------------------------------------------------------------

@test "report_unresolved: lists every could-not-provision resource by name (FR-011)" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        summary::start "test"
        SEED_UNRESOLVED=(["workflow state '"'"'Specifying'"'"'"]=1 ["agent label '"'"'agent:claude'"'"'"]=1)
        seed::report_unresolved
        printf "exit=%s\n" "$SEED_EXIT_CODE"
        summary::emit
    '
    [[ "$output" == *"Specifying"* ]]
    [[ "$output" == *"agent:claude"* ]]
    [[ "$output" == *"could be neither created"* ]]
    [[ "$output" == *"exit=1"* ]]
}

@test "report_unresolved: no-op when nothing unresolved" {
    run bash -c '
        set -euo pipefail
        source "'"${SEED_SH}"'"
        summary::start "test"
        SEED_UNRESOLVED=()
        seed::report_unresolved
        printf "exit=%s\n" "$SEED_EXIT_CODE"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"exit=0"* ]]
}
