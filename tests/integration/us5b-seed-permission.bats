#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us5b-seed-permission.bats — spec 005 User Story 3
#
#   GIVEN an operator whose label-create calls are DENIED with a permission
#         error (the rcollette symptom in #41), but where the persisted
#         resources the bridge depends on (workflow states, default states,
#         agent labels) already EXIST and can be ADOPTED by name,
#   WHEN  `src/seed.sh` runs,
#   THEN  the denied create produces a clear, actionable message naming the
#         resource and pointing at the adopt / team-scoped path (FR-004),
#         AND the run proceeds along the adopt path rather than hard-failing
#         (FR-006): every persisted UUID is captured and the run does not
#         abort cryptically.
#
# Maps to FR-004 + FR-006 + SC-003.
#
# Mock strategy: the locate-union returned by the shim INCLUDES the workflow
# states, the team's stock states, and the agent:* labels (so all PERSISTED
# resources adopt cleanly) but EXCLUDES the phase:* / task-phase:* labels (so
# their create path fires). Every mutation response is a 200 carrying a
# FORBIDDEN errors[] body, which graphql::mutate_capture classifies as a
# permission error — driving the actionable message + adopt fallback.
# =============================================================================

load '../helpers/integration-helpers'

setup() {
    integration::skip_unless_enabled
    integration::setup_sandbox '001-minimal'
    integration::install_gh_shim_no_pr

    local nodes
    nodes='[
{"id":"cccccccc-0001-4ccc-cccc-cccccccccccc","name":"Specifying","type":"unstarted"},
{"id":"cccccccc-0002-4ccc-cccc-cccccccccccc","name":"Clarifying","type":"started"},
{"id":"cccccccc-0003-4ccc-cccc-cccccccccccc","name":"Planning","type":"started"},
{"id":"cccccccc-0004-4ccc-cccc-cccccccccccc","name":"Tasking","type":"started"},
{"id":"cccccccc-0005-4ccc-cccc-cccccccccccc","name":"Red-team","type":"started"},
{"id":"cccccccc-0006-4ccc-cccc-cccccccccccc","name":"Implementing","type":"started"},
{"id":"cccccccc-0007-4ccc-cccc-cccccccccccc","name":"Analyzing","type":"started"},
{"id":"cccccccc-0008-4ccc-cccc-cccccccccccc","name":"Ready-to-merge","type":"started"},
{"id":"cccccccc-0009-4ccc-cccc-cccccccccccc","name":"Merged","type":"completed"}
]'

    local team_states
    team_states='[
{"id":"dddddddd-0001-4ddd-dddd-dddddddddddd","name":"Todo","type":"unstarted"},
{"id":"dddddddd-0002-4ddd-dddd-dddddddddddd","name":"In Progress","type":"started"},
{"id":"dddddddd-0003-4ddd-dddd-dddddddddddd","name":"Done","type":"completed"}
]'

    # Only the agent:* labels are present in the union — the phase / task-phase
    # families are absent so their create path fires (and is denied).
    local labels
    labels='[
{"id":"bbbb0021-1111-4111-1111-111111110021","name":"agent:claude"},
{"id":"bbbb0022-1111-4111-1111-111111110022","name":"agent:codex"}
]'

    integration::stage_response 'query' \
        "{\"data\":{\"workflowStates\":{\"nodes\":${nodes}},\"issueLabels\":{\"nodes\":${labels}},\"team\":{\"states\":{\"nodes\":${team_states}}}}}"

    # Every mutation (the phase / task-phase label creates) returns a 200 with
    # a FORBIDDEN errors[] body → classified as a permission error.
    integration::stage_response 'mutation' \
        '{"errors":[{"message":"You do not have permission to create labels in this workspace","extensions":{"code":"FORBIDDEN"}}]}'

    integration::stage_response 'default' '{"data":{}}'
}

@test "US5b: permission-denied label create → actionable message + adopt fallback (FR-004/FR-006)" {
    run integration::run_seed --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"

    # The run does NOT hard-fail cryptically: the persisted resources adopt
    # and the only failures are the (name-looked-up, non-persisted) phase
    # labels, surfaced as warnings — not a stack dump or raw API error.
    # Exit may be non-zero (warnings promote it), but it must be a clean
    # bridge exit code, not a crash.
    [ "$status" -le 1 ]

    # Actionable message: names the failed resource AND points at the adopt /
    # team-scoped path (FR-004 / SC-003).
    [[ "$output" == *"phase:"* ]]
    [[ "$output" == *"permission"* ]]
    [[ "$output" == *"adopt"* ]] || [[ "$output" == *"ADOPT"* ]] || [[ "$output" == *"--scope team"* ]]

    # NOT a raw GraphQL stack dump / bare error envelope.
    [[ "$output" != *'"errors":[{'* ]]

    # Adopt fallback proceeded: the persisted resources were captured from the
    # existing nodes (not the zero placeholder).
    grep -q 'cccccccc-0001-4ccc-cccc-cccccccccccc' "$LINEAR_CONFIG_PATH"
    grep -q 'bbbb0021-1111-4111-1111-111111110021' "$LINEAR_CONFIG_PATH"
}
