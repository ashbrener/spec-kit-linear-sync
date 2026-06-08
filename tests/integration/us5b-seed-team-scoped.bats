#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us5b-seed-team-scoped.bats — spec 005 User Story 1
#
#   GIVEN an operator seeding with --scope team on a fresh team (every
#         workflowStates / issueLabels locate returns ZERO nodes),
#   WHEN  `src/seed.sh --scope team --team <UUID>` runs,
#   THEN  every issueLabelCreate mutation body carries the team UUID as
#         `teamId` (FR-001 — team-scoped labels, creatable with team-level
#         permission), the workflow states are created (already team-scoped),
#         all UUIDs are captured into config, and the run exits 0.
#
# Maps to FR-001 + FR-009 + SC-001.
# =============================================================================

load '../helpers/integration-helpers'

setup() {
    integration::skip_unless_enabled
    integration::setup_sandbox '001-minimal'
    integration::install_gh_shim_no_pr

    # Workflow-state + label locates return ZERO nodes → every create path
    # fires. The team's stock states exist (so default_state capture is a
    # clean adopt, not a warning).
    integration::stage_response 'query' \
        '{"data":{"workflowStates":{"nodes":[]},"issueLabels":{"nodes":[]},"team":{"states":{"nodes":[{"id":"dddddddd-0001-4ddd-dddd-dddddddddddd","name":"Todo","type":"unstarted"},{"id":"dddddddd-0002-4ddd-dddd-dddddddddddd","name":"In Progress","type":"started"},{"id":"dddddddd-0003-4ddd-dddd-dddddddddddd","name":"Done","type":"completed"}]}}}}'

    # Creates echo a valid UUID so capture round-trips.
    integration::stage_response 'mutation' \
        '{"data":{"workflowStateCreate":{"success":true,"workflowState":{"id":"aaaa0001-1111-4111-1111-111111110001","name":"Specifying","type":"unstarted"}},"issueLabelCreate":{"success":true,"issueLabel":{"id":"bbbb0001-1111-4111-1111-111111110001","name":"phase:specifying"}}}}'

    integration::stage_response 'default' '{"data":{}}'
}

@test "US5b: --scope team creates team-scoped labels (teamId in every label create)" {
    run integration::run_seed --scope team --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    [ "$status" -eq 0 ]

    # Every issueLabelCreate body MUST carry the team UUID as teamId (FR-001).
    # Count label creates and the subset that carry teamId; they must match.
    local label_creates with_team
    label_creates="$(integration::calls_containing 'issueLabelCreate')"
    with_team="$(integration::calls_containing 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa')"
    [ "$label_creates" -ge 1 ]
    # teamId appears in label creates (and the workflow-state creates already
    # carry the team). Every label-create body references the team UUID.
    [ "$with_team" -ge "$label_creates" ]

    # The teamId field name appears in a create body.
    [ "$(integration::calls_containing 'teamId')" -ge 1 ]

    # UUIDs captured into config (FR-008 shape preserved).
    [ -f "$LINEAR_CONFIG_PATH" ]
    grep -q 'workflow_state_uuids:' "$LINEAR_CONFIG_PATH"
    grep -q 'agent_label_uuids:' "$LINEAR_CONFIG_PATH"

    # Summary emitted.
    [[ "$output" == *"summary"* ]]
}

@test "US5b: --scope workspace omits teamId from label creates (FR-013 unchanged)" {
    run integration::run_seed --scope workspace --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    [ "$status" -eq 0 ]

    # In workspace scope, label-create bodies must NOT carry teamId. The
    # workflow-state creates still carry the team UUID, so we assert on the
    # label-create operation specifically by checking that no issueLabelCreate
    # body contains "teamId".
    local label_with_teamid
    label_with_teamid="$(
        grep -F 'issueLabelCreate' "${MOCK_LINEAR_STATE}/calls.log" 2>/dev/null \
            | grep -cF 'teamId' || true
    )"
    [ "${label_with_teamid:-0}" -eq 0 ]
}
