#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us5b-seed-adopt.bats — spec 005 User Story 2
#
#   GIVEN all required workflow states + labels already exist (every
#         workflowStates / issueLabels locate returns exactly one matching
#         node) and the team's stock states exist,
#   WHEN  `src/seed.sh` runs as an operator who cannot create resources,
#   THEN  every required UUID is captured into config and ZERO create
#         mutations are issued — the resources are ADOPTED by name.
#
# Maps to FR-002 + FR-003 + SC-002 + SC-005.
#
# Mock strategy: every locate query returns the union of all known nodes;
# the seed step's name-match probe captures each existing UUID and skips
# the create (adopt). If ANY create fires, the assertion fails.
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

    local labels
    labels='[
{"id":"bbbb0001-1111-4111-1111-111111110001","name":"phase:specifying"},
{"id":"bbbb0002-1111-4111-1111-111111110002","name":"phase:clarifying"},
{"id":"bbbb0003-1111-4111-1111-111111110003","name":"phase:planning"},
{"id":"bbbb0004-1111-4111-1111-111111110004","name":"phase:tasking"},
{"id":"bbbb0005-1111-4111-1111-111111110005","name":"phase:red_team"},
{"id":"bbbb0006-1111-4111-1111-111111110006","name":"phase:implementing"},
{"id":"bbbb0007-1111-4111-1111-111111110007","name":"phase:analyzing"},
{"id":"bbbb0008-1111-4111-1111-111111110008","name":"phase:ready_to_merge"},
{"id":"bbbb0009-1111-4111-1111-111111110009","name":"phase:merged"},
{"id":"bbbb0011-1111-4111-1111-111111110011","name":"task-phase:1"},
{"id":"bbbb0012-1111-4111-1111-111111110012","name":"task-phase:2"},
{"id":"bbbb0013-1111-4111-1111-111111110013","name":"task-phase:3"},
{"id":"bbbb0014-1111-4111-1111-111111110014","name":"task-phase:4"},
{"id":"bbbb0015-1111-4111-1111-111111110015","name":"task-phase:5"},
{"id":"bbbb0016-1111-4111-1111-111111110016","name":"task-phase:6"},
{"id":"bbbb0017-1111-4111-1111-111111110017","name":"task-phase:7"},
{"id":"bbbb0018-1111-4111-1111-111111110018","name":"task-phase:8"},
{"id":"bbbb0019-1111-4111-1111-111111110019","name":"task-phase:9"},
{"id":"bbbb0021-1111-4111-1111-111111110021","name":"agent:claude"},
{"id":"bbbb0022-1111-4111-1111-111111110022","name":"agent:codex"}
]'

    # Every locate returns the union; the team-states query returns the stock
    # trio. The seed step's per-name probe matches each and adopts.
    integration::stage_response 'query' \
        "{\"data\":{\"workflowStates\":{\"nodes\":${nodes}},\"issueLabels\":{\"nodes\":${labels}},\"team\":{\"states\":{\"nodes\":${team_states}}}}}"

    # If a create ever fires (test failure), it lands a parseable response.
    integration::stage_response 'mutation' \
        '{"data":{"workflowStateCreate":{"success":true,"workflowState":{"id":"00000000-0000-4000-0000-000000000000","name":"Unexpected","type":"unstarted"}},"issueLabelCreate":{"success":true,"issueLabel":{"id":"00000000-0000-4000-0000-000000000000","name":"unexpected"}}}}'

    integration::stage_response 'default' '{"data":{}}'
}

@test "US5b: adopt — all required resources exist → zero create mutations (FR-002/SC-002)" {
    run integration::run_seed --team "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    [ "$status" -eq 0 ]

    # ZERO create mutations — everything adopted.
    local mutations
    mutations="$(integration::mutation_count)"
    [ "$mutations" -eq 0 ]

    # Queries DID fire (the adopt probe).
    [ "$(integration::query_count)" -ge 1 ]

    # Every persisted UUID captured into config (FR-008 shape / SC-005).
    [ -f "$LINEAR_CONFIG_PATH" ]
    for key in specifying clarifying planning tasking red_team \
               implementing analyzing ready_to_merge merged; do
        grep -qE "^[[:space:]]+${key}:" "$LINEAR_CONFIG_PATH"
    done
    grep -qE '^[[:space:]]+claude:' "$LINEAR_CONFIG_PATH"
    grep -qE '^[[:space:]]+codex:' "$LINEAR_CONFIG_PATH"

    # The captured workflow-state UUIDs are the EXISTING ones (adopted),
    # not the zero placeholder.
    grep -q 'cccccccc-0001-4ccc-cccc-cccccccccccc' "$LINEAR_CONFIG_PATH"
    ! grep -q '00000000-0000-0000-0000-000000000000' "$LINEAR_CONFIG_PATH"

    # The run reports the adopt/existing outcome.
    [[ "$output" == *"adopted"* ]] || [[ "$output" == *"existing"* ]]
}
