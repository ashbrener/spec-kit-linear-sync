#!/usr/bin/env bats
# shellcheck shell=bats
# =============================================================================
# tests/integration/us1-phase-header-nearmiss.bats — #34 broadened grammar
#
# Coverage for the #34 fix (spec 006, faithful projection — Part A):
#
#   The phase-header parser WAS colon-only (`^## Phase [0-9]+:`), so a
#   tasks.md whose headers used an em-dash delimiter (`## Phase 1 —
#   Setup`) — or a hyphen, or bare whitespace — matched NOTHING and
#   produced ZERO task-phase sub-issues (silently, pre-#45; loudly via a
#   near-miss WARNING after #45). Spec 006 BROADENS the grammar: the
#   canonical spec-kit em-dash form (and hyphen, and bare whitespace)
#   now parse to the SAME phase number + name the colon form would have,
#   so those headers DO produce sub-issues and DO NOT emit a near-miss
#   warning (FR-001/FR-002/FR-005). The near-miss safety net is narrowed
#   to genuinely unparseable lines (a worded number — covered by the
#   unit suite).
#
# Scenario:
#
#   GIVEN a `specs/006-emdash-phases/` directory whose tasks.md has two
#         `## Phase N — <Name>` (em-dash) headers and a clean Linear
#         state (no Issues match speckit-spec:006),
#   WHEN  `src/reconcile.sh --spec 006` runs,
#   THEN  the reconciler:
#           * exits 0,
#           * creates the two task-phase sub-issues (`Phase 1 — Setup`,
#             `Phase 2 — Foundational`), and
#           * emits NO near-miss warning for those (now-accepted) headers.
#
# Maps to #34, FR-001, FR-002, FR-005.
#
# Mock strategy mirrors us1-fresh-reconcile.bats: the default curl shim
# returns "no nodes" for locate queries and a fake-UUID payload for
# mutations. We assert on the call log + the summary text.
# =============================================================================

load '../helpers/integration-helpers'

setup() {
    integration::skip_unless_enabled
    integration::setup_sandbox '006-emdash-phases'
    integration::install_gh_shim_no_pr

    # Spec-issue locate → zero nodes (forces CREATE of the spec Issue).
    integration::stage_response 'query-LocateSpecIssue' \
        '{"data":{"issues":{"nodes":[]}}}'

    # Task-phase locate query → zero nodes for every phase. Forces the
    # CREATE path for each sub-issue (now that the em-dash grammar parses).
    integration::stage_response 'query-LocateTaskPhase' \
        '{"data":{"issues":{"nodes":[]}}}'

    # Generic query fallback — empty so reconcile sees no existing state.
    integration::stage_response 'query' \
        '{"data":{"issues":{"nodes":[]},"issue":{"blocks":{"nodes":[]}}}}'

    # Mutations always succeed and echo a stable fake UUID.
    integration::stage_response 'mutation' \
        '{"data":{"issueCreate":{"success":true,"issue":{"id":"11111111-1111-4111-1111-111111111111","identifier":"ACM-1","title":"created"}},"issueUpdate":{"success":true,"issue":{"id":"22222222-2222-4222-2222-222222222222","identifier":"ACM-2","title":"updated","state":{"id":"cccccccc-0004-4ccc-cccc-cccccccccccc"}}}}}'

    integration::stage_response 'default' '{"data":{}}'
}

@test "us1-broadened-grammar: em-dash headers create sub-issues and emit NO near-miss" {
    run integration::run_reconcile --spec 006

    # ---- exit code ----
    [ "$status" -eq 0 ]

    # ---- the two em-dash phase headers NOW produce sub-issues ----
    # The sub-issue title format is `Phase N — <Name>` (em-dash). After
    # the #34 broadening, the em-dash tasks.md headers parse to the same
    # number+name a colon header would, so these exact titles must appear
    # in a create mutation body. (Fails on pre-#34 code, which produced
    # ZERO sub-issues for em-dash headers.)
    local phase1_calls phase2_calls
    phase1_calls="$(integration::calls_containing 'Phase 1 — Setup')"
    [ "$phase1_calls" -ge 1 ] \
        || { echo "expected >=1 mutation referencing 'Phase 1 — Setup' (em-dash header must now parse), got ${phase1_calls}" >&2; false; }

    phase2_calls="$(integration::calls_containing 'Phase 2 — Foundational')"
    [ "$phase2_calls" -ge 1 ] \
        || { echo "expected >=1 mutation referencing 'Phase 2 — Foundational' (em-dash header must now parse), got ${phase2_calls}" >&2; false; }

    # ---- at least 3 mutations: 1 spec Issue + 2 sub-issues ----
    local mutations
    mutations="$(integration::mutation_count)"
    [ "$mutations" -ge 3 ]

    # ---- NO near-miss warning for the now-accepted headers (FR-005) ----
    # The distinctive near-miss substring must be ABSENT from the run
    # output (those em-dash headers are valid now, not near-misses).
    [[ "$output" != *"phase-like heading(s) not parsed"* ]] \
        || { echo "expected NO near-miss warning for accepted em-dash headers, but the summary emitted one" >&2; false; }
}
